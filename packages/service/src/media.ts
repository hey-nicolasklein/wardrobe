import { randomUUID } from 'node:crypto';

import { GetObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';

import type { Database } from './database.js';
import { withTransaction } from './database.js';
import { findOwnedPrivateAsset, type OwnedPrivateAsset } from './ownership.js';
import {
  createSignedDownloadUrl,
  createSignedUploadUrl,
  type PrivateObjectStorage,
} from './storage.js';

const maximumSourceBytes = 20 * 1024 * 1024;
const maximumSourceEdge = 12_000;
const maximumSourcePixels = 40_000_000;
const signedUrlLifetimeSeconds = 300;

const decodedFormatsByContentType: Record<string, readonly string[]> = {
  'image/jpeg': ['jpeg'],
  'image/png': ['png'],
  'image/webp': ['webp'],
  'image/heic': ['heif'],
  'image/heif': ['heif'],
};

export class MediaValidationError extends Error {
  constructor(
    readonly code:
      | 'file-too-large'
      | 'file-type-mismatch'
      | 'invalid-image'
      | 'invalid-dimensions'
      | 'upload-missing',
    message: string,
  ) {
    super(message);
    this.name = 'MediaValidationError';
  }
}

export class IdempotencyConflictError extends Error {
  constructor() {
    super('This idempotency key was already used for another command.');
    this.name = 'IdempotencyConflictError';
  }
}

export class OwnedResourceNotFoundError extends Error {
  constructor() {
    super('The requested private resource does not exist.');
    this.name = 'OwnedResourceNotFoundError';
  }
}

export function validateSourceUploadIntent(input: { byteSize: number }): void {
  if (input.byteSize > maximumSourceBytes) {
    throw new MediaValidationError(
      'file-too-large',
      `Source Photos must be ${maximumSourceBytes / 1024 / 1024} MB or smaller.`,
    );
  }
}

export async function createSourceUploadIntent(
  database: Database,
  storage: PrivateObjectStorage,
  input: { accountId: string; contentType: string; byteSize: number },
): Promise<{ assetId: string; uploadUrl: string; expiresAt: Date; headers: Record<string, string> }> {
  validateSourceUploadIntent(input);
  const assetId = randomUUID();
  const objectKey = `accounts/${input.accountId}/source-photos/${assetId}`;
  await database.query(
    `INSERT INTO private_assets (
       id, account_id, purpose, object_key, content_type, byte_size, state
     ) VALUES ($1, $2, 'source-photo', $3, $4, $5, 'pending')`,
    [assetId, input.accountId, objectKey, input.contentType, input.byteSize],
  );
  const uploadUrl = await createSignedUploadUrl(
    storage,
    objectKey,
    input.contentType,
    input.byteSize,
    signedUrlLifetimeSeconds,
  );
  return {
    assetId,
    uploadUrl,
    expiresAt: new Date(Date.now() + signedUrlLifetimeSeconds * 1_000),
    headers: { 'Content-Type': input.contentType },
  };
}

async function readAndValidateImage(
  storage: PrivateObjectStorage,
  asset: OwnedPrivateAsset,
): Promise<{ width: number; height: number; objectVersionId: string }> {
  let response;
  try {
    response = await storage.client.send(
      new GetObjectCommand({ Bucket: storage.bucket, Key: asset.objectKey }),
    );
  } catch (error) {
    const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
    if (status === 404 || (error as { name?: string }).name === 'NoSuchKey') {
      throw new MediaValidationError(
        'upload-missing',
        'The upload is missing or incomplete. Request a new upload and try again.',
      );
    }
    throw error;
  }
  const bytes = await response.Body?.transformToByteArray();
  if (!bytes || bytes.byteLength !== asset.byteSize || bytes.byteLength > maximumSourceBytes) {
    throw new MediaValidationError('file-too-large', 'Uploaded bytes do not match the upload intent.');
  }

  const image = sharp(bytes, { failOn: 'error', limitInputPixels: maximumSourcePixels });
  let metadata: Awaited<ReturnType<typeof image.metadata>>;
  try {
    metadata = await image.metadata();
  } catch {
    throw new MediaValidationError('invalid-image', 'The uploaded file is not a decodable image.');
  }
  const allowedFormats = decodedFormatsByContentType[asset.contentType] ?? [];
  if (!metadata.format || !allowedFormats.includes(metadata.format)) {
    throw new MediaValidationError(
      'file-type-mismatch',
      'The uploaded image type does not match its declared type.',
    );
  }
  if (
    !metadata.width ||
    !metadata.height ||
    metadata.width > maximumSourceEdge ||
    metadata.height > maximumSourceEdge ||
    metadata.width * metadata.height > maximumSourcePixels
  ) {
    throw new MediaValidationError(
      'invalid-dimensions',
      `Source Photos must be at most ${maximumSourceEdge} pixels per edge and ${maximumSourcePixels / 1_000_000} megapixels.`,
    );
  }
  try {
    await image.stats();
  } catch {
    throw new MediaValidationError('invalid-image', 'The uploaded file is not a decodable image.');
  }
  if (!response.VersionId) {
    throw new Error('Private object storage did not return a version ID for an uploaded object.');
  }
  return {
    width: metadata.width,
    height: metadata.height,
    objectVersionId: response.VersionId,
  };
}

export async function completeSourceUpload(
  database: Database,
  storage: PrivateObjectStorage,
  input: { accountId: string; assetId: string; idempotencyKey: string },
): Promise<{ sourcePhotoId: string; sourcePhotoCreatedAt: Date; asset: OwnedPrivateAsset }> {
  const requestHash = input.assetId;
  return withTransaction(database, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [
      `${input.accountId}:${input.idempotencyKey}`,
    ]);
    const replay = await client.query<{
      command_kind: string;
      request_hash: string;
      response_body: { sourcePhotoId: string };
    }>(
      `SELECT command_kind, request_hash, response_body
       FROM idempotency_commands
       WHERE account_id = $1 AND key = $2`,
      [input.accountId, input.idempotencyKey],
    );
    if (replay.rows[0]) {
      if (
        replay.rows[0].command_kind !== 'complete-source-upload' ||
        replay.rows[0].request_hash !== requestHash
      ) {
        throw new IdempotencyConflictError();
      }
      const asset = await findOwnedPrivateAsset(client, input.accountId, input.assetId);
      if (!asset) throw new Error('Completed asset is missing.');
      const source = await client.query<{ created_at: Date }>(
        `SELECT created_at FROM source_photos WHERE id = $1 AND account_id = $2`,
        [replay.rows[0].response_body.sourcePhotoId, input.accountId],
      );
      if (!source.rows[0]) throw new Error('Completed Source Photo is missing.');
      return {
        sourcePhotoId: replay.rows[0].response_body.sourcePhotoId,
        sourcePhotoCreatedAt: source.rows[0].created_at,
        asset,
      };
    }

    const asset = await findOwnedPrivateAsset(client, input.accountId, input.assetId);
    if (!asset || asset.purpose !== 'source-photo') throw new OwnedResourceNotFoundError();
    const validation =
      asset.state === 'pending'
        ? await readAndValidateImage(storage, asset)
        : {
            width: asset.pixelWidth!,
            height: asset.pixelHeight!,
            objectVersionId: asset.objectVersionId!,
          };
    if (!validation.objectVersionId) {
      throw new Error('Ready private asset is not bound to a validated object version.');
    }
    await client.query(
      `UPDATE private_assets
       SET state = 'ready', pixel_width = $3, pixel_height = $4,
           object_version_id = $5, ready_at = now()
       WHERE id = $1 AND account_id = $2 AND state = 'pending'`,
      [
        input.assetId,
        input.accountId,
        validation.width,
        validation.height,
        validation.objectVersionId,
      ],
    );
    const sourcePhotoId = randomUUID();
    const source = await client.query<{ id: string; created_at: Date }>(
      `INSERT INTO source_photos (id, account_id, asset_id)
       VALUES ($1, $2, $3)
       ON CONFLICT (account_id, asset_id) DO UPDATE SET asset_id = EXCLUDED.asset_id
       RETURNING id, created_at`,
      [sourcePhotoId, input.accountId, input.assetId],
    );
    const finalSourcePhotoId = source.rows[0]!.id;
    await client.query(
      `INSERT INTO idempotency_commands (
         account_id, key, command_kind, request_hash, response_status, response_body, expires_at
       ) VALUES ($1, $2, 'complete-source-upload', $3, 200, $4, now() + interval '24 hours')`,
      [input.accountId, input.idempotencyKey, requestHash, { sourcePhotoId: finalSourcePhotoId }],
    );
    return {
      sourcePhotoId: finalSourcePhotoId,
      sourcePhotoCreatedAt: source.rows[0]!.created_at,
      asset: {
        ...asset,
        state: 'ready' as const,
        pixelWidth: validation.width,
        pixelHeight: validation.height,
        objectVersionId: validation.objectVersionId,
      },
    };
  });
}

export async function createOwnedAssetDownload(
  database: Database,
  storage: PrivateObjectStorage,
  input: { accountId: string; assetId: string },
): Promise<{ downloadUrl: string; expiresAt: Date } | null> {
  const asset = await findOwnedPrivateAsset(database, input.accountId, input.assetId);
  if (!asset || asset.state !== 'ready' || !asset.objectVersionId) return null;
  return {
    downloadUrl: await createSignedDownloadUrl(
      storage,
      asset.objectKey,
      asset.objectVersionId,
      signedUrlLifetimeSeconds,
    ),
    expiresAt: new Date(Date.now() + signedUrlLifetimeSeconds * 1_000),
  };
}
