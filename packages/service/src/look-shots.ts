import type { LookStyle } from '@form/contracts';

import type { Database, DatabaseClient } from './database.js';

// Camera setups per photo style. The planner picks one that fits the planned
// activity and avoids recently used ones, so the feed varies without the user
// choosing a camera angle. The id lands in the look's concept, and the app
// shows it in the look menu.
export const lookShots = {
  candid: {
    'candid-mid-laugh': 'Caught mid-laugh or mid-sentence, turned toward someone just outside the frame.',
    'candid-over-shoulder': 'Shot from behind at an angle as the person glances back over their shoulder.',
    'candid-seated': 'The person sits at a table, on a bench, or at a bar, shot at eye level from across the table.',
    'candid-busy-hands': 'The person is busy with something in their hands, like a coffee, phone, keys, or bag, and looks down at it.',
  },
  street: {
    'street-low-wide': "Shot from low, about knee height, on the iPhone's 0.5x wide lens, so the legs look long and the buildings lean in; the person looks down or away with the head slightly bowed, in hard sunlight with crisp shadows.",
    'street-walking': 'Shot at eye level while the person walks toward the camera mid-stride, with a little motion in the hands and fabric.',
    'street-side-lean': 'Shot from the side at chest height while the person leans against a wall, railing, or shop window, relaxed and glancing down the street.',
    'street-steps': 'Shot from slightly above while the person sits on steps, a curb, or a low wall, legs stretched or crossed, the whole outfit visible.',
    'street-wide-scene': 'Shot from a few metres away so the person stands in the middle of the street scene, smaller in the frame, with the surroundings telling the story.',
  },
  mirror: {
    'mirror-straight': 'Standing straight on to the mirror, phone held at chest height.',
    'mirror-angled': 'Turned three-quarters to the mirror with one hip out, phone raised beside the face.',
    'mirror-step': 'Stepping toward the mirror with one foot forward, phone held low at the hip.',
  },
} as const satisfies Record<LookStyle, Record<string, string>>;

type ShotsByStyle = typeof lookShots;
export type LookShot = { [S in LookStyle]: keyof ShotsByStyle[S] }[LookStyle] & string;

const shotEntries = Object.entries(lookShots).flatMap(([style, shots]) =>
  Object.entries(shots).map(([id, description]) => ({ id, description, style: style as LookStyle })),
);

export const isLookShot = (value: string): value is LookShot =>
  shotEntries.some((entry) => entry.id === value);

export const shotStyle = (shot: string | undefined) =>
  shotEntries.find((entry) => entry.id === shot)?.style ?? null;

export const shotPrompt = (shot: string | undefined) =>
  shotEntries.find((entry) => entry.id === shot)?.description ?? null;

// How strongly hearts pull a shot type: each heart adds half the base weight,
// up to three times the base. Shots used in the last few looks drop to a third,
// so the feed keeps varying even around a favourite.
const likeBoost = 0.5;
const maxLikeBoost = 2;
const recentLooks = 3;
const recentFactor = 0.35;

export type ShotWeight = {
  style: LookStyle;
  shot: string;
  likes: number;
  recent: boolean;
  hidden: boolean;
  weight: number;
  chance: number;
};

/**
 * The current weight of every shot type for an account, the input of
 * [pickShot] and of the feed debug panel. Hidden shots weigh nothing, unless a
 * style's shots are all hidden; then the style ignores hiding.
 */
export async function shotWeights(
  database: Database | DatabaseClient,
  accountId: string,
): Promise<ShotWeight[]> {
  const [likes, recent, hidden] = await Promise.all([
    database.query<{ shot: string; likes: string }>(
      `SELECT planned_concept->>'shot' AS shot, count(*) AS likes FROM looks
       WHERE account_id=$1 AND liked_at IS NOT NULL AND deleted_at IS NULL AND planned_concept ? 'shot'
       GROUP BY 1`,
      [accountId],
    ),
    database.query<{ shot: string }>(
      `SELECT planned_concept->>'shot' AS shot FROM looks
       WHERE account_id=$1 AND deleted_at IS NULL AND planned_concept ? 'shot'
       ORDER BY created_at DESC LIMIT ${recentLooks}`,
      [accountId],
    ),
    hiddenShots(database, accountId),
  ]);
  const likesByShot = new Map(likes.rows.map((row) => [row.shot, Number(row.likes)]));
  const recentShots = new Set(recent.rows.map((row) => row.shot));
  return (Object.keys(lookShots) as LookStyle[]).flatMap((style) => {
    const entries = shotEntries.filter((entry) => entry.style === style);
    const allHidden = entries.every((entry) => hidden.includes(entry.id));
    const weighted = entries.map((entry) => {
      const likesCount = likesByShot.get(entry.id) ?? 0;
      const isHidden = hidden.includes(entry.id);
      const isRecent = recentShots.has(entry.id);
      const weight =
        isHidden && !allHidden
          ? 0
          : (1 + Math.min(likesCount * likeBoost, maxLikeBoost)) * (isRecent ? recentFactor : 1);
      return { style, shot: entry.id, likes: likesCount, recent: isRecent, hidden: isHidden, weight };
    });
    const total = weighted.reduce((sum, entry) => sum + entry.weight, 0);
    return weighted.map((entry) => ({ ...entry, chance: total ? entry.weight / total : 0 }));
  });
}

/**
 * Draws a shot of [style] by weight. [exclude] is left out, for "same outfit,
 * other perspective"; if nothing else has weight, any other shot of the style
 * is taken.
 */
export function pickShot(
  weights: ShotWeight[],
  style: LookStyle,
  exclude?: string,
  random: () => number = Math.random,
) {
  const candidates = weights.filter((entry) => entry.style === style && entry.shot !== exclude);
  const weighted = candidates.filter((entry) => entry.weight > 0);
  const pool = weighted.length ? weighted : candidates.map((entry) => ({ ...entry, weight: 1 }));
  const total = pool.reduce((sum, entry) => sum + entry.weight, 0);
  let roll = random() * total;
  for (const entry of pool) {
    roll -= entry.weight;
    if (roll < 0) return entry.shot;
  }
  return pool[pool.length - 1]!.shot;
}

export async function hiddenShots(database: Database | DatabaseClient, accountId: string) {
  const rows = await database.query<{ shot: string }>(
    'SELECT shot FROM look_shot_preferences WHERE account_id=$1 ORDER BY shot',
    [accountId],
  );
  return rows.rows.map((row) => row.shot);
}

export async function setShotHidden(
  database: Database,
  input: { accountId: string; shot: LookShot; hidden: boolean },
) {
  await database.query(
    input.hidden
      ? 'INSERT INTO look_shot_preferences(account_id,shot) VALUES($1,$2) ON CONFLICT DO NOTHING'
      : 'DELETE FROM look_shot_preferences WHERE account_id=$1 AND shot=$2',
    [input.accountId, input.shot],
  );
  return hiddenShots(database, input.accountId);
}
