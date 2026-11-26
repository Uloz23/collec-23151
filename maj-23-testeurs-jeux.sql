-- =====================================================================
--  Collec' 23-151 : mise à jour n° 23
--  Testeurs de jeux : un joueur normal (vraies cartes, vrais boosters) qui peut aussi jouer
--  aux jeux en état « test ». Ses scores et sa progression sont enregistrés normalement,
--  mais aucun booster n'est gagné tant que le jeu est en test (pour personne).
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite les mises à jour n° 3 et 21.)
-- =====================================================================

alter table public.players add column if not exists game_tester boolean not null default false;

create or replace function public.games_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); t boolean;
begin
  select is_test or game_tester into t from public.players where id = me;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'description', description, 'image', image,
                    'status', status, 'settings', settings - 'rewards') order by sort, name)
                   from public.games where status in ('soon', 'on') or (status = 'test' and t)), '[]'::jsonb);
end $$;


create or replace function public.game_submit(p_token uuid, p_game text, p_track text, p_score int, p_accuracy numeric, p_details jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); pl record; g record; prev_score int; maxs int; rl jsonb;
        given int := 0; cap int; today int; reasons text[] := '{}'; is_record boolean; n int; rk int;
begin
  select * into pl from public.players where id = me;
  select * into g from public.games where id = p_game;
  if g is null or not public._game_open(p_game, pl.is_test or pl.game_tester) then raise exception 'jeu_ferme'; end if;
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
  -- pas de récompense tant que le jeu est en test
  for rl in select * from jsonb_array_elements(case when g.status = 'on' then coalesce(g.settings->'rewards', '[]'::jsonb) else '[]'::jsonb end) loop
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


create or replace function public.game_progress_set(p_token uuid, p_game text, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); t boolean; gt boolean;
begin
  select is_test, game_tester into t, gt from public.players where id = me;
  if t then return; end if;  -- compte test : rien n'est enregistré
  if not public._game_open(p_game, gt) then raise exception 'jeu_ferme'; end if;
  if p_data is null or length(p_data::text) > 20000 then raise exception 'progression_invalide'; end if;
  insert into public.game_progress (player_id, game, data) values (me, p_game, p_data)
  on conflict (player_id, game) do update set data = excluded.data, updated_at = now();
end $$;


create or replace function public.admin_set_game_tester(p_id uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  update public.players set game_tester = p_on where id = p_id;
end $$;

drop function if exists public.admin_players();
create function public.admin_players() returns table (id uuid, pseudo text, stock int, gifts int, cartes bigint, created_at timestamptz, last_seen timestamptz, can_gift boolean, is_test boolean, game_tester boolean)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return query select p.id, p.pseudo, p.stock, p.gifts, (select count(distinct card_id) from public.owned o where o.player_id = p.id), p.created_at, p.last_seen, p.can_gift, p.is_test, p.game_tester
    from public.players p order by p.pseudo;
end $$;

grant execute on function public.games_list(uuid), public.game_submit(uuid, text, text, int, numeric, jsonb), public.game_progress_set(uuid, text, jsonb) to anon, authenticated;
revoke execute on function public.admin_set_game_tester(uuid, boolean), public.admin_players() from public, anon;
grant execute on function public.admin_set_game_tester(uuid, boolean), public.admin_players() to authenticated;

select 'Mise à jour n° 23 installée' as resultat;
