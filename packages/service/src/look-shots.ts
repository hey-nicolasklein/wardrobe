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

/**
 * The shots the planner may pick for [style]. Shots the user hid are left out,
 * unless that would leave none.
 */
export function shotsFor(style: LookStyle, hidden: string[]) {
  const all = shotEntries.filter((entry) => entry.style === style);
  const open = all.filter((entry) => !hidden.includes(entry.id));
  return (open.length ? open : all).map(({ id, description }) => ({ id, description }));
}

/** A different shot of the same style for "same outfit, other perspective". */
export function pickReshoot(style: LookStyle, current: string | undefined, hidden: string[]) {
  const options = shotsFor(style, [...hidden, ...(current ? [current] : [])]).filter(
    (entry) => entry.id !== current,
  );
  const pool = options.length ? options : shotsFor(style, []);
  return pool[Math.floor(Math.random() * pool.length)]!.id;
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
