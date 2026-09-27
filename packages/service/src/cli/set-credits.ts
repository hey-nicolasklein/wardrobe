import { createDatabase, readDatabaseConfig, setCreditBalance } from '../index.js';

// Usage: set-credits <email> <balance>
// Meters the account and sets its credit balance, e.g. to reset a test budget.
const [email, balanceText] = process.argv.slice(2);
const balance = Number(balanceText);
if (!email || !Number.isInteger(balance) || balance < 0)
  throw new Error('Usage: set-credits <email> <balance>');

const database = createDatabase(readDatabaseConfig());
try {
  const account = await database.query<{ id: string }>('SELECT id FROM accounts WHERE email = $1', [
    email.toLowerCase(),
  ]);
  const accountId = account.rows[0]?.id;
  if (!accountId) throw new Error(`No account with email ${email}.`);
  await setCreditBalance(database, { accountId, balance, note: 'set-credits CLI' });
  console.log(`${email} now has ${balance} credits.`);
} finally {
  await database.end();
}
