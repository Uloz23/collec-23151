-- =====================================================================
--  Collec' 23-151 : mise à jour n° 1
--  Permet à l'admin d'autoriser un joueur à offrir des boosters depuis l'appli.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

alter table public.players add column if not exists can_gift boolean not null default false;

-- L'état du joueur indique s'il peut offrir
create or replace function public._state(pid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'pseudo', p.pseudo, 'stock', p.stock, 'gifts', p.gifts, 'gift_reason', p.gift_reason,
    'can_gift', p.can_gift,
    'cap', (s.data->>'cap')::int,
    'next_at', case when p.stock >= (s.data->>'cap')::int then null else public._next_at(p.tick, s.data) end,
    'period_min', extract(epoch from public._period_at(now(), s.data)) / 60,
    'owned', coalesce((select jsonb_agg(jsonb_build_array(o.card_id, o.variant, o.count)) from public.owned o where o.player_id = p.id), '[]'::jsonb)
  )
  from public.players p, public.settings s where p.id = pid and s.id = 1;
$$;
revoke all on function public._state(uuid) from public, anon, authenticated;

-- Liste des joueurs, pour celui qui a le droit d'offrir
create or replace function public.gift_targets(p_token uuid) returns table (id uuid, pseudo text, gifts int)
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  if not exists (select 1 from public.players x where x.id = me and x.can_gift) then raise exception 'pas_autorise'; end if;
  return query select p.id, p.pseudo, p.gifts from public.players p where p.id <> me order by lower(p.pseudo);
end $$;

-- Offrir depuis l'appli (on ne peut pas s'offrir à soi-même)
create or replace function public.gift_as_player(p_token uuid, p_ids uuid[], p_count int, p_reason text) returns int
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); n int;
begin
  if not exists (select 1 from public.players where id = me and can_gift) then raise exception 'pas_autorise'; end if;
  if p_count < 1 or p_count > 20 then raise exception 'nombre_invalide'; end if;
  update public.players set gifts = gifts + p_count, gift_reason = coalesce(nullif(btrim(p_reason), ''), 'Booster offert')
    where id <> me and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count; return n;
end $$;

-- L'admin donne ou retire le droit d'offrir
create or replace function public.admin_set_gifter(p_id uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  update public.players set can_gift = p_on where id = p_id;
end $$;

-- La liste des joueurs de l'admin montre ce droit
drop function if exists public.admin_players();
create function public.admin_players() returns table (id uuid, pseudo text, stock int, gifts int, cartes bigint, created_at timestamptz, last_seen timestamptz, can_gift boolean)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return query select p.id, p.pseudo, p.stock, p.gifts, (select count(distinct card_id) from public.owned o where o.player_id = p.id), p.created_at, p.last_seen, p.can_gift
    from public.players p order by p.pseudo;
end $$;

grant execute on function public.gift_targets(uuid), public.gift_as_player(uuid, uuid[], int, text) to anon, authenticated;
grant execute on function public.admin_set_gifter(uuid, boolean), public.admin_players() to authenticated;
revoke execute on function public.admin_set_gifter(uuid, boolean), public.admin_players() from anon;

select 'Mise à jour n° 1 installée' as resultat;
