import * as SQLite from 'expo-sqlite';

import { mergePendingEdit } from './wardrobe-state';
import {
  emptyWardrobeCache,
  type CachedWardrobe,
  type PendingWardrobeEdit,
} from './wardrobe-types';

type OutboxRow = {
  payload: string;
};

let databasePromise: ReturnType<typeof SQLite.openDatabaseAsync> | null = null;

async function database() {
  if (!databasePromise) {
    databasePromise = SQLite.openDatabaseAsync('form-wardrobe.db').then(async (db) => {
      await db.execAsync(`
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS wardrobe_cache (
          account_id TEXT PRIMARY KEY NOT NULL,
          payload TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS wardrobe_outbox (
          account_id TEXT NOT NULL,
          wardrobe_item_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (account_id, wardrobe_item_id)
        );
      `);
      return db;
    });
  }
  return databasePromise;
}

export async function readWardrobeCache(accountId: string): Promise<CachedWardrobe> {
  const db = await database();
  const row = await db.getFirstAsync<{ payload: string }>(
    'SELECT payload FROM wardrobe_cache WHERE account_id = ?',
    accountId,
  );
  if (!row) return emptyWardrobeCache;
  try {
    return JSON.parse(row.payload) as CachedWardrobe;
  } catch {
    return emptyWardrobeCache;
  }
}

export async function writeWardrobeCache(
  accountId: string,
  cache: CachedWardrobe,
): Promise<void> {
  const db = await database();
  await db.runAsync(
    `INSERT INTO wardrobe_cache (account_id, payload, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(account_id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at`,
    accountId,
    JSON.stringify(cache),
    new Date().toISOString(),
  );
}

export async function readPendingEdits(accountId: string): Promise<PendingWardrobeEdit[]> {
  const db = await database();
  const rows = await db.getAllAsync<OutboxRow>(
    'SELECT payload FROM wardrobe_outbox WHERE account_id = ? ORDER BY created_at',
    accountId,
  );
  return rows.flatMap((row) => {
    try {
      return [JSON.parse(row.payload) as PendingWardrobeEdit];
    } catch {
      return [];
    }
  });
}

export async function putPendingEdit(edit: PendingWardrobeEdit): Promise<PendingWardrobeEdit> {
  const db = await database();
  const row = await db.getFirstAsync<OutboxRow>(
    'SELECT payload FROM wardrobe_outbox WHERE account_id = ? AND wardrobe_item_id = ?',
    edit.accountId,
    edit.wardrobeItemId,
  );
  let existing: PendingWardrobeEdit | undefined;
  try {
    existing = row ? (JSON.parse(row.payload) as PendingWardrobeEdit) : undefined;
  } catch {
    existing = undefined;
  }
  if (existing?.attemptedAt) {
    throw new Error('This item already has an edit awaiting confirmation from the service.');
  }
  const merged = mergePendingEdit(existing, edit);
  await db.runAsync(
    `INSERT INTO wardrobe_outbox (account_id, wardrobe_item_id, payload, created_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(account_id, wardrobe_item_id) DO UPDATE SET payload = excluded.payload`,
    merged.accountId,
    merged.wardrobeItemId,
    JSON.stringify(merged),
    merged.createdAt,
  );
  return merged;
}

export async function setPendingEditAttempted(
  edit: PendingWardrobeEdit,
): Promise<PendingWardrobeEdit> {
  if (edit.attemptedAt) return edit;
  const attempted = { ...edit, attemptedAt: new Date().toISOString() };
  const db = await database();
  await db.runAsync(
    'UPDATE wardrobe_outbox SET payload = ? WHERE account_id = ? AND wardrobe_item_id = ?',
    JSON.stringify(attempted),
    edit.accountId,
    edit.wardrobeItemId,
  );
  return attempted;
}

export async function deletePendingEdit(accountId: string, wardrobeItemId: string): Promise<void> {
  const db = await database();
  await db.runAsync(
    'DELETE FROM wardrobe_outbox WHERE account_id = ? AND wardrobe_item_id = ?',
    accountId,
    wardrobeItemId,
  );
}

export async function setPendingEditError(
  edit: PendingWardrobeEdit,
  error: string,
): Promise<PendingWardrobeEdit> {
  const failed = { ...edit, error };
  const db = await database();
  await db.runAsync(
    'UPDATE wardrobe_outbox SET payload = ? WHERE account_id = ? AND wardrobe_item_id = ?',
    JSON.stringify(failed),
    edit.accountId,
    edit.wardrobeItemId,
  );
  return failed;
}
