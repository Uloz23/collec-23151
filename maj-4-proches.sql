-- =====================================================================
--  Collec' 23-151 : mise à jour n° 4
--  Cartes de proches d'un gadz (Za, Zon, pote, enfant…) : type Gadz avec un sous-type.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

alter table public.cards add column if not exists kind text;

select 'Mise à jour n° 4 installée' as resultat;
