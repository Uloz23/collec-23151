-- =====================================================================
--  Collec' 23-151 : mise à jour n° 13
--  Propositions de cartes par les joueurs (nouvelle carte ou amélioration d'une carte existante),
--  avec photo facultative. L'admin les voit dans l'onglet « Propositions ».
--  À coller dans Supabase > SQL Editor > New query, puis « Run ». Relançable sans danger.
-- =====================================================================

create table if not exists public.proposals (
  id          bigserial primary key,
  player_id   uuid not null references public.players(id) on delete cascade,
  kind        text not null default 'nouvelle',          -- nouvelle, amelioration
  card_id     int references public.cards(id) on delete set null,  -- carte à améliorer
  name        text,
  type        text,
  idea        text,
  flavor      text,
  photo       text,                                       -- image réduite (data:image/jpeg;base64,…)
  status      text not null default 'attente',            -- attente, ajoutee
  created_at  timestamptz not null default now(),
  done_at     timestamptz
);
alter table public.proposals enable row level security;
revoke all on public.proposals from anon, authenticated;

-- Un joueur envoie une proposition
create or replace function public.proposal_create(p_token uuid, p_kind text, p_card int, p_name text, p_type text,
  p_idea text, p_flavor text, p_photo text) returns bigint
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token); nid bigint;
begin
  if p_kind not in ('nouvelle', 'amelioration') then raise exception 'proposition_invalide'; end if;
  if p_kind = 'amelioration' and not exists (select 1 from public.cards where id = p_card) then raise exception 'proposition_invalide'; end if;
  if p_kind = 'nouvelle' and coalesce(btrim(p_name), '') = '' then raise exception 'proposition_sans_nom'; end if;
  if coalesce(btrim(p_idea), '') = '' and coalesce(btrim(p_flavor), '') = '' and p_photo is null then raise exception 'proposition_vide'; end if;
  if p_photo is not null and (p_photo not like 'data:image/jpeg;base64,%' or length(p_photo) > 600000) then raise exception 'photo_invalide'; end if;
  insert into public.proposals (player_id, kind, card_id, name, type, idea, flavor, photo)
    values (me, p_kind, case when p_kind = 'amelioration' then p_card end, left(btrim(p_name), 40), left(p_type, 20),
            left(btrim(p_idea), 1500), left(btrim(p_flavor), 200), p_photo)
    returning id into nid;
  return nid;
end $$;

-- Ses propositions (sans les photos, pour rester léger)
create or replace function public.proposal_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'card_id', x.card_id, 'name', x.name,
      'status', x.status, 'photo', x.photo is not null, 'created_at', x.created_at) order by x.created_at desc)
    from public.proposals x where x.player_id = me), '[]'::jsonb);
end $$;

-- Retirer sa proposition tant qu'elle est en attente
create or replace function public.proposal_withdraw(p_token uuid, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public._player(p_token);
begin
  delete from public.proposals where id = p_id and player_id = me and status = 'attente';
end $$;

-- Admin : toutes les propositions, avec l'auteur et la photo
create or replace function public.admin_proposals() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'card_id', x.card_id, 'card_name', c.name,
      'name', x.name, 'type', x.type, 'idea', x.idea, 'flavor', x.flavor, 'photo', x.photo, 'status', x.status,
      'pseudo', p.pseudo, 'created_at', x.created_at) order by (x.status = 'attente') desc, x.created_at desc)
    from public.proposals x join public.players p on p.id = x.player_id left join public.cards c on c.id = x.card_id), '[]'::jsonb);
end $$;

create or replace function public.admin_proposal_done(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  update public.proposals set status = 'ajoutee', done_at = now() where id = p_id;
end $$;

create or replace function public.admin_proposal_delete(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'reserve_admin'; end if;
  delete from public.proposals where id = p_id;
end $$;

grant execute on function public.proposal_create(uuid, text, int, text, text, text, text, text), public.proposal_mine(uuid),
  public.proposal_withdraw(uuid, bigint) to anon, authenticated;
grant execute on function public.admin_proposals(), public.admin_proposal_done(bigint), public.admin_proposal_delete(bigint) to authenticated;
revoke execute on function public.admin_proposals(), public.admin_proposal_done(bigint), public.admin_proposal_delete(bigint) from anon;

select 'Mise à jour n° 13 installée' as resultat;
