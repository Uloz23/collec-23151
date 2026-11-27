-- =====================================================================
--  Collec' 23-151 : mise à jour n° 26
--  Mon rang dans la fam's sur chaque piste d'un jeu (pour l'écran « Ma progression » de Monome Hero).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite la mise à jour n° 21.)
-- =====================================================================

create or replace function public.game_my_ranks(p_token uuid, p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  return coalesce((
    select jsonb_object_agg(track, jsonb_build_object('rank', rk, 'of', n))
      from (select b.track, b.player_id,
                   rank() over (partition by b.track order by b.score desc) as rk,
                   count(*) over (partition by b.track) as n
              from public.game_best b join public.players p on p.id = b.player_id
             where b.game = p_game and not p.is_test and b.track not like 'semaine/%') x
     where x.player_id = me), '{}'::jsonb);
end $$;
grant execute on function public.game_my_ranks(uuid, text) to anon, authenticated;

select 'Mise à jour n° 26 installée' as resultat;
