-- =====================================================================
--  Collec' 23-151 : mise à jour n° 20
--  Mode test sans trace : un compte passé en test peut ouvrir des boosters sans que les cartes
--  soient ajoutées à sa vraie collection, et quand on le repasse en normal, sa réserve
--  (boosters, cadeaux, god packs garantis) revient exactement à ce qu'elle était avant le test.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 3 et 19.)
-- =====================================================================

alter table public.players add column if not exists test_saved jsonb;

-- Passage en test : on met la réserve de côté ; retour en normal : on la remet
create or replace function public._test_save() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.is_test and not old.is_test then
    new.test_saved := jsonb_build_object('stock', old.stock, 'gifts', old.gifts, 'gift_reason', old.gift_reason,
                                         'tick', old.tick, 'god_next', old.god_next, 'god_msg', old.god_msg);
  elsif old.is_test and not new.is_test and old.test_saved is not null then
    new.stock := (old.test_saved->>'stock')::int;
    new.gifts := (old.test_saved->>'gifts')::int;
    new.gift_reason := old.test_saved->>'gift_reason';
    new.tick := (old.test_saved->>'tick')::timestamptz;
    new.god_next := coalesce((old.test_saved->>'god_next')::int, 0);
    new.god_msg := old.test_saved->>'god_msg';
    new.test_saved := null;
  end if;
  return new;
end $$;
revoke all on function public._test_save() from public, anon, authenticated;
drop trigger if exists players_test_save on public.players;
create trigger players_test_save before update of is_test on public.players
  for each row execute function public._test_save();

create or replace function public.open_booster(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pid uuid := public._player(p_token); s jsonb; sv jsonb; gp jsonb; p record; god boolean; slots jsonb; slot jsonb;
        r text; cid int; v text; taken int[] := '{}'; vars text[] := '{}'; rars text[] := '{}';
        res jsonb := '[]'; is_new boolean; is_newv boolean; i int; n int; nspec int; k int; t text; m int;
begin
  perform public._accrue(pid);
  select data into s from public.settings where id = 1;
  select * into p from public.players where id = pid for update;
  if p.stock + p.gifts < 1 then raise exception 'pas_de_booster'; end if;
  -- un god pack garanti passe en premier, sinon le hasard
  god := p.god_next > 0 or random() < (s->>'god_rate')::numeric;
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

  -- 2. God pack : minimum garanti de chaque version spéciale ("min" : {"doree": 1, "textless": 1})
  if god and n > 0 then
    for t, m in select key, value::int from jsonb_each_text(
        case when jsonb_typeof(gp->'min') = 'object' then gp->'min'
             else jsonb_build_object('textless', coalesce((gp->>'min')::int, 1)) end)
        order by case key when 'doree' then 0 else 1 end loop
      select count(*) into nspec from unnest(vars) x where x = t;
      while nspec < m loop
        -- on améliore d'abord une carte qui n'est ni dorée ni full art
        select i0 into k from generate_subscripts(vars, 1) i0 where vars[i0] not in ('doree', 'textless') order by random() limit 1;
        -- sinon une carte d'une autre version spéciale déjà au-delà de son minimum
        if k is null then
          select i0 into k from generate_subscripts(vars, 1) i0
           where vars[i0] in ('doree', 'textless') and vars[i0] <> t
             and (select count(*) from unnest(vars) y where y = vars[i0]) > coalesce((gp->'min'->>vars[i0])::int, 0)
           order by random() limit 1;
        end if;
        exit when k is null;
        vars[k] := t;
        nspec := nspec + 1;
      end loop;
    end loop;
  end if;

  -- 3. Enregistrement
  for i in 1 .. n loop
    cid := taken[i]; v := vars[i];
    is_new  := not exists (select 1 from public.owned where player_id = pid and card_id = cid);
    is_newv := v <> 'normale' and not exists (select 1 from public.owned where player_id = pid and card_id = cid and variant = v);
    -- compte en mode test : on montre le tirage, mais rien n'est enregistré
    if not p.is_test then
      insert into public.owned (player_id, card_id, variant) values (pid, cid, v)
        on conflict (player_id, card_id, variant) do update set count = public.owned.count + 1;
      insert into public.pulls (player_id, card_id, variant, god) values (pid, cid, v, god);
    end if;
    res := res || jsonb_build_object('card_id', cid, 'variant', v, 'new_card', is_new, 'new_variant', is_newv);
  end loop;

  -- les boosters offerts partent en premier
  if p.gifts > 0 then
    update public.players set gifts = gifts - 1,
      gift_reason = case when gifts - 1 < 1 then null else gift_reason end where id = pid;
  else
    update public.players set stock = stock - 1, tick = case when stock >= (s->>'cap')::int then now() else tick end where id = pid;
  end if;
  -- le god pack garanti est consommé ; son message n'est montré qu'une fois
  if p.god_next > 0 then update public.players set god_next = god_next - 1, god_msg = null where id = pid; end if;
  return jsonb_build_object('god', god, 'god_msg', case when p.god_next > 0 then p.god_msg end,
                            'pulls', res, 'state', public._state(pid));
end $$;

select 'Mise à jour n° 20 installée' as resultat;
