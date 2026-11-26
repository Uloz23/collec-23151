-- =====================================================================
--  Collec' 23-151 : mise à jour n° 24
--  Remise à zéro complète d'un jeu depuis l'admin (scores, progression et récompenses
--  de tous les joueurs), par exemple au moment de l'ouvrir à tous après la phase de test.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite la mise à jour n° 21.)
-- =====================================================================

create or replace function public.admin_game_reset(p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a int; b int; c int;
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  delete from public.game_best where game = p_game;      get diagnostics a = row_count;
  delete from public.game_progress where game = p_game;  get diagnostics b = row_count;
  delete from public.game_rewards where game = p_game;   get diagnostics c = row_count;
  return jsonb_build_object('scores', a, 'progressions', b, 'recompenses', c);
end $$;
revoke execute on function public.admin_game_reset(text) from public, anon;
grant execute on function public.admin_game_reset(text) to authenticated;

select 'Mise à jour n° 24 installée' as resultat;
