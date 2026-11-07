-- =====================================================================
--  Collec' 23-151 : mise à jour n° 10
--  Bilan pour l'admin (onglet « Bilan », réservé à l'admin) :
--  échanges (cartes les plus échangées, plus gros échangeurs) et boosters ouverts.
--  Les comptes test sont exclus des chiffres.
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
--  (Nécessite la mise à jour n° 8.)
-- =====================================================================

create or replace function public.admin_stats() returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  perform public._trades_expire();

  with
  -- Tirages : une ligne par carte tirée. Lu en jsonb pour s'adapter à la forme de la table.
  raw as (select to_jsonb(x) j from public.pulls x),
  pl as (
    select (j->>'player_id')::uuid pid, (e->>'card_id')::int cid, coalesce(e->>'variant', 'normale') v,
           coalesce(j->>'created_at', j->>'opened_at', j->>'at', j->>'ts') t, j->>'booster_id' b
    from raw, lateral (select coalesce(j->'cards', jsonb_build_array(j)) arr) a,
         lateral jsonb_array_elements(case when jsonb_typeof(a.arr) = 'array' then a.arr else jsonb_build_array(j) end) e
  ),
  pulls as (
    select pl.*, c.name, c.rarity, p.pseudo from pl
    join public.players p on p.id = pl.pid and not p.is_test
    left join public.cards c on c.id = pl.cid
  ),
  -- Un booster = les cartes tirées au même instant par le même joueur
  boosters as (select pid, pseudo, coalesce(b, t) k, count(*) n from pulls group by pid, pseudo, coalesce(b, t)),
  tr as (
    select t.*, a.pseudo fp, b.pseudo tp from public.trades t
    join public.players a on a.id = t.from_id and not a.is_test
    join public.players b on b.id = t.to_id and not b.is_test
  ),
  ok as (select * from tr where status = 'acceptee'),
  moved as (  -- chaque échange accepté fait bouger deux cartes
    select give_card cid, give_variant v from ok union all select want_card, want_variant from ok
  ),
  traders as (
    select pseudo, count(*) filter (where acc) acceptes, count(*) filter (where sent) proposes, count(*) filter (where not sent) recus
    from (select fp pseudo, true sent, status = 'acceptee' acc from tr
          union all select tp, false, status = 'acceptee' from tr) z
    group by pseudo
  )
  select jsonb_build_object(
    'trades', jsonb_build_object(
      'total', (select count(*) from tr where status <> 'modifiee'),
      'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from tr group by status) s), '{}'),
      'top_cards', coalesce((select jsonb_agg(jsonb_build_object('id', m.cid, 'name', c.name, 'rarity', c.rarity, 'n', m.n) order by m.n desc, c.name)
                    from (select cid, count(*) n from moved group by cid order by 2 desc limit 10) m left join public.cards c on c.id = m.cid), '[]'),
      'top_traders', coalesce((select jsonb_agg(jsonb_build_object('pseudo', pseudo, 'acceptes', acceptes, 'proposes', proposes, 'recus', recus)
                    order by acceptes desc, proposes desc, pseudo) from (select * from traders order by acceptes desc, proposes desc limit 15) x), '[]'),
      'last', coalesce((select jsonb_agg(jsonb_build_object('at', decided_at, 'from', fp, 'to', tp,
                      'give', (select name from public.cards where id = give_card), 'give_v', give_variant,
                      'want', (select name from public.cards where id = want_card), 'want_v', want_variant) order by decided_at desc)
                    from (select * from ok order by decided_at desc limit 10) y), '[]')
    ),
    'boosters', jsonb_build_object(
      'total', (select count(*) from boosters),
      'cards', (select count(*) from pulls),
      'players', (select count(distinct pid) from pulls),
      'by_rarity', coalesce((select jsonb_object_agg(coalesce(rarity, '?'), n) from (select rarity, count(*) n from pulls group by rarity) r), '{}'),
      'by_variant', coalesce((select jsonb_object_agg(v, n) from (select v, count(*) n from pulls group by v) r), '{}'),
      'top_openers', coalesce((select jsonb_agg(jsonb_build_object('pseudo', pseudo, 'n', n) order by n desc, pseudo)
                    from (select pseudo, count(*) n from boosters group by pseudo order by 2 desc limit 15) x), '[]'),
      'top_cards', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'rarity', rarity, 'n', n) order by n desc, name)
                    from (select name, rarity, count(*) n from pulls group by cid, name, rarity order by 3 desc limit 10) x), '[]'),
      'never', (select count(*) from public.cards c where c.published and not exists (select 1 from pulls where cid = c.id)),
      'best', coalesce((select jsonb_agg(jsonb_build_object('pseudo', pseudo, 'name', name, 'rarity', rarity, 'v', v, 'at', t) order by t desc)
                    from (select * from pulls where rarity = 'mythique' or v in ('doree', 'textless') order by t desc limit 15) x), '[]')
    )
  ) into res;
  return res;
end $$;

revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

select 'Mise à jour n° 10 installée' as resultat;
