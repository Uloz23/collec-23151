-- =====================================================================
--  Collec' 23-151 : mise à jour n° 5
--  Deux couleurs réglables pour l'illustration des cartes sans photo (fond et motif).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

alter table public.cards add column if not exists color_bg text;
alter table public.cards add column if not exists color_fg text;

select 'Mise à jour n° 5 installée' as resultat;
