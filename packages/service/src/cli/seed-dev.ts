import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

import { PutObjectCommand } from '@aws-sdk/client-s3';

import {
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  signInWithIdentity,
  withTransaction,
} from '../index.js';

// Gives a local dev account a few ready pieces so the Schrank is not empty.
//
//   npm run dev:seed [-- <email>]   default dev@form.local, the debug sign-in email
//
// The account is created the same way POST /v1/auth/dev would. The pieces are real
// catalog images from stargate (laid-flat-v4, high). The transparent PNG stands in
// for the source photo and the keyed image too, so no real photo lives in the repo.
// Ids are derived from account and piece, so running it again adds nothing.

const pieces = [
  {
    slug: 'turtleneck',
    name: 'Beige Ribbed Turtleneck Top',
    category: 'top',
    colors: ['beige'],
    traits: { kind: 'turtleneck top', warmth: 'mid', formality: 'smart-casual' },
  },
  {
    slug: 'wide-leg-pants',
    name: 'Black Wide-Leg Pants',
    category: 'pants',
    colors: ['black'],
    traits: { kind: 'wide-leg pants', warmth: 'mid', formality: 'casual' },
  },
  {
    slug: 'high-top-sneaker',
    name: 'White High-Top Sneaker',
    category: 'shoes',
    colors: ['white', 'cream', 'beige'],
    traits: { kind: 'high-top sneakers', warmth: 'mid', formality: 'casual' },
  },
] as const;

const localHostnames = new Set(['localhost', '127.0.0.1', '::1']);
for (const url of [process.env.DATABASE_URL, process.env.S3_ENDPOINT]) {
  if (!localHostnames.has(new URL(url ?? 'invalid://').hostname))
    throw new Error('The dev seed only runs against a local database and object storage.');
}

function seedId(...parts: string[]): string {
  const hex = createHash('sha256').update(parts.join(':')).digest('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-8${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

const email = (process.argv[2] ?? 'dev@form.local').trim().toLowerCase();
const database = createDatabase(readDatabaseConfig());
const storage = createPrivateObjectStorage(readObjectStorageConfig());
try {
  await migrateDatabase(database);
  await ensurePrivateBucket(storage);
  const account = await signInWithIdentity(database, { provider: 'dev', subject: email, email });
  if (!account) throw new Error(`Account ${email} is disabled.`);

  let added = 0;
  for (const piece of pieces) {
    const id = (role: string) => seedId(account.id, piece.slug, role);
    const existing = await database.query('SELECT 1 FROM wardrobe_items WHERE id = $1', [id('item')]);
    if (existing.rows.length) continue;

    const png = await readFile(new URL(`../../seed/${piece.slug}.png`, import.meta.url));
    const assets = [
      [id('source'), 'source-photo', `accounts/${account.id}/source-photos/${id('source')}`],
      [id('keyed'), 'shelf-image-keyed', `accounts/${account.id}/catalog/shelf-image-keyed/${id('keyed')}`],
      [
        id('transparent'),
        'shelf-image-transparent',
        `accounts/${account.id}/catalog/shelf-image-transparent/${id('transparent')}`,
      ],
    ] as const;
    const versions = new Map<string, string>();
    for (const [, , key] of assets) {
      const uploaded = await storage.client.send(
        new PutObjectCommand({ Bucket: storage.bucket, Key: key, Body: png, ContentType: 'image/png' }),
      );
      if (!uploaded.VersionId) throw new Error('The bucket must have versioning enabled.');
      versions.set(key, uploaded.VersionId);
    }

    const metadata = { name: piece.name, category: piece.category, colors: piece.colors, notes: null };
    await withTransaction(database, async (client) => {
      for (const [assetId, purpose, key] of assets) {
        await client.query(
          `INSERT INTO private_assets (
             id, account_id, purpose, object_key, object_version_id, content_type, byte_size,
             pixel_width, pixel_height, state, ready_at
           ) VALUES ($1, $2, $3, $4, $5, 'image/png', $6, 816, 816, 'ready', now())`,
          [assetId, account.id, purpose, key, versions.get(key), png.byteLength],
        );
      }
      await client.query('INSERT INTO source_photos (id, account_id, asset_id) VALUES ($1, $2, $3)', [
        id('photo'),
        account.id,
        id('source'),
      ]);
      await client.query(
        `INSERT INTO wardrobe_items (id, account_id, source_photo_id, state, status, name, category, colors)
         VALUES ($1, $2, $3, 'owning', 'ready', $4, $5, $6)`,
        [id('item'), account.id, id('photo'), piece.name, piece.category, piece.colors],
      );
      await client.query(
        `INSERT INTO item_traits (wardrobe_item_id, account_id, warmth, kind, formality)
         VALUES ($1, $2, $3, $4, $5)`,
        [id('item'), account.id, piece.traits.warmth, piece.traits.kind, piece.traits.formality],
      );
      await client.query(
        `INSERT INTO generation_attempts (
           id, account_id, wardrobe_item_id, source_photo_id, keyed_asset_id, transparent_asset_id,
           state, reviewed_metadata, model, quality, output_size, prompt_version, finished_at
         ) VALUES ($1, $2, $3, $4, $5, $6, 'kept', $7, 'seed', 'high', '816x816', 'laid-flat-v4', now())`,
        [id('attempt'), account.id, id('item'), id('photo'), id('keyed'), id('transparent'), metadata],
      );
      await client.query(
        `INSERT INTO shelf_image_versions (
           id, account_id, wardrobe_item_id, generation_attempt_id, keyed_asset_id,
           transparent_asset_id, quality, output_size, prompt_version, kept_at
         ) VALUES ($1, $2, $3, $4, $5, $6, 'high', '816x816', 'laid-flat-v4', now())`,
        [id('version'), account.id, id('item'), id('attempt'), id('keyed'), id('transparent')],
      );
      await client.query(
        'UPDATE wardrobe_items SET current_shelf_image_version_id = $1, record_version = 1 WHERE id = $2',
        [id('version'), id('item')],
      );
    });
    added += 1;
  }
  console.log(`Seeded ${added} of ${pieces.length} pieces into ${email} (${account.id}).`);
} finally {
  storage.client.destroy();
  await database.end();
}
