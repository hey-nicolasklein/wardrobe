import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';

import type { DatabaseConfig } from './config.js';

const { Pool } = pg;

export type Database = pg.Pool;
export type DatabaseClient = pg.PoolClient;

export function createDatabase(config: DatabaseConfig): Database {
  return new Pool({
    connectionString: config.DATABASE_URL,
    max: 10,
    connectionTimeoutMillis: 5_000,
    idleTimeoutMillis: 30_000,
  });
}

export async function migrateDatabase(database: Database): Promise<string[]> {
  await database.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);

  const migrationDirectory = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
  const migrationNames = (await readdir(migrationDirectory))
    .filter((name) => /^\d+_.+\.sql$/.test(name))
    .sort();
  const applied: string[] = [];

  for (const name of migrationNames) {
    const existing = await database.query<{ exists: boolean }>(
      'SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE name = $1) AS exists',
      [name],
    );
    if (existing.rows[0]?.exists) continue;

    const sql = await readFile(join(migrationDirectory, name), 'utf8');
    const client = await database.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [name]);
      await client.query('COMMIT');
      applied.push(name);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  return applied;
}

export async function checkDatabase(database: Database): Promise<void> {
  await database.query('SELECT 1');
}

export async function withTransaction<T>(
  database: Database,
  operation: (client: DatabaseClient) => Promise<T>,
): Promise<T> {
  const client = await database.connect();
  try {
    await client.query('BEGIN');
    const result = await operation(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
