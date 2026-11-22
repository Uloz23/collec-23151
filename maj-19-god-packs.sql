-- =====================================================================
--  Collec' 23-151 : mise à jour n° 19
--  God packs à la hauteur de leur rareté :
--   - dorées et full art bien plus fréquentes (réglage "god_pack" > "variants") ;
--   - au moins une dorée ou full art garantie (réglage "god_pack" > "min") ;
--   - une commune ou une peu commune tirée dans un god pack est toujours dorée ou full art
--     (réglage "god_pack" > "forced") ;
--   - les autres cartes restent au moins brillantes.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite la mise à jour n° 12.)
-- =====================================================================

-- Réglage par défaut (ne remplace pas un réglage déjà présent)
update public.settings set data = jsonb_build_object('god_pack', jsonb_build_object(
    'variants', jsonb_build_object('doree', 0.04, 'textless', 0.20),
    'min', 1,
    'forced', jsonb_build_array('commune', 'peu-commune'),
    'doree_share', 0.2)) || data
  where id = 1;

-- Version « spéciale » imposée : dorée ou full art (part des dorées : doree_share)
create or replace function public._god_special(gp jsonb) returns text
language sql volatile as $$
  select case when random() < coalesce((gp->>'doree_share')::numeric, 0.2) then 'doree' else 'textless' end;
$$;
revoke all on function public._god_special(jsonb) from public, anon, authenticated;

create or replace function public.open_booster(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pid uuid := public._player(p_token); s jsonb; sv jsonb; gp jsonb; p record; god boolean; slots jsonb; slot jsonb;
        r text; cid int; v text; taken int[] := '{}'; vars text[] := '{}'; rars text[] := '{}';
        res jsonb := '[]'; is_new boolean; is_newv boolean; i int; n int; nspec int; k int;
begin
  perform public._accrue(pid);
  select data into s from public.settings where id = 1;
  select * into p from public.players where id = pid for update;
  if p.stock + p.gifts < 1 then raise exception 'pas_de_booster'; end if;
  god := random() < (s->>'god_rate')::numeric;
  slots := case when god then s->'god_slots' else s->'slots' end;
  gp := coalesce(s->'god_pack', '{}'::jsonb);
  -- dans un god pack, les probabilités de dorée / full art sont remplacées par celles de "god_pack"
  sv := case when god then s || jsonb_build_object('variants', coalesce(s->'variants', '{}'::jsonb) || coalesce(gp->'variants', '{}'::jsonb)) else s end;

  -- 1. Tirage des cartes et de leurs versions
  for slot in select * from jsonb_array_elements(slots) loop
    r := public._pick(slot);
    select id into cid from public.cards where published and rarity = r and id <> all(taken) order by random() limit 1;
    if cid is null then select id into cid from public.cards where published and rarity = r order by random() limit 1; end if;
    if cid is null then select id into cid from public.cards where published order by random() limit 1; end if;
    r := (select rarity from public.cards where id = cid);
    v := public._variant(sv, r);
    if god then
      if coalesce(gp->'forced', '[]'::jsonb) ? r and v not in ('doree', 'textless') then v := public._god_special(gp); end if;
      if v = 'normale' then v := 'brillante'; end if;
    end if;
    taken := taken || cid; vars := vars || v; rars := rars || r;
  end loop;
  n := coalesce(array_length(taken, 1), 0);

  -- 2. God pack : garantie d'un minimum de dorées / full art
  if god and n > 0 then
    select count(*) into nspec from unnest(vars) x where x in ('doree', 'textless');
    while nspec < least(coalesce((gp->>'min')::int, 1), n) loop
      select i0 into k from generate_subscripts(vars, 1) i0 where vars[i0] not in ('doree', 'textless') order by random() limit 1;
      exit when k is null;
      vars[k] := public._god_special(gp);
      nspec := nspec + 1;
    end loop;
  end if;

  -- 3. Enregistrement
  for i in 1 .. n loop
    cid := taken[i]; v := vars[i];
    is_new  := not exists (select 1 from public.owned where player_id = pid and card_id = cid);
    is_newv := v <> 'normale' and not exists (select 1 from public.owned where player_id = pid and card_id = cid and variant = v);
    insert into public.owned (player_id, card_id, variant) values (pid, cid, v)
      on conflict (player_id, card_id, variant) do update set count = public.owned.count + 1;
    insert into public.pulls (player_id, card_id, variant, god) values (pid, cid, v, god);
    res := res || jsonb_build_object('card_id', cid, 'variant', v, 'new_card', is_new, 'new_variant', is_newv);
  end loop;

  -- les boosters offerts partent en premier
  if p.gifts > 0 then
    update public.players set gifts = gifts - 1, gift_reason = case when gifts - 1 < 1 then null else gift_reason end where id = pid;
  else
    update public.players set stock = stock - 1, tick = case when stock >= (s->>'cap')::int then now() else tick end where id = pid;
  end if;
  return jsonb_build_object('god', god, 'pulls', res, 'state', public._state(pid));
end $$;

select 'Mise à jour n° 19 installée' as resultat;
