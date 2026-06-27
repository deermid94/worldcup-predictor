// ============================================================
//  Supabase Edge Function — sync World Cup fixtures + scores.
//  Same job as scripts/sync.mjs, but runs on Supabase's own
//  infrastructure and is triggered by Supabase Cron (reliable,
//  server-side clock) instead of GitHub Actions.
//
//  Env vars:
//    FOOTBALL_DATA_KEY          — set this as a secret (Dashboard → Edge Functions → Secrets)
//    SUPABASE_URL               — built in automatically, no need to set
//    SUPABASE_SERVICE_ROLE_KEY  — built in automatically, no need to set
// ============================================================

const FD_KEY = Deno.env.get("FOOTBALL_DATA_KEY");
const SB_URL = Deno.env.get("SUPABASE_URL");
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const COMP = Deno.env.get("COMPETITION") ?? "WC"; // WC = FIFA World Cup

// Turn the API's stage/group into a friendly label.
function label(m: any): string {
  if (m.group) return "Group " + String(m.group).replace(/^GROUP_/, "");
  const map: Record<string, string> = {
    LAST_16: "Round of 16",
    QUARTER_FINALS: "Quarter-final",
    SEMI_FINALS: "Semi-final",
    THIRD_PLACE: "Third place",
    FINAL: "Final",
    GROUP_STAGE: "Group stage",
  };
  return map[m.stage] || String(m.stage || "").replace(/_/g, " ");
}

Deno.serve(async () => {
  if (!FD_KEY || !SB_URL || !SB_KEY) {
    return new Response("Missing env vars (FOOTBALL_DATA_KEY / SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)", { status: 500 });
  }

  // 1. Fetch all World Cup matches from the data provider.
  const res = await fetch(`https://api.football-data.org/v4/competitions/${COMP}/matches`, {
    headers: { "X-Auth-Token": FD_KEY },
  });
  if (!res.ok) {
    const body = await res.text();
    return new Response(`football-data.org error ${res.status}: ${body}`, { status: 502 });
  }
  const { matches = [] } = await res.json();

  // 2. Map to our table shape. Only record a score once FINISHED,
  //    so the leaderboard never counts a half-time scoreline.
  const rows = matches
    .filter((m: any) => m.homeTeam?.name && m.awayTeam?.name && m.utcDate)
    .map((m: any) => ({
      ext_id: m.id,
      stage: label(m),
      home_team: m.homeTeam.name,
      away_team: m.awayTeam.name,
      kickoff: m.utcDate,
      home_score: m.status === "FINISHED" ? (m.score?.fullTime?.home ?? null) : null,
      away_score: m.status === "FINISHED" ? (m.score?.fullTime?.away ?? null) : null,
      // Knockout scoring: who progressed + how it was decided. ET/PENS ⇒
      // the 90-minute result was a draw, inferred from `duration` downstream.
      winner: m.status === "FINISHED"
        ? (({ HOME_TEAM: "H", AWAY_TEAM: "A" } as Record<string, string>)[m.score?.winner] ?? null) : null,
      duration: m.status === "FINISHED" ? (m.score?.duration ?? null) : null,
    }));

  if (!rows.length) return new Response("No usable matches yet — nothing to write.", { status: 200 });

  // 3. Upsert into Supabase (service key bypasses row-level security).
  const up = await fetch(`${SB_URL}/rest/v1/matches?on_conflict=ext_id`, {
    method: "POST",
    headers: {
      apikey: SB_KEY,
      Authorization: `Bearer ${SB_KEY}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(rows),
  });
  if (!up.ok) {
    const body = await up.text();
    return new Response(`Supabase upsert error ${up.status}: ${body}`, { status: 502 });
  }

  const finished = rows.filter((r: any) => r.home_score != null).length;

  // 4. Top scorers (Golden Boot). Secondary data — a failure here must
  //    not abort the run, since fixtures/scores are what really matter.
  let scorerMsg = "";
  try {
    scorerMsg = " " + await syncScorers();
  } catch (e) {
    console.error("Scorers sync skipped:", e);
  }

  const msg = `Synced ${rows.length} fixtures (${finished} with final scores).${scorerMsg}`;
  console.log(msg);
  return new Response(msg, { status: 200 });
});

// Pull the tournament's leading scorers and mirror them into our table.
async function syncScorers(): Promise<string> {
  const res = await fetch(`https://api.football-data.org/v4/competitions/${COMP}/scorers?limit=30`, {
    headers: { "X-Auth-Token": FD_KEY! },
  });
  if (!res.ok) {
    console.error("scorers fetch", res.status, await res.text());
    return "Scorers fetch failed.";
  }
  const { scorers = [] } = await res.json();

  const rows = scorers
    .filter((s: any) => s.player?.id && s.player?.name)
    .map((s: any) => ({
      ext_id: s.player.id,
      player: s.player.name,
      team: s.team?.name ?? null,
      goals: s.goals ?? 0,
      assists: s.assists ?? null,
      penalties: s.penalties ?? null,
      played_matches: s.playedMatches ?? null,
    }));
  if (!rows.length) return "No scorers yet.";

  const up = await fetch(`${SB_URL}/rest/v1/scorers?on_conflict=ext_id`, {
    method: "POST",
    headers: {
      apikey: SB_KEY!,
      Authorization: `Bearer ${SB_KEY}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(rows),
  });
  if (!up.ok) {
    console.error("Supabase scorers upsert", up.status, await up.text());
    return "Scorers upsert failed.";
  }
  return `Synced ${rows.length} top scorers.`;
}
