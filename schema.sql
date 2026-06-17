-- ============================================================
--  World Cup 2026 Predictor — database setup
--  Run this ONCE in your Supabase project:
--    Supabase dashboard → SQL Editor → New query → paste → Run
-- ============================================================

-- ---- Tables -------------------------------------------------

-- The fixtures. These are filled in AUTOMATICALLY by the sync
-- robot (GitHub Action) from football-data.org — you don't add
-- them by hand. ext_id is the data provider's own match id, used
-- to keep each fixture's row stable across updates.
create table if not exists matches (
  id          bigint generated always as identity primary key,
  ext_id      bigint unique,              -- football-data.org match id
  stage       text,                       -- e.g. 'Group A', 'Round of 16'
  home_team   text not null,
  away_team   text not null,
  kickoff     timestamptz not null,       -- when picks lock & become visible
  home_score  int,                        -- filled automatically when the game ends
  away_score  int
);

-- One row per (player, match). A player is just a nickname.
create table if not exists predictions (
  id          uuid primary key default gen_random_uuid(),
  player      text not null,
  match_id    bigint not null references matches(id) on delete cascade,
  pick        text not null check (pick in ('H','D','A')),  -- Home / Draw / Away
  created_at  timestamptz not null default now(),
  unique (player, match_id)
);

-- ---- Security (this is what hides picks until kickoff) ------

alter table matches      enable row level security;
alter table predictions  enable row level security;

-- Anyone can read the fixtures.
drop policy if exists "matches readable" on matches;
create policy "matches readable" on matches
  for select using (true);

-- A prediction row can only be READ once its match has kicked off.
-- Before kickoff, this returns NOTHING for everyone — so no peeking.
drop policy if exists "predictions visible after kickoff" on predictions;
create policy "predictions visible after kickoff" on predictions
  for select using (
    exists (select 1 from matches m where m.id = match_id and m.kickoff <= now())
  );

-- You may SUBMIT a pick only before kickoff.
drop policy if exists "predictions insertable before kickoff" on predictions;
create policy "predictions insertable before kickoff" on predictions
  for insert with check (
    exists (select 1 from matches m where m.id = match_id and m.kickoff > now())
  );

-- You may CHANGE a pick only before kickoff.
drop policy if exists "predictions updatable before kickoff" on predictions;
create policy "predictions updatable before kickoff" on predictions
  for update using (
    exists (select 1 from matches m where m.id = match_id and m.kickoff > now())
  ) with check (
    exists (select 1 from matches m where m.id = match_id and m.kickoff > now())
  );

-- Note: the sync robot writes fixtures/scores using the SERVICE key,
-- which bypasses these rules. The rules only constrain the public
-- (anon) key used by the webpage your friends load.
