-- ============================================================
--  World Cup 2026 Predictor — v2: player PINs + locked groups
--  Run this ONCE in Supabase: dashboard → SQL Editor → paste → Run.
--  Safe to re-run (everything is idempotent).
-- ============================================================

-- pgcrypto gives us crypt()/gen_salt() for hashing PINs.
create extension if not exists pgcrypto with schema extensions;

-- ---- Players ------------------------------------------------
-- The five fixed entrants. Everyone starts on the shared temporary
-- PIN '0000'; the app prompts each person to set their own on first
-- login (and a Change PIN button lets them update it any time). PINs
-- are stored hashed and are never readable by the public (anon) key.
create table if not exists players (
  name      text primary key,
  pin_hash  text
);

alter table players enable row level security;
-- NB: no policies for anon => the table itself is not directly
-- readable or writable from the website. All access goes through
-- the two SECURITY DEFINER functions below.

-- The five entrants, each seeded with the temporary PIN '0000'.
-- on conflict do nothing => re-running this script never resets a
-- PIN someone has already changed.
insert into players(name, pin_hash) values
  ('Champion',  extensions.crypt('0000', extensions.gen_salt('bf'))),
  ('Lizard',    extensions.crypt('0000', extensions.gen_salt('bf'))),
  ('Chang',     extensions.crypt('0000', extensions.gen_salt('bf'))),
  ('Cactus',    extensions.crypt('0000', extensions.gen_salt('bf'))),
  ('Pop Smoke', extensions.crypt('0000', extensions.gen_salt('bf')))
on conflict (name) do nothing;

-- Names only (no pins) — used to fill the login dropdown.
create or replace function list_players()
  returns setof text
  language sql
  security definer
  set search_path = public
as $$
  select name from players order by name;
$$;
grant execute on function list_players() to anon;

-- Trust-on-first-use login check:
--   • unknown name           → false
--   • first time (no pin yet) → set this pin, return true
--   • pin already set         → true only if it matches
create or replace function claim_or_verify(p_name text, p_pin text)
  returns boolean
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
declare h text;
begin
  select pin_hash into h from players where name = p_name;
  if not found then
    return false;
  end if;
  if h is null then
    update players set pin_hash = crypt(p_pin, gen_salt('bf')) where name = p_name;
    return true;
  end if;
  return h = crypt(p_pin, h);
end;
$$;
grant execute on function claim_or_verify(text, text) to anon;

-- Change a PIN: requires the current PIN to match. Used both for the
-- "set your own PIN" prompt after a '0000' login and the Change PIN button.
create or replace function change_pin(p_name text, p_old text, p_new text)
  returns boolean
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
declare h text;
begin
  if length(coalesce(p_new, '')) < 4 then
    return false;                       -- new PIN too short
  end if;
  select pin_hash into h from players where name = p_name;
  if not found then
    return false;
  end if;
  if h is not null and h <> crypt(p_old, h) then
    return false;                       -- current PIN wrong
  end if;
  update players set pin_hash = crypt(p_new, gen_salt('bf')) where name = p_name;
  return true;
end;
$$;
grant execute on function change_pin(text, text, text) to anon;

-- ---- Lock the group stage -----------------------------------
-- Group-stage picks are loaded once (by you, via the SQL editor)
-- and can NEVER be changed from the website. These policies stop
-- the public key inserting or updating any pick for a 'Group %'
-- match. Knockout picks remain editable until their kickoff.

drop policy if exists "predictions insertable before kickoff" on predictions;
create policy "predictions insertable before kickoff" on predictions
  for insert with check (
    exists (
      select 1 from matches m
      where m.id = match_id
        and m.kickoff > now()
        and m.stage not ilike 'Group%'
    )
  );

drop policy if exists "predictions updatable before kickoff" on predictions;
create policy "predictions updatable before kickoff" on predictions
  for update using (
    exists (
      select 1 from matches m
      where m.id = match_id
        and m.kickoff > now()
        and m.stage not ilike 'Group%'
    )
  ) with check (
    exists (
      select 1 from matches m
      where m.id = match_id
        and m.kickoff > now()
        and m.stage not ilike 'Group%'
    )
  );

-- The group-stage picks themselves get loaded by a separate
-- generated script (load-group-picks.sql) which runs here in the
-- SQL editor too — the postgres role bypasses the rules above.
