-- =====================================================================
--  Collec' 23-151 : mise à jour n° 15
--  Une carte dépubliée (décochée « Publiée » dans l'admin) ne compte plus dans le classement,
--  même si des joueurs l'ont déjà. Leur exemplaire est conservé : il réapparaîtra si la carte est republiée.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

create or replace function public.leaderboard() returns table (pseudo text, cartes bigint, variantes bigint)
language sql stable security definer set search_path = public as $$
  select p.pseudo,
         count(distinct o.card_id) filter (where c.published),
         count(*) filter (where c.published and o.variant <> 'normale')
  from public.players p
  left join public.owned o on o.player_id = p.id
  left join public.cards c on c.id = o.card_id
  where not p.is_test
  group by p.id
  order by 2 desc, 3 desc, p.pseudo;
$$;
grant execute on function public.leaderboard() to anon, authenticated;

select 'Mise à jour n° 15 installée' as resultat;
