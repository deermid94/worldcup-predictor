-- ============================================================
--  World Cup 2026 Predictor — save picks via a server-side RPC
--  Run ONCE in Supabase: dashboard → SQL Editor → paste → Run.
--  Safe to re-run (idempotent).
--
--  WHY THIS EXISTS: the webpage saved picks with an upsert
--  (insert-or-update so people can change a pick). Under RLS,
--  an ON CONFLICT DO UPDATE has to look up the existing row, but
--  the "no peeking before kickoff" SELECT policy hides it — so
--  Postgres rejected EVERY save with 42501. This SECURITY DEFINER
--  function does the upsert server-side (bypassing RLS), while
--  re-enforcing the same rules the policies did:
--    • player must be one of the five entrants
--    • match must be a knockout game (not 'Group%')
--    • kickoff must be > 2 hours away (the lock)
--  Returns the number of picks saved, or -1 for an unknown player.
-- ============================================================

create or replace function save_picks(p_name text, p_picks jsonb)
  returns int
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
declare
  rec jsonb;
  n   int := 0;
begin
  if p_name not in ('Champion','Cactus','Chang','Lizard','Pop Smoke') then
    return -1;                                   -- unknown / not an entrant
  end if;

  for rec in select value from jsonb_array_elements(p_picks)
  loop
    insert into predictions(player, match_id, pick, advance)
    select p_name,
           (rec->>'match_id')::bigint,
           rec->>'pick',
           nullif(rec->>'advance','')
    where exists (
      select 1 from matches m
      where m.id = (rec->>'match_id')::bigint
        and m.kickoff > now() + interval '2 hours'   -- the 2-hour lock
        and m.stage  not ilike 'Group%'              -- knockout only
    )
    on conflict (player, match_id) do update
      set pick = excluded.pick, advance = excluded.advance;

    if found then n := n + 1; end if;            -- count only rows that passed
  end loop;

  return n;
end;
$$;

grant execute on function save_picks(text, jsonb) to anon;
