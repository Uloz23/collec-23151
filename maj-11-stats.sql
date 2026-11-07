-- =====================================================================
--  Collec' 23-151 : mise à jour n° 11
--  Statistiques pour l'admin (onglet « Stats ») : boosters, variantes, échanges, par joueur et par heure.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 3 et n° 8.)
-- =====================================================================

create or replace function public.admin_stats_joueurs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  perform public._trades_expire();
  with pl as (select id, pseudo, last_seen from public.players where not is_test),
       pu as (select x.* from public.pulls x join pl on pl.id = x.player_id),
       tr as (select x.* from public.trades x where x.from_id in (select id from pl) and x.to_id in (select id from pl))
  select jsonb_build_object(
    'joueurs', (select count(*) from pl),
    'boosters', (select count(*) / 5 from pu),
    'god_packs', (select count(*) / 5 from pu where god),
    'cartes_tirees', (select count(*) from pu),
    'variantes', (select coalesce(jsonb_object_agg(variant, n), '{}'::jsonb) from (select variant, count(*) n from pu group by variant) v),
    'echanges', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from tr group by status) s),
    'par_joueur', (select coalesce(jsonb_agg(j order by (j->>'boosters')::int desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'pseudo', pl.pseudo,
          'boosters', (select count(*) / 5 from pu where pu.player_id = pl.id),
          'cartes', (select count(distinct card_id) from public.owned o where o.player_id = pl.id),
          'doree', (select count(*) from pu where pu.player_id = pl.id and variant = 'doree'),
          'textless', (select count(*) from pu where pu.player_id = pl.id and variant = 'textless'),
          'brillante', (select count(*) from pu where pu.player_id = pl.id and variant = 'brillante'),
          'echanges_proposes', (select count(*) from tr where tr.from_id = pl.id and tr.status <> 'modifiee'),
          'echanges_faits', (select count(*) from tr where (tr.from_id = pl.id or tr.to_id = pl.id) and tr.status = 'acceptee'),
          'vu', pl.last_seen) j
        from pl) q),
    'par_heure', (select coalesce(jsonb_agg(jsonb_build_object('h', h, 'boosters', n) order by h), '[]'::jsonb) from (
        select date_trunc('hour', created_at) h, count(*) / 5 n from pu where created_at > now() - interval '3 days' group by 1) t),
    'belles_cartes', (select coalesce(jsonb_agg(jsonb_build_object('pseudo', p.pseudo, 'carte', c.name, 'variante', x.variant, 'quand', x.created_at) order by x.created_at desc), '[]'::jsonb)
        from (select * from pu where variant in ('doree', 'textless') order by created_at desc limit 30) x
        join public.players p on p.id = x.player_id join public.cards c on c.id = x.card_id),
    'cartes_jamais_tirees', (select coalesce(jsonb_agg(c.name order by c.id), '[]'::jsonb) from public.cards c
        where c.published and not exists (select 1 from pu where pu.card_id = c.id)),
    'cartes_populaires', (select coalesce(jsonb_agg(jsonb_build_object('carte', name, 'n', n) order by n desc), '[]'::jsonb) from (
        select c.name, count(*) n from pu join public.cards c on c.id = pu.card_id group by c.name order by count(*) desc limit 8) t)
  ) into r;
  return r;
end $$;

grant execute on function public.admin_stats_joueurs() to authenticated;
revoke execute on function public.admin_stats_joueurs() from anon;

select 'Mise à jour n° 11 installée' as resultat;
