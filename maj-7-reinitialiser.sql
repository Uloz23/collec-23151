-- =====================================================================
--  Collec' 23-151 : mise à jour n° 7
--  Remettre des comptes à zéro (cartes, boosters, minuteur) sans les supprimer :
--  le pseudo et le code restent les mêmes.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite la mise à jour n° 6.)
-- =====================================================================

create or replace function public.admin_reset_players(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare s jsonb; n int;
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  select data into s from public.settings where id = 1;
  delete from public.owned where player_id = any(p_ids);
  delete from public.pulls where player_id = any(p_ids);
  update public.players set stock = 0, gifts = coalesce((s->>'welcome_gifts')::int, 1), gift_reason = 'Booster de bienvenue',
         tick = now(), last_free_gift = null
    where id = any(p_ids);
  get diagnostics n = row_count; return n;
end $$;

grant execute on function public.admin_reset_players(uuid[]) to authenticated;
revoke execute on function public.admin_reset_players(uuid[]) from anon;

select 'Mise à jour n° 7 installée' as resultat;
