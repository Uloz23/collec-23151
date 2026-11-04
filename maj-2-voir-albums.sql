-- Mise à jour n° 2 : voir l'album des autres joueurs (lecture seule)
-- À coller dans Supabase > SQL Editor, puis « Run ». Une seule fois suffit (la relancer ne casse rien).

create or replace function public.player_album(p_token uuid, p_pseudo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid; target public.players%rowtype;
begin
  me := public._player(p_token);
  select * into target from public.players where lower(pseudo) = lower(trim(p_pseudo));
  if target.id is null then raise exception 'joueur_introuvable'; end if;
  return jsonb_build_object(
    'pseudo', target.pseudo,
    'owned', coalesce((select jsonb_agg(jsonb_build_array(o.card_id, o.variant, o.count))
                       from public.owned o where o.player_id = target.id), '[]'::jsonb));
end $$;

revoke all on function public.player_album(uuid, text) from public;
grant execute on function public.player_album(uuid, text) to anon, authenticated;

select 'Mise à jour n° 2 installée' as resultat;
