import { randomUUID } from 'node:crypto';

import type { Database } from './database.js';
import { withTransaction } from './database.js';
import { OwnedResourceNotFoundError } from './media.js';

export type LookCollection = {
  id: string;
  name: string;
  emoji: string;
  createdAt: string;
  /** Newest first, so the first look is the cover. */
  lookIds: string[];
};

/** The account's Sammlungen, oldest first, each with its looks. */
export async function listLookCollections(database: Database, accountId: string): Promise<LookCollection[]> {
  const result = await database.query<{ id: string; name: string; emoji: string; created_at: Date; look_ids: string[] }>(
    `SELECT c.id, c.name, c.emoji, c.created_at,
       COALESCE(array_agg(e.look_id ORDER BY e.added_at DESC) FILTER (WHERE l.id IS NOT NULL), '{}') AS look_ids
     FROM look_collections c
     LEFT JOIN look_collection_entries e ON e.collection_id = c.id
     LEFT JOIN looks l ON l.id = e.look_id AND l.deleted_at IS NULL
     WHERE c.account_id = $1
     GROUP BY c.id
     ORDER BY c.created_at`,
    [accountId],
  );
  return result.rows.map((row) => ({
    id: row.id,
    name: row.name,
    emoji: row.emoji,
    createdAt: row.created_at.toISOString(),
    lookIds: row.look_ids,
  }));
}

export async function createLookCollection(
  database: Database,
  input: { accountId: string; name: string; emoji: string },
): Promise<LookCollection> {
  const id = randomUUID();
  const result = await database.query<{ created_at: Date }>(
    `INSERT INTO look_collections (id, account_id, name, emoji) VALUES ($1, $2, $3, $4) RETURNING created_at`,
    [id, input.accountId, input.name, input.emoji],
  );
  return { id, name: input.name, emoji: input.emoji, createdAt: result.rows[0]!.created_at.toISOString(), lookIds: [] };
}

/** Removes a Sammlung. Its looks stay in the feed. */
export async function deleteLookCollection(database: Database, input: { accountId: string; collectionId: string }) {
  const result = await database.query(`DELETE FROM look_collections WHERE id = $1 AND account_id = $2`, [
    input.collectionId,
    input.accountId,
  ]);
  if (!result.rowCount) throw new OwnedResourceNotFoundError();
}

/**
 * Files a look into a Sammlung or takes it out. Filing also hearts the look,
 * so it keeps weighting future looks the way "Würde ich tragen" did.
 */
export async function setLookInCollection(
  database: Database,
  input: { accountId: string; collectionId: string; lookId: string; included: boolean },
) {
  await withTransaction(database, async (client) => {
    const owned = await client.query(
      `SELECT 1 FROM look_collections c, looks l
       WHERE c.id = $1 AND c.account_id = $3 AND l.id = $2 AND l.account_id = $3 AND l.deleted_at IS NULL`,
      [input.collectionId, input.lookId, input.accountId],
    );
    if (!owned.rows[0]) throw new OwnedResourceNotFoundError();
    if (input.included) {
      await client.query(
        `INSERT INTO look_collection_entries (collection_id, look_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [input.collectionId, input.lookId],
      );
      await client.query(`UPDATE looks SET liked_at = COALESCE(liked_at, now()) WHERE id = $1`, [input.lookId]);
    } else {
      await client.query(`DELETE FROM look_collection_entries WHERE collection_id = $1 AND look_id = $2`, [
        input.collectionId,
        input.lookId,
      ]);
    }
  });
  return { included: input.included };
}
