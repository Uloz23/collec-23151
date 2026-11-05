-- =====================================================================
--  Collec' 23-151 : mise à jour n° 3
--  Compte de test : toutes les cartes et variantes débloquées, boosters illimités,
--  invisible pour les autres joueurs (classement, albums, liste pour offrir).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

alter table public.players add column if not exists is_test boolean not null default false;

-- Un compte test voit tout son album rempli (chaque carte publiée, dans les 4 versions)
create or replace function public._state(pid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'pseudo', p.pseudo, 'stock', p.stock, 'gifts', p.gifts, 'gift_reason', p.gift_reason,
    'can_gift', p.can_gift, 'is_test', p.is_test,
    'cap', (s.data->>'cap')::int,
    'next_at', case when p.stock >= (s.data->>'cap')::int then null else public._next_at(p.tick, s.data) end,
    'period_min', extract(epoch from public._period_at(now(), s.data)) / 60,
    'owned', case when p.is_test then
        coalesce((select jsonb_agg(jsonb_build_array(c.id, v.v, 1)) from public.cards c
                  cross join (values ('normale'), ('brillante'), ('textless'), ('doree')) as v(v) where c.published), '[]'::jsonb)
      else
        coalesce((select jsonb_agg(jsonb_build_array(o.card_id, o.variant, o.count)) from public.owned o where o.player_id = p.id), '[]'::jsonb)
      end
  )
  from public.players p, public.settings s where p.id = pid and s.id = 1;
$$;
revoke all on function public._state(uuid) from public, anon, authenticated;

-- Boosters illimités : la réserve d'un compte test reste toujours pleine
create or replace function public._test_refill() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.is_test then
    new.stock := greatest(new.stock, coalesce((select (data->>'cap')::int from public.settings where id = 1), 5));
  end if;
  return new;
end $$;
revoke all on function public._test_refill() from public, anon, authenticated;
drop trigger if exists players_test_refill on public.players;
create trigger players_test_refill before insert or update on public.players for each row execute function public._test_refill();

-- Invisible dans le classement
create or replace function public.leaderboard() returns table (pseudo text, cartes bigint, variantes bigint)
language sql stable security definer set search_path = public as $$
  select p.pseudo, count(distinct o.card_id), count(*) filter (where o.variant <> 'normale')
  from public.players p left join public.owned o on o.player_id = p.id
  where not p.is_test
  group by p.id order by 2 desc, 3 desc, p.pseudo;
$$;

-- Invisible pour ceux qui offrent des boosters depuis l'appli
create or replace function public.gift_targets(p_token uuid) returns table (id uuid, pseudo text, gifts int)
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  if not exists (select 1 from public.players x where x.id = me and x.can_gift) then raise exception 'pas_autorise'; end if;
  return query select p.id, p.pseudo, p.gifts from public.players p where p.id <> me and not p.is_test order by lower(p.pseudo);
end $$;

-- Son album ne peut pas être consulté par les autres
create or replace function public.player_album(p_token uuid, p_pseudo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid; target public.players%rowtype;
begin
  me := public._player(p_token);
  select * into target from public.players where lower(pseudo) = lower(trim(p_pseudo)) and not is_test;
  if target.id is null then raise exception 'joueur_introuvable'; end if;
  return jsonb_build_object(
    'pseudo', target.pseudo,
    'owned', coalesce((select jsonb_agg(jsonb_build_array(o.card_id, o.variant, o.count))
                       from public.owned o where o.player_id = target.id), '[]'::jsonb));
end $$;

-- L'admin coche ou décoche « Test »
create or replace function public.admin_set_test(p_id uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  update public.players set is_test = p_on where id = p_id;
end $$;

drop function if exists public.admin_players();
create function public.admin_players() returns table (id uuid, pseudo text, stock int, gifts int, cartes bigint, created_at timestamptz, last_seen timestamptz, can_gift boolean, is_test boolean)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return query select p.id, p.pseudo, p.stock, p.gifts, (select count(distinct card_id) from public.owned o where o.player_id = p.id), p.created_at, p.last_seen, p.can_gift, p.is_test
    from public.players p order by p.pseudo;
end $$;

grant execute on function public.leaderboard(), public.gift_targets(uuid), public.player_album(uuid, text) to anon, authenticated;
grant execute on function public.admin_set_test(uuid, boolean), public.admin_players() to authenticated;
revoke execute on function public.admin_set_test(uuid, boolean), public.admin_players() from anon;

select 'Mise à jour n° 3 installée' as resultat;
