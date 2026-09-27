import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';

import {
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  withTransaction,
} from '../index.js';

// Copies one account with all its records and stored images between deployments.
//
//   export <email> <dir>  writes records.json and objects/<asset id> into <dir>
//   import <dir>          recreates the account in the configured database and bucket
//
// Object version IDs cannot be carried over, so import uploads each object anew
// and rewrites private_assets.object_version_id. Import refuses an account whose
// id or email already exists; it never overwrites.

// Insert order does not matter: import disables FK triggers for the transaction.
const accountTables = [
  'account_identities',
  'credit_ledger',
  'private_assets',
  'source_photos',
  'detection_attempts',
  'detection_proposals',
  'wardrobe_items',
  'generation_attempts',
  'shelf_image_versions',
  'character_sheets',
  'looks',
  'idempotency_commands',
  'remote_image_jobs',
] as const;

type Snapshot = {
  exportedAt: string;
  migrations: string[];
  tables: Record<string, unknown[]>;
};

const [command, ...args] = process.argv.slice(2);
const database = createDatabase(readDatabaseConfig());
const storage = createPrivateObjectStorage(readObjectStorageConfig());

async function rows(sql: string, params: unknown[]): Promise<unknown[]> {
  const result = await database.query<{ rows: unknown[] | null }>(
    `SELECT json_agg(t) AS rows FROM (${sql}) t`,
    params,
  );
  return result.rows[0]?.rows ?? [];
}

async function exportAccount(email: string, dir: string) {
  const account = await database.query<{ id: string }>('SELECT id FROM accounts WHERE email = $1', [
    email.toLowerCase(),
  ]);
  const accountId = account.rows[0]?.id;
  if (!accountId) throw new Error(`No account with email ${email}.`);

  const tables: Record<string, unknown[]> = {
    accounts: await rows('SELECT * FROM accounts WHERE id = $1', [accountId]),
  };
  for (const table of accountTables) {
    const filter =
      table === 'private_assets'
        ? "AND state = 'ready'"
        : table === 'remote_image_jobs'
          ? "AND state NOT IN ('queued', 'leased')"
          : '';
    tables[table] = await rows(`SELECT * FROM ${table} WHERE account_id = $1 ${filter}`, [accountId]);
  }
  tables.look_items = await rows(
    'SELECT li.* FROM look_items li JOIN looks l ON l.id = li.look_id WHERE l.account_id = $1',
    [accountId],
  );
  const migrations = await database.query<{ name: string }>(
    'SELECT name FROM schema_migrations ORDER BY name',
  );

  await mkdir(join(dir, 'objects'), { recursive: true });
  const assets = tables.private_assets as { id: string; object_key: string; object_version_id: string }[];
  for (const asset of assets) {
    const object = await storage.client.send(
      new GetObjectCommand({ Bucket: storage.bucket, Key: asset.object_key, VersionId: asset.object_version_id }),
    );
    await writeFile(join(dir, 'objects', asset.id), await object.Body!.transformToByteArray());
  }
  const snapshot: Snapshot = {
    exportedAt: new Date().toISOString(),
    migrations: migrations.rows.map((row) => row.name),
    tables,
  };
  await writeFile(join(dir, 'records.json'), JSON.stringify(snapshot));
  console.log(`Exported ${email} (${accountId}) with ${assets.length} objects to ${dir}.`);
}

async function importAccount(dir: string) {
  const snapshot = JSON.parse(await readFile(join(dir, 'records.json'), 'utf8')) as Snapshot;
  const account = snapshot.tables.accounts![0] as { id: string; email: string };
  await migrateDatabase(database);
  await ensurePrivateBucket(storage);

  const existing = await database.query('SELECT 1 FROM accounts WHERE id = $1 OR email = $2', [
    account.id,
    account.email,
  ]);
  if (existing.rows.length) throw new Error(`Account ${account.email} already exists here.`);

  // Upload first. A failed import then leaves only unreferenced objects behind.
  const versions = new Map<string, string>();
  const assets = snapshot.tables.private_assets as { id: string; object_key: string; content_type: string }[];
  for (const asset of assets) {
    const uploaded = await storage.client.send(
      new PutObjectCommand({
        Bucket: storage.bucket,
        Key: asset.object_key,
        ContentType: asset.content_type,
        Body: await readFile(join(dir, 'objects', asset.id)),
      }),
    );
    if (!uploaded.VersionId) throw new Error('The target bucket must have versioning enabled.');
    versions.set(asset.id, uploaded.VersionId);
  }

  await withTransaction(database, async (client) => {
    await client.query('SET LOCAL session_replication_role = replica');
    for (const [table, records] of Object.entries(snapshot.tables)) {
      if (!records.length) continue;
      await client.query(
        `INSERT INTO ${table} SELECT * FROM json_populate_recordset(null::${table}, $1)`,
        [JSON.stringify(records)],
      );
    }
    for (const [assetId, versionId] of versions) {
      await client.query('UPDATE private_assets SET object_version_id = $2 WHERE id = $1', [
        assetId,
        versionId,
      ]);
    }
  });
  console.log(`Imported ${account.email} (${account.id}) with ${versions.size} objects.`);
}

try {
  if (command === 'export' && args.length === 2) await exportAccount(args[0]!, args[1]!);
  else if (command === 'import' && args.length === 1) await importAccount(args[0]!);
  else throw new Error('Usage: account-snapshot export <email> <dir> | import <dir>');
} finally {
  await database.end();
}
