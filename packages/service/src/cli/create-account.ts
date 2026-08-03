import { createAccount, createDatabase, migrateDatabase, readDatabaseConfig } from '../index.js';

const email = process.env.ADMIN_ACCOUNT_EMAIL;
const password = process.env.ADMIN_ACCOUNT_PASSWORD;
if (!email || !password) {
  throw new Error('Set ADMIN_ACCOUNT_EMAIL and ADMIN_ACCOUNT_PASSWORD to create an account.');
}
if (password.length < 12) {
  throw new Error('Administrator-created passwords must contain at least 12 characters.');
}

const database = createDatabase(readDatabaseConfig());
try {
  await migrateDatabase(database);
  const account = await createAccount(database, { email, password });
  console.log(`Created FORM account ${account.email} (${account.id}).`);
} finally {
  await database.end();
}
