-- =====================================================================
--  Collec' 23-151 : mise à jour n° 17
--  Les dorées et les full art s'échangent entre elles quelle que soit la rareté
--  (une dorée de Gadz contre une dorée de mythique, par exemple).
--  Réglable dans l'admin (Réglages : case « les dorées et les full art s'échangent entre elles… »).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

update public.settings set data = '{"trade_free_variants": ["doree", "textless"]}'::jsonb || data where id = 1;

create or replace function public.trade_propose(p_token uuid, p_to text, p_give_card int, p_give_variant text,
  p_want_card int, p_want_variant text, p_replaces bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); mep public.players%rowtype; t public.players%rowtype; old public.trades%rowtype; nid bigint;
  libre boolean;
begin
  perform public._trades_expire();
  select * into mep from public.players where id = me;
  if mep.is_test then raise exception 'echange_impossible'; end if;
  select * into t from public.players where lower(pseudo) = lower(btrim(p_to)) and not is_test;
  if t.id is null then raise exception 'joueur_introuvable'; end if;
  if t.id = me then raise exception 'pas_soi_meme'; end if;
  if not public._owns(me, p_give_card, p_give_variant) then raise exception 'carte_plus_la'; end if;
  if not public._owns(t.id, p_want_card, p_want_variant) then raise exception 'carte_plus_la'; end if;
  -- Même version « libre » des deux côtés (dorée contre dorée, full art contre full art) : la rareté ne compte pas
  libre := p_give_variant = p_want_variant and coalesce((select data->'trade_free_variants' ? p_give_variant from public.settings where id = 1), false);
  if not libre and public._trade_group((select rarity from public.cards where id = p_give_card)) is distinct from
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

select 'Mise à jour n° 17 installée' as resultat;
