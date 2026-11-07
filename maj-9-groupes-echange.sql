-- =====================================================================
--  Collec' 23-151 : mise à jour n° 9
--  Échanges par groupes de rareté : Gadz, communes et peu communes s'échangent entre elles ;
--  rares et mythiques (dont le .onscrit) s'échangent entre elles.
--  Groupes réglables dans l'admin (Réglages avancés : "trade_groups").
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite la mise à jour n° 8.)
-- =====================================================================

update public.settings set data = '{"trade_groups": [["gadz", "commune", "peu-commune"], ["rare", "mythique"]]}'::jsonb || data where id = 1;

-- Numéro du groupe d'échange d'une rareté (une rareté absente des groupes forme son propre groupe)
create or replace function public._trade_group(r text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select g.i::text from public.settings s, jsonb_array_elements(s.data->'trade_groups') with ordinality as g(arr, i)
                   where s.id = 1 and g.arr ? r limit 1), 'seule:' || r);
$$;
revoke all on function public._trade_group(text) from public, anon, authenticated;

create or replace function public.trade_propose(p_token uuid, p_to text, p_give_card int, p_give_variant text,
  p_want_card int, p_want_variant text, p_replaces bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); mep public.players%rowtype; t public.players%rowtype; old public.trades%rowtype; nid bigint;
begin
  perform public._trades_expire();
  select * into mep from public.players where id = me;
  if mep.is_test then raise exception 'echange_impossible'; end if;
  select * into t from public.players where lower(pseudo) = lower(btrim(p_to)) and not is_test;
  if t.id is null then raise exception 'joueur_introuvable'; end if;
  if t.id = me then raise exception 'pas_soi_meme'; end if;
  if not public._owns(me, p_give_card, p_give_variant) then raise exception 'carte_plus_la'; end if;
  if not public._owns(t.id, p_want_card, p_want_variant) then raise exception 'carte_plus_la'; end if;
  if public._trade_group((select rarity from public.cards where id = p_give_card)) is distinct from
     public._trade_group((select rarity from public.cards where id = p_want_card)) then
    raise exception 'rarete_differente'; end if;
  if coalesce((select (data->>'trade_same_variant')::boolean from public.settings where id = 1), true) and p_give_variant <> p_want_variant then
    raise exception 'version_differente'; end if;
  if (select count(*) from public.trades where from_id = me and status = 'attente') >= 15 then raise exception 'trop_echanges'; end if;
  if p_replaces is not null then
    select * into old from public.trades where id = p_replaces for update;
    if old.id is null or old.status <> 'attente' or not (me in (old.from_id, old.to_id)) or not (t.id in (old.from_id, old.to_id)) then
      raise exception 'echange_termine'; end if;
    update public.trades set status = 'modifiee', decided_at = now() where id = old.id;
  end if;
  insert into public.trades (from_id, to_id, give_card, give_variant, want_card, want_variant, replaces)
    values (me, t.id, p_give_card, p_give_variant, p_want_card, p_want_variant, p_replaces) returning id into nid;
  return nid;
end $$;

grant execute on function public.trade_propose(uuid, text, int, text, int, text, bigint) to anon, authenticated;

select 'Mise à jour n° 9 installée' as resultat;
