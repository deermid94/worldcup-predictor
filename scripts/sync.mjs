// ============================================================
//  Sync robot — pulls World Cup fixtures + scores from
//  football-data.org and writes them into Supabase.
//  Runs on a schedule via GitHub Actions (see .github/workflows).
//  No npm install needed — uses built-in fetch (Node 18+).
// ============================================================

const FD_KEY   = process.env.FOOTBALL_DATA_KEY;
const SB_URL   = process.env.SUPABASE_URL;          // https://xxxx.supabase.co
const SB_KEY   = process.env.SUPABASE_SERVICE_KEY;  // service_role key (secret!)
const COMP     = process.env.COMPETITION || 'WC';   // WC = FIFA World Cup

if (!FD_KEY || !SB_URL || !SB_KEY) {
  console.error('Missing env vars: FOOTBALL_DATA_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY');
  process.exit(1);
}

// Turn the API's stage/group into a friendly label.
function label(m) {
  if (m.group) return 'Group ' + m.group.replace(/^GROUP_/, '');
  const map = {
    LAST_16: 'Round of 16', QUARTER_FINALS: 'Quarter-final',
    SEMI_FINALS: 'Semi-final', THIRD_PLACE: 'Third place', FINAL: 'Final',
    GROUP_STAGE: 'Group stage',
  };
  return map[m.stage] || (m.stage || '').replace(/_/g, ' ');
}

async function main() {
  // 1. Fetch all World Cup matches from the data provider.
  const res = await fetch(`https://api.football-data.org/v4/competitions/${COMP}/matches`, {
    headers: { 'X-Auth-Token': FD_KEY },
  });
  if (!res.ok) {
    console.error('football-data.org error', res.status, await res.text());
    process.exit(1);
  }
  const { matches = [] } = await res.json();
  console.log(`Fetched ${matches.length} matches from football-data.org`);

  // 2. Map them to our table shape. Only record a score once FINISHED,
  //    so the leaderboard never counts a half-time scoreline.
  const rows = matches
    .filter(m => m.homeTeam?.name && m.awayTeam?.name && m.utcDate)
    .map(m => ({
      ext_id:     m.id,
      stage:      label(m),
      home_team:  m.homeTeam.name,
      away_team:  m.awayTeam.name,
      kickoff:    m.utcDate,
      home_score: m.status === 'FINISHED' ? (m.score?.fullTime?.home ?? null) : null,
      away_score: m.status === 'FINISHED' ? (m.score?.fullTime?.away ?? null) : null,
    }));

  if (!rows.length) { console.log('No usable matches yet — nothing to write.'); return; }

  // 3. Upsert into Supabase (service key bypasses row-level security).
  //    on_conflict=ext_id keeps each fixture's row (and its id) stable,
  //    so existing predictions stay linked.
  const up = await fetch(`${SB_URL}/rest/v1/matches?on_conflict=ext_id`, {
    method: 'POST',
    headers: {
      apikey: SB_KEY,
      Authorization: `Bearer ${SB_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(rows),
  });
  if (!up.ok) {
    console.error('Supabase upsert error', up.status, await up.text());
    process.exit(1);
  }
  const finished = rows.filter(r => r.home_score != null).length;
  console.log(`Synced ${rows.length} fixtures (${finished} with final scores).`);
}

main().catch(e => { console.error(e); process.exit(1); });
