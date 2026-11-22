-- =====================================================================
--  Collec' 23-151 : mise à jour n° 19
--  God packs à la hauteur de leur rareté :
--   - au moins une dorée ET au moins une full art garanties (réglage "god_pack" > "min") ;
--   - les autres cartes ont aussi de bonnes chances d'être dorées ou full art ("god_pack" > "variants") ;
--   - une commune ou une peu commune tirée dans un god pack est toujours dorée ou full art ("forced") ;
--   - les cartes restantes sont au moins brillantes ;
--   - ceux qui ont le droit d'offrir (et l'admin) peuvent garantir que le(s) prochain(s) booster(s)
--     d'un joueur sera un god pack, sans lui ajouter de booster : avec un message, ou en toute discrétion.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ».
--  Relançable, mais remet le réglage "god_pack" à ses valeurs ci-dessous.
-- =====================================================================

update public.settings set data = data || jsonb_build_object('god_pack', jsonb_build_object(
    'variants', jsonb_build_object('doree', 0.10, 'textless', 0.25),
    'min', jsonb_build_object('doree', 1, 'textless', 1),
    'forced', jsonb_build_array('commune', 'peu-commune'),
    'doree_share', 0.3))
  where id = 1;

-- God packs garantis : nombre de prochains boosters qui seront des god packs, et le message éventuel
alter table public.players drop column if exists god_gifts;
alter table public.players add column if not exists god_next int not null default 0;
alter table public.players add column if not exists god_msg text;
drop function if exists public.gift_as_player(uuid, uuid[], int, text, boolean);
drop function if exists public.admin_gift_god(uuid[], int, text);

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

-- Version « spéciale » imposée : dorée ou full art (part des dorées : doree_share)
create or replace function public._god_special(gp jsonb) returns text
language sql volatile as $$
  select case when random() < coalesce((gp->>'doree_share')::numeric, 0.3) then 'doree' else 'textless' end;
$$;
revoke all on function public._god_special(jsonb) from public, anon, authenticated;

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
    insert into public.owned (player_id, card_id, variant) values (pid, cid, v)
      on conflict (player_id, card_id, variant) do update set count = public.owned.count + 1;
    insert into public.pulls (player_id, card_id, variant, god) values (pid, cid, v, god);
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

-- Garantir un god pack (sans ajouter de booster). p_msg vide ou p_discret = true : rien n'est signalé au joueur.
create or replace function public._god_bless(p_ids uuid[], p_except uuid, p_count int, p_msg text, p_discret boolean) returns int
language plpgsql security definer set search_path = public as $$
declare n int; msg text := case when p_discret then null else nullif(btrim(p_msg), '') end; r record;
begin
  if p_count < 1 or p_count > 20 then raise exception 'nombre_invalide'; end if;
  update public.players set god_next = god_next + p_count, god_msg = coalesce(msg, god_msg)
    where (p_except is null or id <> p_except) and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count;
  -- avec un message : une notification sur le téléphone (si la mise à jour n° 14 est installée)
  if msg is not null and to_regclass('public.push_queue') is not null then
    for r in select id from public.players where (p_except is null or id <> p_except) and (p_ids is null or id = any(p_ids)) and not is_test loop
      execute 'insert into public.push_queue (player_id, kind, title, body) values ($1, ''cadeau'', $2, $3)'
        using r.id, '✨ Ton prochain booster est un god pack', msg;
    end loop;
  end if;
  return n;
end $$;
revoke all on function public._god_bless(uuid[], uuid, int, text, boolean) from public, anon, authenticated;

-- Depuis l'appli (droit d'offrir) : le message est signé du pseudo
create or replace function public.god_bless(p_token uuid, p_ids uuid[], p_count int, p_msg text, p_discret boolean) returns int
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); ps text;
begin
  select pseudo into ps from public.players where id = me and can_gift;
  if ps is null then raise exception 'pas_autorise'; end if;
  return public._god_bless(p_ids, me, p_count,
    case when nullif(btrim(p_msg), '') is null then null else ps || ' : ' || btrim(p_msg) end, p_discret);
end $$;

-- Depuis l'admin
create or replace function public.admin_god_bless(p_ids uuid[], p_count int, p_msg text, p_discret boolean) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return public._god_bless(p_ids, null, p_count, p_msg, p_discret);
end $$;

grant execute on function public.god_bless(uuid, uuid[], int, text, boolean) to anon, authenticated;
revoke execute on function public.admin_god_bless(uuid[], int, text, boolean) from public, anon;
grant execute on function public.admin_god_bless(uuid[], int, text, boolean) to authenticated;

select 'Mise à jour n° 19 installée' as resultat;
