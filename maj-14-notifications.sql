-- =====================================================================
--  Collec' 23-151 : mise à jour n° 14
--  Notifications sur le téléphone (réserve pleine, rappel de 19 h, booster offert, échanges).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 3, 6 et 8.)
--  Le réveil automatique (cron) est installé à part, à l'étape suivante du guide.
-- =====================================================================

-- Téléphones abonnés et leurs choix
create table if not exists public.push_subs (
  id          bigserial primary key,
  player_id   uuid not null references public.players(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  prefs       jsonb not null default '{"full": true, "rappel": true, "cadeau": true, "echange": true}'::jsonb,
  created_at  timestamptz not null default now()
);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from anon, authenticated;

-- Notifications en attente d'envoi (cadeaux, échanges)
create table if not exists public.push_queue (
  id          bigserial primary key,
  player_id   uuid not null references public.players(id) on delete cascade,
  kind        text not null,            -- cadeau, echange
  title       text not null,
  body        text not null,
  url         text not null default './',
  created_at  timestamptz not null default now()
);
alter table public.push_queue enable row level security;
revoke all on public.push_queue from anon, authenticated;

-- Ce qui a déjà été signalé (pour ne pas répéter)
alter table public.players add column if not exists full_notified boolean not null default false;
alter table public.players add column if not exists reminded_on date;

-- ---------- Côté joueur : s'abonner, régler, se désabonner ----------
create or replace function public.push_subscribe(p_token uuid, p_endpoint text, p_p256dh text, p_auth text, p_prefs jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  insert into public.push_subs (player_id, endpoint, p256dh, auth, prefs)
    values (me, p_endpoint, p_p256dh, p_auth, coalesce(p_prefs, '{"full": true, "rappel": true, "cadeau": true, "echange": true}'::jsonb))
  on conflict (endpoint) do update set player_id = me, p256dh = excluded.p256dh, auth = excluded.auth,
    prefs = coalesce(p_prefs, public.push_subs.prefs);
end $$;

create or replace function public.push_prefs(p_token uuid, p_endpoint text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  return (select prefs from public.push_subs where endpoint = p_endpoint and player_id = me);
end $$;

create or replace function public.push_unsubscribe(p_token uuid, p_endpoint text) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  delete from public.push_subs where endpoint = p_endpoint and player_id = me;
end $$;

-- ---------- Déclencheurs : cadeaux et échanges ----------
create or replace function public._push_on_gift() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.gifts > old.gifts and not new.is_test then
    insert into public.push_queue (player_id, kind, title, body)
      values (new.id, 'cadeau', '🎁 Booster offert', coalesce(nullif(new.gift_reason, ''), 'Un booster t''attend dans ta collec''.'));
  end if;
  return new;
end $$;
drop trigger if exists players_push_gift on public.players;
create trigger players_push_gift after update of gifts on public.players for each row execute function public._push_on_gift();

create or replace function public._push_on_trade() returns trigger
language plpgsql security definer set search_path = public as $$
declare a text; b text;
begin
  select pseudo into a from public.players where id = new.from_id;
  select pseudo into b from public.players where id = new.to_id;
  if tg_op = 'INSERT' and new.status = 'attente' then
    insert into public.push_queue (player_id, kind, title, body, url)
      values (new.to_id, 'echange', '⇄ Proposition d''échange', a || ' te propose un échange.', './#fams');
  elsif tg_op = 'UPDATE' and old.status = 'attente' and new.status in ('acceptee', 'refusee') then
    insert into public.push_queue (player_id, kind, title, body, url)
      values (new.from_id, 'echange', case when new.status = 'acceptee' then '⇄ Échange accepté' else 'Échange refusé' end,
              b || case when new.status = 'acceptee' then ' a accepté ton échange !' else ' a refusé ton échange.' end, './#fams');
  end if;
  return new;
end $$;
drop trigger if exists trades_push on public.trades;
create trigger trades_push after insert or update of status on public.trades for each row execute function public._push_on_trade();

-- ---------- Appelée par la fonction serveur : la liste des notifications à envoyer ----------
create or replace function public.push_collect() returns jsonb
language plpgsql security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; r record; cap int; ids bigint[]; paris timestamp := now() at time zone 'Europe/Paris';
        msgs text[] := array[
          'Tes boosters t''attendent : viens les ouvrir !',
          'Il y a des cartes à découvrir dans ta collec''.',
          'Tes boosters s''accumulent, la fam''s avance sans toi !',
          'Un petit booster avant de dîner ?'];
begin
  select (data->>'cap')::int into cap from public.settings where id = 1;

  -- 1. Réserve pleine (une fois, jusqu'à ce que la réserve redescende)
  for r in select id from public.players where not is_test and exists (select 1 from public.push_subs s where s.player_id = players.id) loop
    perform public._accrue(r.id);
  end loop;
  update public.players set full_notified = false where full_notified and stock < cap;
  for r in select p.id from public.players p where not p.is_test and not p.full_notified and p.stock >= cap loop
    insert into public.push_queue (player_id, kind, title, body)
      values (r.id, 'full', '🎴 Réserve pleine', 'Ouvre un booster pour ne pas en perdre !');
    update public.players set full_notified = true where id = r.id;
  end loop;

  -- 2. Rappel de 19 h (heure de Paris) : au moins 2 boosters en attente et pas venu aujourd'hui
  if extract(hour from paris) = 19 then
    for r in select p.id from public.players p
             where not p.is_test and p.stock + p.gifts >= 2
               and (p.reminded_on is null or p.reminded_on < paris::date)
               and (p.last_seen is null or (p.last_seen at time zone 'Europe/Paris')::date < paris::date) loop
      insert into public.push_queue (player_id, kind, title, body)
        values (r.id, 'rappel', 'Collec'' 23-151', msgs[1 + floor(random() * array_length(msgs, 1))::int]);
      update public.players set reminded_on = paris::date where id = r.id;
    end loop;
  end if;

  -- 3. On assemble les messages pour chaque téléphone abonné, selon ses choix, puis on vide la file
  select array_agg(id) into ids from public.push_queue;
  select coalesce(jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth,
           'title', q.title, 'body', q.body, 'url', q.url, 'tag', q.kind)), '[]'::jsonb)
    into out
    from public.push_queue q join public.push_subs s on s.player_id = q.player_id
   where q.id = any(ids) and coalesce((s.prefs->>q.kind)::boolean, true);
  delete from public.push_queue where id = any(ids);
  return out;
end $$;

-- Téléphones qui n'existent plus (désinstallés, autorisation retirée)
create or replace function public.push_gone(p_endpoints text[]) returns void
language sql security definer set search_path = public as $$
  delete from public.push_subs where endpoint = any(p_endpoints);
$$;

revoke all on function public._push_on_gift(), public._push_on_trade() from public, anon, authenticated;
revoke all on function public.push_collect(), public.push_gone(text[]) from public, anon, authenticated;
grant execute on function public.push_collect(), public.push_gone(text[]) to service_role;
grant execute on function public.push_subscribe(uuid, text, text, text, jsonb), public.push_prefs(uuid, text),
  public.push_unsubscribe(uuid, text) to anon, authenticated;

select 'Mise à jour n° 14 installée' as resultat;
