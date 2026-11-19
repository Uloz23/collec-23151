-- =====================================================================
--  Collec' 23-151 : mise à jour n° 18
--  Case « Viscrit » sur les cartes Gadz : la carte affiche « Viscrit » à la place de la génération (Pn).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

alter table public.cards add column if not exists viscrit boolean not null default false;

select 'Mise à jour n° 18 installée' as resultat;
