import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import type { Database } from './database.js';
import { withTransaction } from './database.js';

const migrationsDirectory = fileURLToPath(
  new URL('../migrations/', import.meta.url),
);

export async function runMigrations(database: Database): Promise<void> {
  await database.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);

  const migrationNames = (await readdir(migrationsDirectory))
    .filter((name) => name.endsWith('.sql'))
    .sort();

  await withTransaction(database, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock($1)', [0x464f524d]);

    for (const name of migrationNames) {
      const existing = await client.query(
        'SELECT 1 FROM schema_migrations WHERE name = $1',
        [name],
      );

      if (existing.rowCount) continue;

      const sql = await readFile(`${migrationsDirectory}/${name}`, 'utf8');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [
        name,
      ]);
    }
  });
}
