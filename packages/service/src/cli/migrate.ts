import { createDatabase, migrateDatabase, readDatabaseConfig } from '../index.js';

const database = createDatabase(readDatabaseConfig());
try {
  const applied = await migrateDatabase(database);
  console.log(applied.length === 0 ? 'Database is current.' : `Applied: ${applied.join(', ')}`);
} finally {
  await database.end();
}
