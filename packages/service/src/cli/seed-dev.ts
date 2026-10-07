import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

import { PutObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';

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

// Fills a local dev account's Schrank with real pieces, so looks and proposals
// have something to work with.
//
//   npm run dev:seed [-- <email>]   default dev@form.local, the debug sign-in email
//
// The account is created the same way POST /v1/auth/dev would. The pieces are the
// real catalog images the app bundles for onboarding (apps/mobile/assets/onboarding),
// stored as PNG like the catalog pipeline does. The same image stands in for the
// source photo and the keyed image, so no real photo lives in the repo. Ids are
// derived from account and slug, so running it again adds nothing.

type Warmth = 'light' | 'mid' | 'warm';
type Formality = 'casual' | 'smart-casual' | 'business' | 'formal';
type Piece = {
  slug: string;
  // File name in apps/mobile/assets/onboarding, without .webp.
  asset: string;
  name: string;
  category: string;
  colors: string[];
  state?: 'owning' | 'wanting';
  traits: { kind: string; warmth: Warmth; formality: Formality; brand?: string };
};

const pieces: Piece[] = [
  // Slugs of the first seed, so accounts seeded before keep these three once.
  { slug: 'turtleneck', asset: 'turtleneck', name: 'Beige Ribbed Turtleneck Top', category: 'top', colors: ['beige'], traits: { kind: 'turtleneck top', warmth: 'mid', formality: 'smart-casual' } },
  { slug: 'wide-leg-pants', asset: 'balloon-pants', name: 'Black Wide-Leg Pants', category: 'pants', colors: ['black'], traits: { kind: 'wide-leg pants', warmth: 'mid', formality: 'casual' } },
  { slug: 'high-top-sneaker', asset: 'high-top', name: 'Nike Air Max Plus Cream', category: 'shoes', colors: ['cream', 'beige'], traits: { kind: 'sneakers', warmth: 'mid', formality: 'casual', brand: 'Nike' } },
  { slug: 'leather-jacket', asset: 'leather-jacket', name: 'Black Leather Jacket', category: 'jacket', colors: ['black'], traits: { kind: 'leather jacket', warmth: 'mid', formality: 'smart-casual' } },
  { slug: 'jersey', asset: 'jersey', name: 'Germany 1990 Football Jersey', category: 'top', colors: ['white', 'black', 'red', 'yellow'], traits: { kind: 'football jersey', warmth: 'light', formality: 'casual', brand: 'Adidas' } },
  { slug: 'maroon-sneaker', asset: 'maroon-sneaker', name: 'Nike Air Max Plus Burgundy', category: 'shoes', colors: ['burgundy'], traits: { kind: 'sneakers', warmth: 'mid', formality: 'casual', brand: 'Nike' } },
  { slug: 'sunglasses', asset: 'sunglasses', name: 'Black Sunglasses with Orange Lenses', category: 'accessory', colors: ['black', 'orange'], traits: { kind: 'sunglasses', warmth: 'light', formality: 'casual' } },
  { slug: 'teddy-coat', asset: 'teddy-coat', name: 'Beige Teddy Coat', category: 'coat', colors: ['beige'], traits: { kind: 'teddy coat', warmth: 'warm', formality: 'smart-casual' } },
  { slug: 'brown-trousers', asset: 'brown-trousers', name: 'Brown Pleated Trousers', category: 'pants', colors: ['brown'], traits: { kind: 'trousers', warmth: 'mid', formality: 'smart-casual' } },
  { slug: 'puffer', asset: 'puffer', name: 'The North Face Green Fleece Puffer', category: 'jacket', colors: ['green'], traits: { kind: 'puffer jacket', warmth: 'warm', formality: 'casual', brand: 'The North Face' } },
  { slug: 'striped-shirt', asset: 'striped-shirt', name: 'Yellow Striped Camp Shirt', category: 'top', colors: ['yellow', 'cream'], traits: { kind: 'camp shirt', warmth: 'light', formality: 'casual' } },
  { slug: 'shorts', asset: 'shorts', name: 'Black Shorts', category: 'pants', colors: ['black'], traits: { kind: 'shorts', warmth: 'light', formality: 'casual' } },
  { slug: 'white-sneaker', asset: 'white-sneaker', name: 'Nike Air Force 1 Sail', category: 'shoes', colors: ['cream', 'black'], traits: { kind: 'sneakers', warmth: 'mid', formality: 'casual', brand: 'Nike' } },
  { slug: 'ring', asset: 'ring', name: 'Silver Signet Ring', category: 'accessory', colors: ['silver'], traits: { kind: 'ring', warmth: 'light', formality: 'smart-casual' } },
  { slug: 'croc-jacket', asset: 'croc-jacket', name: 'Red Leather Jacket with Leopard Lining', category: 'jacket', colors: ['red', 'brown'], traits: { kind: 'leather jacket', warmth: 'mid', formality: 'casual' } },
  { slug: 'black-shirt', asset: 'black-shirt', name: 'Black Boxy Camp Shirt', category: 'top', colors: ['black'], traits: { kind: 'camp shirt', warmth: 'light', formality: 'smart-casual' } },
  { slug: 'black-pants', asset: 'black-pants', name: 'Black Straight Trousers', category: 'pants', colors: ['black'], traits: { kind: 'trousers', warmth: 'mid', formality: 'business' } },
  { slug: 'runner', asset: 'runner', name: 'Brown Suede Runner', category: 'shoes', colors: ['brown', 'white'], traits: { kind: 'sneakers', warmth: 'mid', formality: 'casual' } },
  { slug: 'leopard-jacket', asset: 'leopard-jacket', name: 'Black Bomber with Leopard Collar', category: 'jacket', colors: ['black', 'brown'], traits: { kind: 'bomber jacket', warmth: 'warm', formality: 'casual' } },
  { slug: 'white-tee', asset: 'white-tee', name: 'White Boxy T-Shirt', category: 'top', colors: ['white'], traits: { kind: 't-shirt', warmth: 'light', formality: 'casual' } },
  { slug: 'glasses', asset: 'glasses', name: 'Clear Frame Glasses', category: 'accessory', colors: ['transparent', 'green'], traits: { kind: 'glasses', warmth: 'light', formality: 'smart-casual' } },
  { slug: 'olive-jacket', asset: 'olive-jacket', name: 'Olive Work Jacket', category: 'jacket', colors: ['olive', 'brown'], state: 'wanting', traits: { kind: 'work jacket', warmth: 'mid', formality: 'casual' } },
  { slug: 'black-sneaker', asset: 'black-sneaker', name: 'Nike Air Force 1 Black', category: 'shoes', colors: ['black', 'white'], state: 'wanting', traits: { kind: 'sneakers', warmth: 'mid', formality: 'casual', brand: 'Nike' } },
];

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
  for (const [index, piece] of pieces.entries()) {
    const id = (role: string) => seedId(account.id, piece.slug, role);
    const existing = await database.query('SELECT 1 FROM wardrobe_items WHERE id = $1', [id('item')]);
    if (existing.rows.length) continue;

    const webp = await readFile(
      new URL(`../../../../apps/mobile/assets/onboarding/${piece.asset}.webp`, import.meta.url),
    );
    const { data: png, info } = await sharp(webp).png().toBuffer({ resolveWithObject: true });
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
           ) VALUES ($1, $2, $3, $4, $5, 'image/png', $6, $7, $8, 'ready', now())`,
          [assetId, account.id, purpose, key, versions.get(key), png.byteLength, info.width, info.height],
        );
      }
      await client.query('INSERT INTO source_photos (id, account_id, asset_id) VALUES ($1, $2, $3)', [
        id('photo'),
        account.id,
        id('source'),
      ]);
      // Staggered a minute apart in list order, so the Schrank shows them in a stable order.
      await client.query(
        `INSERT INTO wardrobe_items (id, account_id, source_photo_id, state, status, name, category, colors, created_at, updated_at)
         VALUES ($1, $2, $3, $4, 'ready', $5, $6, $7, now() - make_interval(mins => $8), now() - make_interval(mins => $8))`,
        [id('item'), account.id, id('photo'), piece.state ?? 'owning', piece.name, piece.category, piece.colors, pieces.length - index],
      );
      await client.query(
        `INSERT INTO item_traits (wardrobe_item_id, account_id, warmth, kind, formality, brand)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [id('item'), account.id, piece.traits.warmth, piece.traits.kind, piece.traits.formality, piece.traits.brand ?? null],
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
