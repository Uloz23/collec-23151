-- =====================================================================
--  Collec' 23-151 : mise à jour n° 8
--  Échanges entre joueurs : une carte contre une carte de même rareté (variantes libres),
--  proposition valable 2 jours, annulable, modifiable (la modification remplace la proposition).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 3 et n° 6.)
-- =====================================================================

create table if not exists public.trades (
  id            bigserial primary key,
  from_id       uuid not null references public.players(id) on delete cascade,
  to_id         uuid not null references public.players(id) on delete cascade,
  give_card     int  not null references public.cards(id) on delete cascade,   -- donnée par from_id
  give_variant  text not null,
  want_card     int  not null references public.cards(id) on delete cascade,   -- donnée par to_id
  want_variant  text not null,
  status        text not null default 'attente',  -- attente, acceptee, refusee, annulee, expiree, modifiee, impossible
  replaces      bigint references public.trades(id) on delete set null,
  created_at    timestamptz not null default now(),
  decided_at    timestamptz
);
create index if not exists trades_to on public.trades (to_id, status);
create index if not exists trades_from on public.trades (from_id, status);
alter table public.trades enable row level security;
revoke all on public.trades from anon, authenticated;

-- Les propositions de plus de 2 jours expirent
create or replace function public._trades_expire() returns void
language sql security definer set search_path = public as $$
  update public.trades set status = 'expiree', decided_at = created_at + interval '2 days'
  where status = 'attente' and created_at < now() - interval '2 days';
$$;

create or replace function public._owns(pid uuid, cid int, v text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.owned where player_id = pid and card_id = cid and variant = v and count > 0);
$$;

-- Proposer un échange (ou modifier une proposition en cours : p_replaces)
create or replace function public.trade_propose(p_token uuid, p_to text, p_give_card int, p_give_variant text,
  p_want_card int, p_want_variant text, p_replaces bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); mep public.players%rowtype; t public.players%rowtype; old public.trades%rowtype; nid bigint;
begin
  perform public._trades_expire();
  select * into mep from public.players where id = me;
  if mep.is_test then raise exception 'echange_impossible'; end if;
  select * into t from public.players where lower(pseudo) = lower(btrim(p_to)) and not is_test;
  if t.id is null then raise exception 'joueur_introuvable'; end if;
  if t.id = me then raise exception 'pas_soi_meme'; end if;
  if not public._owns(me, p_give_card, p_give_variant) then raise exception 'carte_plus_la'; end if;
  if not public._owns(t.id, p_want_card, p_want_variant) then raise exception 'carte_plus_la'; end if;
  if (select rarity from public.cards where id = p_give_card) is distinct from (select rarity from public.cards where id = p_want_card) then
    raise exception 'rarete_differente'; end if;
  if (select count(*) from public.trades where from_id = me and status = 'attente') >= 15 then raise exception 'trop_echanges'; end if;
  if p_replaces is not null then
    select * into old from public.trades where id = p_replaces for update;
    if old.id is null or old.status <> 'attente' or not (me in (old.from_id, old.to_id)) or not (t.id in (old.from_id, old.to_id)) then
      raise exception 'echange_termine'; end if;
    update public.trades set status = 'modifiee', decided_at = now() where id = old.id;
  end if;
  insert into public.trades (from_id, to_id, give_card, give_variant, want_card, want_variant, replaces)
    values (me, t.id, p_give_card, p_give_variant, p_want_card, p_want_variant, p_replaces) returning id into nid;
  return nid;
end $$;

-- Mes échanges : en cours (reçus et envoyés) + ceux terminés ces 3 derniers jours
create or replace function public.trade_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  perform public._trades_expire();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', x.id, 'mine', x.from_id = me,
      'other', case when x.from_id = me then b.pseudo else a.pseudo end,
      'give_card', x.give_card, 'give_variant', x.give_variant, 'want_card', x.want_card, 'want_variant', x.want_variant,
      'status', x.status, 'created_at', x.created_at, 'decided_at', x.decided_at,
      'expires_at', x.created_at + interval '2 days') order by x.created_at desc)
    from public.trades x join public.players a on a.id = x.from_id join public.players b on b.id = x.to_id
    where (x.from_id = me or x.to_id = me) and (x.status = 'attente' or x.decided_at > now() - interval '3 days')), '[]'::jsonb);
end $$;

-- Répondre à une proposition reçue
create or replace function public.trade_answer(p_token uuid, p_id bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); x public.trades%rowtype;
begin
  perform public._trades_expire();
  select * into x from public.trades where id = p_id for update;
  if x.id is null or x.to_id <> me then raise exception 'echange_introuvable'; end if;
  if x.status <> 'attente' then raise exception 'echange_termine'; end if;
  if not p_accept then
    update public.trades set status = 'refusee', decided_at = now() where id = x.id;
    return public._state(me);
  end if;
  -- on verrouille les deux collections, puis on vérifie que chacun a toujours sa carte
  perform 1 from public.players where id in (x.from_id, x.to_id) order by id for update;
  if not public._owns(x.from_id, x.give_card, x.give_variant) or not public._owns(x.to_id, x.want_card, x.want_variant) then
    update public.trades set status = 'impossible', decided_at = now() where id = x.id;
    raise exception 'carte_plus_la';
  end if;
  -- la carte de celui qui propose part chez moi
  update public.owned set count = count - 1 where player_id = x.from_id and card_id = x.give_card and variant = x.give_variant;
  insert into public.owned (player_id, card_id, variant) values (x.to_id, x.give_card, x.give_variant)
    on conflict (player_id, card_id, variant) do update set count = public.owned.count + 1;
  -- ma carte part chez lui
  update public.owned set count = count - 1 where player_id = x.to_id and card_id = x.want_card and variant = x.want_variant;
  insert into public.owned (player_id, card_id, variant) values (x.from_id, x.want_card, x.want_variant)
    on conflict (player_id, card_id, variant) do update set count = public.owned.count + 1;
  delete from public.owned where player_id in (x.from_id, x.to_id) and count <= 0;
  update public.trades set status = 'acceptee', decided_at = now() where id = x.id;
  return public._state(me);
end $$;

-- Annuler sa propre proposition
create or replace function public.trade_cancel(p_token uuid, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  update public.trades set status = 'annulee', decided_at = now() where id = p_id and from_id = me and status = 'attente';
  if not found then raise exception 'echange_termine'; end if;
end $$;

-- Remise à zéro d'un compte : ses échanges disparaissent aussi
create or replace function public.admin_reset_players(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare s jsonb; n int;
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  select data into s from public.settings where id = 1;
  delete from public.owned where player_id = any(p_ids);
  delete from public.pulls where player_id = any(p_ids);
  delete from public.trades where from_id = any(p_ids) or to_id = any(p_ids);
  update public.players set stock = 0, gifts = coalesce((s->>'welcome_gifts')::int, 1), gift_reason = 'Booster de bienvenue',
         tick = now(), last_free_gift = null
    where id = any(p_ids);
  get diagnostics n = row_count; return n;
end $$;

revoke all on function public._trades_expire(), public._owns(uuid, int, text) from public, anon, authenticated;
grant execute on function public.trade_propose(uuid, text, int, text, int, text, bigint), public.trade_list(uuid),
  public.trade_answer(uuid, bigint, boolean), public.trade_cancel(uuid, bigint) to anon, authenticated;
grant execute on function public.admin_reset_players(uuid[]) to authenticated;
revoke execute on function public.admin_reset_players(uuid[]) from anon;

select 'Mise à jour n° 8 installée' as resultat;
