-- ============================================================
--  World Cup 2026 Predictor — Golden Boot (top scorers) table
--  Run this ONCE in Supabase: dashboard → SQL Editor → paste → Run.
--  Safe to re-run (idempotent).
-- ============================================================

-- The tournament's top scorers. Filled in AUTOMATICALLY by the sync
-- robot from football-data.org's /scorers endpoint — you don't add
-- rows by hand. ext_id is the data provider's own player id, used to
-- keep each scorer's row stable across updates.
create table if not exists scorers (
  ext_id          bigint primary key,    -- football-data.org player id
  player          text not null,
  team            text,                  -- the player's national team
  goals           int  not null default 0,
  assists         int,                   -- may be null on the free tier
  penalties       int,                   -- may be null on the free tier
  played_matches  int,
  updated_at      timestamptz not null default now()
);

alter table scorers enable row level security;

-- Anyone can read the scorers list (it's public tournament data).
drop policy if exists "scorers readable" on scorers;
create policy "scorers readable" on scorers
  for select using (true);

-- Note: the sync robot writes scorers using the SERVICE key, which
-- bypasses row-level security. With no insert/update policy for anon,
-- the public (website) key can read but never write this table.
