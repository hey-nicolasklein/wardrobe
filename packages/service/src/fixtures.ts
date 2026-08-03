import type { Database } from './database.js';
import { withTransaction } from './database.js';
import type { PrivateAssetStore } from './assets.js';

export const fixtureAccounts = [
  {
    id: '00000000-0000-4000-8000-000000000001',
    email: 'alex@example.test',
    scenario: 'populated',
  },
  {
    id: '00000000-0000-4000-8000-000000000002',
    email: 'blair@example.test',
    scenario: 'cross-account-denial',
  },
] as const;

export async function resetFixtureAccount(
  database: Database,
  assets: PrivateAssetStore,
  account: (typeof fixtureAccounts)[number],
): Promise<void> {
  if (!fixtureAccounts.some(({ id }) => id === account.id)) {
    throw new Error('Fixture reset is restricted to known fixture accounts');
  }

  await assets.deleteAccountObjects(account.id);
  await withTransaction(database, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [account.id]);
    await client.query('DELETE FROM accounts WHERE id = $1', [account.id]);
    await client.query(
      `INSERT INTO accounts (id, email) VALUES ($1, $2)`,
      [account.id, account.email],
    );
    await client.query(
      `INSERT INTO fixture_scenarios (account_id, scenario)
       VALUES ($1, $2)`,
      [account.id, account.scenario],
    );
  });
}

export async function resetFixtures(
  database: Database,
  assets: PrivateAssetStore,
): Promise<void> {
  for (const account of fixtureAccounts) {
    await resetFixtureAccount(database, assets, account);
  }
}
