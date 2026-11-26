-- =====================================================================
--  Collec' 23-151 : mise à jour n° 22
--  Monôme Héro : nom, vignette, réglages (score maximum, récompenses, noms des pistes)
--  et record de la fam's pour chaque piste, affiché dans « Meilleurs scores » du jeu.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger
--  (l'état du jeu, « à venir », « test » ou « ouvert », n'est pas modifié).
--  (Nécessite la mise à jour n° 21.)
-- =====================================================================

update public.games set
  name = 'Monôme Héro',
  description = 'Suis le rythme des chants de chaque tabagn''s et fais grandir ton monôme.',
  image = 'jeux/rythme/vignette.png',
  settings = jsonb_build_object(
    'version', '1',
    'max_score', 3000000,
    'reward_daily_cap', 2,
    'rewards', jsonb_build_array(
      jsonb_build_object('id', 'decouverte', 'track', '%/court/facile', 'min_accuracy', 70, 'boosters', 1, 'reason', 'Nouveau chant réussi'),
      jsonb_build_object('id', 'virtuose', 'track', '%/difficile', 'min_accuracy', 90, 'boosters', 1, 'reason', '90 % en difficile')),
    'labels', jsonb_build_object(
      'bordels', 'Monôme de Bordel''s', 'chalons', 'La cousine Lison', 'boquette', 'Dans les rues',
      'cluns', 'Monôme de Clun''s', 'birse', 'Monôme de Birse', 'court', 'courte', 'entier', 'entière'))
  where id = 'rythme';

-- Meilleur score de la fam's sur chaque piste d'un jeu (comptes test exclus)
create or replace function public.game_tops(p_game text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(track, jsonb_build_object('pseudo', pseudo, 'score', score, 'accuracy', accuracy)), '{}'::jsonb)
  from (select distinct on (b.track) b.track, p.pseudo::text as pseudo, b.score, b.accuracy
          from public.game_best b join public.players p on p.id = b.player_id
         where b.game = p_game and not p.is_test
         order by b.track, b.score desc, b.at) x;
$$;
grant execute on function public.game_tops(text) to anon, authenticated;

select 'Mise à jour n° 22 installée' as resultat;
