-- =====================================================================
--  Collec' 23-151 : mise à jour n° 25
--  Récompenses de Monome Hero :
--   - 1 booster pour chaque version (chant × version × difficulté) réussie à 70 %, sans plafond ;
--   - version « Maître » d'une carte Chant quand ses 6 pistes sont réussies à 90 % ;
--   - carte hors-série pour un sans-faute (aucune note ratée) sur les 30 pistes ;
--   - chant de la semaine : 1 booster à la première partie à 80 %, et 5 boosters dont un god pack
--     garanti pour le ou les meilleurs scores (ex aequo tous récompensés).
--  Cartes hors-série : jamais dans les boosters, ni échangeables, comptées à part.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 19 à 23.)
-- =====================================================================

alter table public.cards add column if not exists hors_serie boolean not null default false;
alter table public.owned drop constraint if exists owned_variant_check;

-- ---------- Réglages du jeu ----------
-- Cartes Chant qui reçoivent la version Maître (retrouvées par leur nom ; modifiables ensuite dans l'admin)
update public.games set settings = (settings - 'reward_daily_cap') || jsonb_build_object(
  'rewards', jsonb_build_array(
    jsonb_build_object('id', 'valide', 'track', '%/%/%', 'min_accuracy', 70, 'boosters', 1, 'reason', 'Version réussie'),
    jsonb_build_object('id', 'semaine80', 'track', 'semaine/%', 'min_accuracy', 80, 'boosters', 1, 'reason', 'Chant de la semaine réussi')),
  'maitre_min', 90, 'maitre_tracks', 6,
  'maitre', coalesce(settings->'maitre', jsonb_strip_nulls(jsonb_build_object(
    'bordels',  (select id from public.cards where name ilike 'Mon_me de Bordel%' order by id limit 1),
    'chalons',  (select id from public.cards where name ilike '%cousine Lison%' order by id limit 1),
    'boquette', (select id from public.cards where name ilike 'Dans les rues%' order by id limit 1),
    'cluns',    (select id from public.cards where name ilike 'Mon_me de Clun%' order by id limit 1),
    'birse',    (select id from public.cards where name ilike 'Mon_me de Birse%' order by id limit 1)))),
  'fc_tracks', 30,
  'weekly', coalesce(settings->'weekly', jsonb_build_object(
    'songs', jsonb_build_array('bordels', 'chalons', 'boquette', 'cluns', 'birse'),
    'levels', jsonb_build_array('difficile', 'tres'),
    'boosters', 5, 'god', 1)))
  where id = 'rythme';

-- ---------- Chant de la semaine ----------
create table if not exists public.game_weekly (
  week     date not null,                 -- lundi de la semaine (heure de Paris)
  game     text not null references public.games(id) on delete cascade,
  song     text not null,
  pos      numeric not null,              -- position de l'extrait dans la version entière (0 à 1)
  level    text not null,
  track    text not null,
  settled  boolean not null default false,
  winners  jsonb,
  primary key (game, week)
);
alter table public.game_weekly enable row level security;
revoke all on public.game_weekly from anon, authenticated;

create or replace function public._week_start() returns date
language sql stable as $$ select date_trunc('week', now() at time zone 'Europe/Paris')::date $$;

-- Crée le chant de la semaine s'il n'existe pas, et récompense les gagnants des semaines terminées
create or replace function public._game_week_ensure(p_game text) returns public.game_weekly
language plpgsql security definer set search_path = public as $$
declare g record; w public.game_weekly; songs jsonb; levels jsonb; s text; l text; best int; r record; win jsonb; nb int; ng int;
begin
  select * into g from public.games where id = p_game;
  if g is null or g.settings->'weekly' is null then return null; end if;
  -- semaines passées pas encore réglées
  for w in select * from public.game_weekly where game = p_game and not settled and week < public._week_start() for update loop
    select max(b.score) into best from public.game_best b join public.players p on p.id = b.player_id
      where b.game = p_game and b.track = w.track and not p.is_test;
    win := '[]'::jsonb;
    if best is not null and g.status = 'on' then
      nb := coalesce((g.settings->'weekly'->>'boosters')::int, 5); ng := coalesce((g.settings->'weekly'->>'god')::int, 1);
      for r in select p.id, p.pseudo, b.accuracy from public.game_best b join public.players p on p.id = b.player_id
                where b.game = p_game and b.track = w.track and not p.is_test and b.score = best loop
        update public.players set gifts = gifts + nb, god_next = god_next + ng,
          gift_reason = g.name || ' : chant de la semaine gagné !' where id = r.id;
        win := win || jsonb_build_object('pseudo', r.pseudo, 'score', best, 'accuracy', r.accuracy);
      end loop;
    end if;
    update public.game_weekly set settled = true, winners = win where game = p_game and week = w.week;
  end loop;
  select * into w from public.game_weekly where game = p_game and week = public._week_start();
  if w.week is null then
    songs := g.settings->'weekly'->'songs'; levels := g.settings->'weekly'->'levels';
    s := songs->>(floor(random() * jsonb_array_length(songs)))::int;
    l := levels->>(floor(random() * jsonb_array_length(levels)))::int;
    insert into public.game_weekly (week, game, song, pos, level, track)
      values (public._week_start(), p_game, s, round(random()::numeric, 4), l, 'semaine/' || public._week_start()::text)
      on conflict do nothing;
    select * into w from public.game_weekly where game = p_game and week = public._week_start();
    -- annonce sur les téléphones
    if g.status = 'on' and to_regclass('public.push_queue') is not null then
      execute 'insert into public.push_queue (player_id, kind, title, body) select id, ''echange'', $1, $2 from public.players where not is_test'
        using '🎵 Nouveau chant de la semaine', g.name || ' : à toi de faire le meilleur score !';
    end if;
  end if;
  return w;
end $$;
revoke all on function public._game_week_ensure(text) from public, anon, authenticated;

-- Tout ce qu'il faut pour l'écran « Chant de la semaine »
create or replace function public.game_weekly(p_token uuid, p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); w public.game_weekly; last public.game_weekly;
begin
  w := public._game_week_ensure(p_game);
  if w.week is null then return null; end if;
  select * into last from public.game_weekly where game = p_game and week < w.week order by week desc limit 1;
  return jsonb_build_object(
    'week', w.week, 'song', w.song, 'pos', w.pos, 'level', w.level, 'track', w.track,
    'ends_at', ((w.week + 7)::timestamp at time zone 'Europe/Paris'),
    'board', coalesce((select jsonb_agg(jsonb_build_object('pseudo', p.pseudo, 'score', b.score, 'accuracy', b.accuracy, 'me', p.id = me) order by b.score desc, b.at)
                       from (select * from public.game_best where game = p_game and track = w.track order by score desc, at limit 50) b
                       join public.players p on p.id = b.player_id where not p.is_test), '[]'::jsonb),
    'last', case when last.week is null then null else jsonb_build_object('week', last.week, 'song', last.song, 'level', last.level, 'winners', coalesce(last.winners, '[]'::jsonb)) end);
end $$;

-- Réglage des semaines passées par le minuteur de la base (si pg_cron est installé), toutes les heures
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'collec-semaine';
    perform cron.schedule('collec-semaine', '7 * * * *', $c$select public._game_week_ensure('rythme')$c$);
  end if;
exception when others then null; end $$;

-- ---------- Envoi d'un score ----------
create or replace function public.game_submit(p_token uuid, p_game text, p_track text, p_score int, p_accuracy numeric, p_details jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); pl record; g record; prev_score int; maxs int; rl jsonb;
        given int := 0; cap int; today int; reasons text[] := '{}'; is_record boolean; n int; rk int;
        ach text[] := '{}'; song text; cid int; w public.game_weekly; minacc numeric;
begin
  select * into pl from public.players where id = me;
  select * into g from public.games where id = p_game;
  if g is null or not public._game_open(p_game, pl.is_test or pl.game_tester) then raise exception 'jeu_ferme'; end if;
  maxs := coalesce((g.settings->>'max_score')::int, 10000000);
  if p_score is null or p_score < 0 or p_score > maxs or coalesce(btrim(p_track), '') = '' or length(p_track) > 80
     or (p_accuracy is not null and (p_accuracy < 0 or p_accuracy > 100)) then raise exception 'score_invalide'; end if;
  -- chant de la semaine : seulement celui de la semaine en cours
  if p_track like 'semaine/%' then
    w := public._game_week_ensure(p_game);
    if w.track is distinct from p_track then raise exception 'semaine_finie'; end if;
  end if;

  if pl.is_test then
    return jsonb_build_object('record', true, 'best', p_score, 'rank', null, 'boosters', 0, 'reasons', '[]'::jsonb, 'test', true);
  end if;

  select score into prev_score from public.game_best where player_id = me and game = p_game and track = p_track;
  is_record := prev_score is null or p_score > prev_score;
  insert into public.game_best (player_id, game, track, score, accuracy, details)
    values (me, p_game, p_track, p_score, p_accuracy, p_details)
  on conflict (player_id, game, track) do update set
    plays = public.game_best.plays + 1,
    score = greatest(public.game_best.score, excluded.score),
    accuracy = case when excluded.score > public.game_best.score then excluded.accuracy else public.game_best.accuracy end,
    details = case when excluded.score > public.game_best.score then excluded.details else public.game_best.details end,
    at = case when excluded.score > public.game_best.score then now() else public.game_best.at end;

  if g.status = 'on' then
    -- récompenses en boosters : une fois par règle et par piste ; plafond par jour seulement s'il est réglé
    cap := (g.settings->>'reward_daily_cap')::int;
    select coalesce(sum(boosters), 0) into today from public.game_rewards
      where player_id = me and game = p_game and (at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date;
    for rl in select * from jsonb_array_elements(coalesce(g.settings->'rewards', '[]'::jsonb)) loop
      n := coalesce((rl->>'boosters')::int, 1);
      continue when cap is not null and today + given + n > cap;
      continue when coalesce(rl->>'track', '*') <> '*' and not (p_track like (rl->>'track'));
      continue when p_score < coalesce((rl->>'min_score')::int, 0);
      continue when (rl ? 'min_accuracy') and coalesce(p_accuracy, 0) < (rl->>'min_accuracy')::numeric;
      continue when exists (select 1 from public.game_rewards where player_id = me and game = p_game and rule = rl->>'id' and track = p_track);
      insert into public.game_rewards (player_id, game, rule, track, boosters) values (me, p_game, rl->>'id', p_track, n);
      given := given + n;
      reasons := reasons || coalesce(rl->>'reason', g.name);
    end loop;
    if given > 0 then
      update public.players set gifts = gifts + given, gift_reason = g.name || ' : ' || reasons[1] where id = me;
    end if;

    -- succès (pistes normales « chant/version/difficulté ») : 90 % et sans-faute, notés une fois par piste
    if p_track like '%/%/%' and p_track not like 'semaine/%' then
      song := split_part(p_track, '/', 1);
      minacc := coalesce((g.settings->>'maitre_min')::numeric, 90);
      if coalesce(p_accuracy, 0) >= minacc then
        insert into public.game_rewards (player_id, game, rule, track, boosters) values (me, p_game, 'p90', p_track, 0) on conflict do nothing;
      end if;
      if coalesce((p_details->>'r')::int, 1) = 0 and coalesce((p_details->>'notes')::int, 0) > 0 then
        insert into public.game_rewards (player_id, game, rule, track, boosters) values (me, p_game, 'fc', p_track, 0) on conflict do nothing;
      end if;
      begin
        -- version Maître de la carte du chant
        cid := (g.settings->'maitre'->>song)::int;
        if cid is not null and not exists (select 1 from public.owned where player_id = me and card_id = cid and variant = 'maitre')
           and (select count(*) from public.game_rewards where player_id = me and game = p_game and rule = 'p90' and track like song || '/%/%')
               >= coalesce((g.settings->>'maitre_tracks')::int, 6) then
          insert into public.owned (player_id, card_id, variant) values (me, cid, 'maitre') on conflict do nothing;
          ach := ach || ('maitre:' || song);
        end if;
        -- carte hors-série du sans-faute complet
        cid := (g.settings->>'fc_card')::int;
        if cid is not null and not exists (select 1 from public.owned where player_id = me and card_id = cid)
           and (select count(*) from public.game_rewards where player_id = me and game = p_game and rule = 'fc' and track not like 'semaine/%')
               >= coalesce((g.settings->>'fc_tracks')::int, 30) then
          insert into public.owned (player_id, card_id, variant) values (me, cid, 'normale') on conflict do nothing;
          ach := ach || 'sans-faute'::text;
        end if;
      exception when others then null;  -- un souci de carte ne doit jamais bloquer l'envoi du score
      end;
    end if;
  end if;

  select count(*) + 1 into rk from public.game_best b join public.players p on p.id = b.player_id
   where b.game = p_game and b.track = p_track and not p.is_test
     and b.score > (select score from public.game_best where player_id = me and game = p_game and track = p_track);
  return jsonb_build_object('record', is_record, 'best', (select score from public.game_best where player_id = me and game = p_game and track = p_track),
                            'previous', prev_score, 'rank', rk, 'boosters', given, 'reasons', to_jsonb(reasons),
                            'achievements', to_jsonb(ach), 'state', public._state(me));
end $$;

-- Avancement des succès d'un joueur (pour l'écran des scores)
create or replace function public.game_achievements(p_token uuid, p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  return jsonb_build_object(
    'p90', coalesce((select jsonb_agg(track) from public.game_rewards where player_id = me and game = p_game and rule = 'p90'), '[]'::jsonb),
    'fc', coalesce((select jsonb_agg(track) from public.game_rewards where player_id = me and game = p_game and rule = 'fc'), '[]'::jsonb));
end $$;

-- Records : sans les pistes du chant de la semaine
create or replace function public.game_records() returns table (game text, game_name text, track text, pseudo text, score int, accuracy numeric)
language sql stable security definer set search_path = public as $$
  select distinct on (b.game, b.track) b.game, g.name, b.track, p.pseudo::text, b.score, b.accuracy
    from public.game_best b join public.players p on p.id = b.player_id join public.games g on g.id = b.game
   where not p.is_test and g.status = 'on' and b.track not like 'semaine/%'
   order by b.game, b.track, b.score desc, b.at;
$$;

-- Classement des collections : sans les cartes hors-série ni la version Maître
create or replace function public.leaderboard() returns table (pseudo text, cartes bigint, variantes bigint)
language sql stable security definer set search_path = public as $$
  select p.pseudo,
         count(distinct o.card_id) filter (where c.published and not c.hors_serie and o.variant <> 'maitre'),
         count(*) filter (where c.published and not c.hors_serie and o.variant not in ('normale', 'maitre'))
  from public.players p
  left join public.owned o on o.player_id = p.id
  left join public.cards c on c.id = o.card_id
  where not p.is_test
  group by p.id
  order by 2 desc, 3 desc, p.pseudo;
$$;

-- Boosters : jamais de carte hors-série
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
    select id into cid from public.cards where published and not hors_serie and rarity = r and id <> all(taken) order by random() limit 1;
    if cid is null then select id into cid from public.cards where published and not hors_serie and rarity = r order by random() limit 1; end if;
    if cid is null then select id into cid from public.cards where published and not hors_serie order by random() limit 1; end if;
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


-- Échanges : ni version Maître, ni carte hors-série
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
  -- la version Maître et les cartes hors-série se méritent : elles ne s'échangent pas
  if 'maitre' in (p_give_variant, p_want_variant)
     or exists (select 1 from public.cards where id in (p_give_card, p_want_card) and hors_serie) then raise exception 'echange_interdit'; end if;
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
grant execute on function public.game_weekly(uuid, text), public.game_submit(uuid, text, text, int, numeric, jsonb),
  public.game_achievements(uuid, text), public.game_records(), public.leaderboard() to anon, authenticated;

select 'Mise à jour n° 25 installée' as resultat;
