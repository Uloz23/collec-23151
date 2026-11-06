-- =====================================================================
--  Collec' 23-151 : mise à jour n° 6
--  Chaque joueur peut offrir un booster gratuit à un autre joueur,
--  une fois par heure pendant le week-end, une fois par jour sinon (réglable dans l'admin).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 1 et n° 3.)
-- =====================================================================

alter table public.players add column if not exists last_free_gift timestamptz;

-- Réglages par défaut (n'écrase pas des réglages déjà faits)
update public.settings set data = '{"free_gift_on": true, "free_gift_weekend_min": 60, "free_gift_min": 1440}'::jsonb || data where id = 1;

-- Délai entre deux cadeaux, selon qu'on est pendant le week-end ou non
create or replace function public._free_period(t timestamptz, s jsonb) returns interval
language sql immutable as $$
  select case when t >= (s->>'weekend_start')::timestamptz and t < (s->>'weekend_end')::timestamptz
    then make_interval(mins => coalesce((s->>'free_gift_weekend_min')::int, 60))
    else make_interval(mins => coalesce((s->>'free_gift_min')::int, 1440)) end;
$$;

create or replace function public._state(pid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'pseudo', p.pseudo, 'stock', p.stock, 'gifts', p.gifts, 'gift_reason', p.gift_reason,
    'can_gift', p.can_gift, 'is_test', p.is_test,
    'cap', (s.data->>'cap')::int,
    'next_at', case when p.stock >= (s.data->>'cap')::int then null else public._next_at(p.tick, s.data) end,
    'period_min', extract(epoch from public._period_at(now(), s.data)) / 60,
    'free_on', coalesce((s.data->>'free_gift_on')::boolean, true) and not p.is_test,
    'free_next', case when p.last_free_gift is null or p.last_free_gift + public._free_period(now(), s.data) <= now() then null
                      else p.last_free_gift + public._free_period(now(), s.data) end,
    'free_min', extract(epoch from public._free_period(now(), s.data)) / 60,
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

-- Offrir son booster gratuit à un autre joueur (par son pseudo)
create or replace function public.free_gift(p_token uuid, p_pseudo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); p public.players%rowtype; t public.players%rowtype; s jsonb;
begin
  select data into s from public.settings where id = 1;
  select * into p from public.players where id = me for update;
  if not coalesce((s->>'free_gift_on')::boolean, true) or p.is_test then raise exception 'cadeau_ferme'; end if;
  if p.last_free_gift is not null and p.last_free_gift + public._free_period(now(), s) > now() then raise exception 'cadeau_attente'; end if;
  select * into t from public.players where lower(pseudo) = lower(btrim(p_pseudo)) and not is_test;
  if t.id is null then raise exception 'joueur_introuvable'; end if;
  if t.id = me then raise exception 'pas_soi_meme'; end if;
  update public.players set gifts = gifts + 1, gift_reason = 'Offert par ' || p.pseudo where id = t.id;
  update public.players set last_free_gift = now() where id = me;
  return public._state(me);
end $$;

revoke all on function public._free_period(timestamptz, jsonb) from public, anon, authenticated;
grant execute on function public.free_gift(uuid, text) to anon, authenticated;

select 'Mise à jour n° 6 installée' as resultat;
