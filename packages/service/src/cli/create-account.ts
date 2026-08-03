import { accountCredentialsSchema } from '@form/contracts';

import { createAccount, createDatabase, migrateDatabase, readDatabaseConfig } from '../index.js';

const email = process.env.ADMIN_ACCOUNT_EMAIL;
const password = process.env.ADMIN_ACCOUNT_PASSWORD;
if (!email || !password) {
  throw new Error('Set ADMIN_ACCOUNT_EMAIL and ADMIN_ACCOUNT_PASSWORD to create an account.');
}
const credentials = accountCredentialsSchema.safeParse({ email, password });
if (!credentials.success) {
  throw new Error(
    'Administrator credentials must use a valid email and a password of at most 256 characters.',
  );
}
if (credentials.data.password.length < 12) {
  throw new Error('Administrator-created passwords must contain at least 12 characters.');
}

const database = createDatabase(readDatabaseConfig());
try {
  await migrateDatabase(database);
  const account = await createAccount(database, credentials.data);
  console.log(`Created FORM account ${account.email} (${account.id}).`);
} finally {
  await database.end();
}
