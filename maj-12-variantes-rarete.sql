-- =====================================================================
--  Collec' 23-151 : mise à jour n° 12
--  Multiplicateur de variantes par rareté (Réglages avancés : "variant_boost").
--  Par défaut : mythiques × 3 (dorée, full art et brillante trois fois plus fréquentes).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

update public.settings set data = '{"variant_boost": {"mythique": 3}}'::jsonb || data where id = 1;

-- Tirage de la version d'une carte, avec le multiplicateur de sa rareté
create or replace function public._variant(s jsonb, r text) returns text
language plpgsql volatile as $$
declare m numeric := coalesce((s->'variant_boost'->>r)::numeric, 1);
        d numeric := (s->'variants'->>'doree')::numeric * m;
        t numeric := (s->'variants'->>'textless')::numeric * m;
        b numeric := (s->'variants'->>'brillante')::numeric * m;
        x numeric := random();
begin
  if d + t + b > 0.95 then  -- garde-fou : au moins 5 % de normales
    m := 0.95 / (d + t + b); d := d * m; t := t * m; b := b * m;
  end if;
  if x < d then return 'doree'; end if;
  if x < d + t then return 'textless'; end if;
  if x < d + t + b then return 'brillante'; end if;
  return 'normale';
end $$;
revoke all on function public._variant(jsonb, text) from public, anon, authenticated;

create or replace function public.open_booster(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pid uuid := public._player(p_token); s jsonb; p record; god boolean; slots jsonb; slot jsonb;
        r text; cid int; v text; taken int[] := '{}'; res jsonb := '[]'; is_new boolean; is_newv boolean;
begin
  perform public._accrue(pid);
  select data into s from public.settings where id = 1;
  select * into p from public.players where id = pid for update;
  if p.stock + p.gifts < 1 then raise exception 'pas_de_booster'; end if;
  god := random() < (s->>'god_rate')::numeric;
  slots := case when god then s->'god_slots' else s->'slots' end;
  for slot in select * from jsonb_array_elements(slots) loop
    r := public._pick(slot);
    select id into cid from public.cards where published and rarity = r and id <> all(taken) order by random() limit 1;
    if cid is null then select id into cid from public.cards where published and rarity = r order by random() limit 1; end if;
    if cid is null then select id into cid from public.cards where published order by random() limit 1; end if;
    taken := taken || cid;
    -- variantes boostées selon la rareté de la carte tirée (réglage "variant_boost")
    v := public._variant(s, (select rarity from public.cards where id = cid));
    if god and v = 'normale' then v := 'brillante'; end if;
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

select 'Mise à jour n° 12 installée' as resultat;
