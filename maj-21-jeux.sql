-- =====================================================================
--  Collec' 23-151 : mise à jour n° 21
--  Socle des jeux : onglet « Jeux », records et classements par jeu et par piste,
--  progression de chaque joueur, récompenses en boosters, réglages dans l'admin.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

-- ---------- Les jeux ----------
-- status : off (invisible), soon (affiché « À venir »), test (jouable par les comptes test seulement), on (ouvert à tous)
create table if not exists public.games (
  id          text primary key,              -- nom du dossier du jeu : jeux/<id>/
  name        text not null,
  description text not null default '',
  image       text,                          -- image de la vignette (chemin du stockage ou adresse)
  status      text not null default 'soon',
  sort        int not null default 0,
  settings    jsonb not null default '{}'::jsonb,   -- max_score, rewards, reward_daily_cap… (voir l'admin)
  updated_at  timestamptz not null default now()
);
alter table public.games enable row level security;
revoke all on public.games from anon, authenticated;

insert into public.games (id, name, description, status, sort, settings) values
  ('rythme', 'Monôme Hero', 'Suis le rythme des chants de chaque tabagn''s.', 'soon', 1, '{}'),
  ('duel',   'Le duel',   'Affronte la fam''s avec tes cartes.',            'soon', 2, '{}'),
  ('demo',   'Démo',      'Jeu d''essai du socle : touche les étoiles le plus vite possible.', 'test', 99,
             '{"max_score": 100000, "reward_daily_cap": 1, "rewards": [{"id": "demo50", "track": "*", "min_score": 50, "boosters": 1, "reason": "Démo réussie"}]}')
on conflict (id) do nothing;

-- ---------- Meilleurs scores (un par joueur, jeu et piste) ----------
create table if not exists public.game_best (
  player_id   uuid not null references public.players(id) on delete cascade,
  game        text not null references public.games(id) on delete cascade,
  track       text not null,                 -- ex. « bordels/remix/entier/difficile »
  score       int not null,
  accuracy    numeric,                       -- précision en %, facultative
  details     jsonb,
  plays       int not null default 1,
  at          timestamptz not null default now(),
  primary key (player_id, game, track)
);
alter table public.game_best enable row level security;
revoke all on public.game_best from anon, authenticated;

-- ---------- Progression (débloquages, réglages du joueur…), libre pour chaque jeu ----------
create table if not exists public.game_progress (
  player_id   uuid not null references public.players(id) on delete cascade,
  game        text not null references public.games(id) on delete cascade,
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  primary key (player_id, game)
);
alter table public.game_progress enable row level security;
revoke all on public.game_progress from anon, authenticated;

-- ---------- Récompenses déjà données ----------
create table if not exists public.game_rewards (
  player_id   uuid not null references public.players(id) on delete cascade,
  game        text not null references public.games(id) on delete cascade,
  rule        text not null,
  track       text not null,
  boosters    int not null,
  at          timestamptz not null default now(),
  primary key (player_id, game, rule, track)
);
alter table public.game_rewards enable row level security;
revoke all on public.game_rewards from anon, authenticated;

-- Un joueur peut-il jouer à ce jeu ?
create or replace function public._game_open(p_game text, p_test boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.games where id = p_game and (status = 'on' or (status = 'test' and p_test)));
$$;
revoke all on function public._game_open(text, boolean) from public, anon, authenticated;

-- ---------- Côté joueur ----------
-- Liste des jeux à afficher (les jeux « test » seulement pour les comptes test)
create or replace function public.games_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); t boolean;
begin
  select is_test into t from public.players where id = me;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'description', description, 'image', image,
                    'status', status, 'settings', settings - 'rewards') order by sort, name)
                   from public.games where status in ('soon', 'on') or (status = 'test' and t)), '[]'::jsonb);
end $$;

-- Envoi d'un score : garde le meilleur, compte les parties, donne les récompenses méritées
create or replace function public.game_submit(p_token uuid, p_game text, p_track text, p_score int, p_accuracy numeric, p_details jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); pl record; g record; prev_score int; maxs int; rl jsonb;
        given int := 0; cap int; today int; reasons text[] := '{}'; is_record boolean; n int; rk int;
