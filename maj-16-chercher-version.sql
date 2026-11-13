-- =====================================================================
--  Collec' 23-151 : mise à jour n° 16
--  « Qui a cette version ? » : liste les joueurs qui possèdent une version précise d'une carte.
--  On ne peut chercher que des cartes qu'on a déjà (dans n'importe quelle version) : les autres restent une surprise.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

create or replace function public.variant_owners(p_token uuid, p_card int, p_variant text)
returns table (pseudo text, n int)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  if p_variant not in ('normale', 'brillante', 'textless', 'doree') then raise exception 'version_inconnue'; end if;
  if not exists (select 1 from public.cards where id = p_card and published) then raise exception 'carte_introuvable'; end if;
  if not exists (select 1 from public.owned where player_id = me and card_id = p_card and count > 0) then raise exception 'carte_pas_a_toi'; end if;
  return query
    select pl.pseudo::text, o.count::int
    from public.owned o join public.players pl on pl.id = o.player_id
    where o.card_id = p_card and o.variant = p_variant and o.count > 0 and pl.id <> me and not pl.is_test
    order by o.count desc, lower(pl.pseudo);
end $$;
grant execute on function public.variant_owners(uuid, int, text) to anon, authenticated;

select 'Mise à jour n° 16 installée' as resultat;