begin
  select * into pl from public.players where id = me;
  select * into g from public.games where id = p_game;
  if g is null or not public._game_open(p_game, pl.is_test) then raise exception 'jeu_ferme'; end if;
  maxs := coalesce((g.settings->>'max_score')::int, 10000000);
  if p_score is null or p_score < 0 or p_score > maxs or coalesce(btrim(p_track), '') = '' or length(p_track) > 80
     or (p_accuracy is not null and (p_accuracy < 0 or p_accuracy > 100)) then raise exception 'score_invalide'; end if;

  -- compte test : rien n'est enregistré (comme pour les boosters)
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

  -- récompenses : une fois par règle et par piste, avec un plafond de boosters par jour
  cap := coalesce((g.settings->>'reward_daily_cap')::int, 3);
  select coalesce(sum(boosters), 0) into today from public.game_rewards
    where player_id = me and game = p_game and (at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date;
  for rl in select * from jsonb_array_elements(coalesce(g.settings->'rewards', '[]'::jsonb)) loop
    n := coalesce((rl->>'boosters')::int, 1);
    continue when today + given + n > cap;
    continue when coalesce(rl->>'track', '*') <> '*' and not (p_track like (rl->>'track')); -- « * » ou motif SQL, ex. « %/difficile »
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

  select count(*) + 1 into rk from public.game_best b join public.players p on p.id = b.player_id
   where b.game = p_game and b.track = p_track and not p.is_test
     and b.score > (select score from public.game_best where player_id = me and game = p_game and track = p_track);
  return jsonb_build_object('record', is_record, 'best', (select score from public.game_best where player_id = me and game = p_game and track = p_track),
                            'previous', prev_score, 'rank', rk, 'boosters', given, 'reasons', to_jsonb(reasons), 'state', public._state(me));
end $$;

-- Mes meilleurs scores pour un jeu
create or replace function public.game_my_bests(p_token uuid, p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  return coalesce((select jsonb_object_agg(track, jsonb_build_object('score', score, 'accuracy', accuracy, 'plays', plays, 'at', at))
                   from public.game_best where player_id = me and game = p_game), '{}'::jsonb);
end $$;

-- Classement d'une piste
create or replace function public.game_board(p_game text, p_track text, p_limit int default 20)
returns table (pseudo text, score int, accuracy numeric, at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.pseudo::text, b.score, b.accuracy, b.at from public.game_best b join public.players p on p.id = b.player_id
   where b.game = p_game and b.track = p_track and not p.is_test
   order by b.score desc, b.at limit least(greatest(coalesce(p_limit, 20), 1), 100);
$$;

-- Le meilleur de chaque piste de chaque jeu ouvert (pour « Records » dans La fam's)
create or replace function public.game_records() returns table (game text, game_name text, track text, pseudo text, score int, accuracy numeric)
language sql stable security definer set search_path = public as $$
  select distinct on (b.game, b.track) b.game, g.name, b.track, p.pseudo::text, b.score, b.accuracy
    from public.game_best b join public.players p on p.id = b.player_id join public.games g on g.id = b.game
   where not p.is_test and g.status = 'on'
   order by b.game, b.track, b.score desc, b.at;
$$;

-- Progression du joueur
create or replace function public.game_progress_get(p_token uuid, p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  return coalesce((select data from public.game_progress where player_id = me and game = p_game), '{}'::jsonb);
end $$;

create or replace function public.game_progress_set(p_token uuid, p_game text, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); t boolean;
begin
  select is_test into t from public.players where id = me;
  if t then return; end if;  -- compte test : rien n'est enregistré
  if not public._game_open(p_game, false) then raise exception 'jeu_ferme'; end if;
  if p_data is null or length(p_data::text) > 20000 then raise exception 'progression_invalide'; end if;
  insert into public.game_progress (player_id, game, data) values (me, p_game, p_data)
  on conflict (player_id, game) do update set data = excluded.data, updated_at = now();
end $$;

-- ---------- Côté admin ----------
create or replace function public.admin_games() returns setof public.games
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return query select * from public.games order by sort, name;
end $$;

create or replace function public.admin_game_save(p_id text, p_name text, p_description text, p_image text, p_status text, p_sort int, p_settings jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  if p_status not in ('off', 'soon', 'test', 'on') or p_id !~ '^[a-z0-9-]{2,30}$' then raise exception 'jeu_invalide'; end if;
  insert into public.games (id, name, description, image, status, sort, settings)
    values (p_id, p_name, coalesce(p_description, ''), nullif(btrim(p_image), ''), p_status, coalesce(p_sort, 0), coalesce(p_settings, '{}'::jsonb))
  on conflict (id) do update set name = excluded.name, description = excluded.description, image = excluded.image,
    status = excluded.status, sort = excluded.sort, settings = excluded.settings, updated_at = now();
end $$;

create or replace function public.admin_game_scores(p_game text)
returns table (player_id uuid, pseudo text, track text, score int, accuracy numeric, plays int, at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return query select b.player_id, p.pseudo::text, b.track, b.score, b.accuracy, b.plays, b.at
    from public.game_best b join public.players p on p.id = b.player_id where b.game = p_game order by b.track, b.score desc;
end $$;

create or replace function public.admin_game_score_delete(p_player uuid, p_game text, p_track text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  delete from public.game_best where player_id = p_player and game = p_game and track = p_track;
end $$;

grant execute on function public.games_list(uuid), public.game_submit(uuid, text, text, int, numeric, jsonb),
  public.game_my_bests(uuid, text), public.game_board(text, text, int), public.game_records(),
  public.game_progress_get(uuid, text), public.game_progress_set(uuid, text, jsonb) to anon, authenticated;
revoke execute on function public.admin_games(), public.admin_game_save(text, text, text, text, text, int, jsonb),
  public.admin_game_scores(text), public.admin_game_score_delete(uuid, text, text) from public, anon;
grant execute on function public.admin_games(), public.admin_game_save(text, text, text, text, text, int, jsonb),
  public.admin_game_scores(text), public.admin_game_score_delete(uuid, text, text) to authenticated;

select 'Mise à jour n° 21 installée' as resultat;
