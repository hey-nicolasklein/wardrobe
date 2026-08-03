import { randomUUID } from 'node:crypto';

import {
  CreateBucketCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadBucketCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
  type S3ClientConfig,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { Database } from './database.js';
import type { ServiceConfig } from './config.js';

export type AssetPurpose =
  | 'source-photo'
  | 'generation-reference'
  | 'shelf-image-keyed'
  | 'shelf-image-transparent'
  | 'fixture';

export interface CreateUploadIntentInput {
  accountId: string;
  purpose: AssetPurpose;
  fileName: string;
  contentType: string;
  byteSize: number;
}

export interface UploadIntent {
  assetId: string;
  objectKey: string;
  uploadUrl: string;
  expiresAt: Date;
  headers: Record<string, string>;
}

export class AssetNotFoundError extends Error {}
export class AssetIntegrityError extends Error {}

export function sanitizeFileName(fileName: string): string {
  const sanitized = fileName
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
  return sanitized || 'upload';
}

export class PrivateAssetStore {
  readonly client: S3Client;

  constructor(
    private readonly database: Database,
    private readonly config: ServiceConfig,
  ) {
    // The generated 3.1101 S3 type omits the runtime-supported credential field
    // from S3ClientConfig, so retain a narrow local intersection until upstream
    // restores it.
    const clientConfig: S3ClientConfig & {
      credentials: { accessKeyId: string; secretAccessKey: string };
    } = {
      endpoint: config.S3_ENDPOINT,
      region: config.S3_REGION,
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.S3_ACCESS_KEY_ID,
        secretAccessKey: config.S3_SECRET_ACCESS_KEY,
      },
    };
    this.client = new S3Client(clientConfig);
  }

  async ensurePrivateBucket(): Promise<void> {
    try {
      await this.client.send(
        new HeadBucketCommand({ Bucket: this.config.S3_BUCKET }),
      );
    } catch (error) {
      const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata
        ?.httpStatusCode;
      if (status !== 404) throw error;
      await this.client.send(
        new CreateBucketCommand({ Bucket: this.config.S3_BUCKET }),
      );
    }
  }

  async createUploadIntent(
    input: CreateUploadIntentInput,
    expiresInSeconds = 10 * 60,
  ): Promise<UploadIntent> {
    const assetId = randomUUID();
    const objectKey = `accounts/${input.accountId}/assets/${assetId}/${sanitizeFileName(input.fileName)}`;

    await this.database.query(
      `INSERT INTO private_assets
        (id, account_id, object_key, purpose, content_type, declared_byte_size)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        assetId,
        input.accountId,
        objectKey,
        input.purpose,
        input.contentType,
        input.byteSize,
      ],
    );

    const command = new PutObjectCommand({
      Bucket: this.config.S3_BUCKET,
      Key: objectKey,
      ContentType: input.contentType,
      ContentLength: input.byteSize,
      Metadata: { accountId: input.accountId, assetId },
    });
    const uploadUrl = await getSignedUrl(this.client, command, {
      expiresIn: expiresInSeconds,
    });

    return {
      assetId,
      objectKey,
      uploadUrl,
      expiresAt: new Date(Date.now() + expiresInSeconds * 1_000),
      headers: { 'content-type': input.contentType },
    };
  }

  async completeUpload(
    accountId: string,
    assetId: string,
    dimensions?: { width: number; height: number },
  ): Promise<void> {
    const result = await this.database.query<{
      object_key: string;
      content_type: string;
      declared_byte_size: string;
    }>(
      `SELECT object_key, content_type, declared_byte_size
       FROM private_assets
       WHERE account_id = $1 AND id = $2 AND state = 'pending-upload'`,
      [accountId, assetId],
    );
    const asset = result.rows[0];
    if (!asset) throw new AssetNotFoundError('Asset upload intent not found');

    const object = await this.client.send(
      new HeadObjectCommand({
        Bucket: this.config.S3_BUCKET,
        Key: asset.object_key,
      }),
    );
    if (
      object.ContentLength !== Number(asset.declared_byte_size) ||
      object.ContentType !== asset.content_type
    ) {
      throw new AssetIntegrityError(
        'Stored object does not match the declared byte size and content type',
      );
    }

    await this.database.query(
      `UPDATE private_assets
       SET state = 'available', stored_byte_size = $3, pixel_width = $4,
           pixel_height = $5, available_at = now()
       WHERE account_id = $1 AND id = $2`,
      [
        accountId,
        assetId,
        object.ContentLength,
        dimensions?.width ?? null,
        dimensions?.height ?? null,
      ],
    );
  }

  async createDownloadUrl(
    accountId: string,
    assetId: string,
    expiresInSeconds = 5 * 60,
  ): Promise<string> {
    const result = await this.database.query<{ object_key: string }>(
      `SELECT object_key FROM private_assets
       WHERE account_id = $1 AND id = $2 AND state = 'available'`,
      [accountId, assetId],
    );
    const asset = result.rows[0];
    if (!asset) throw new AssetNotFoundError('Available asset not found');

    return getSignedUrl(
      this.client,
      new GetObjectCommand({
        Bucket: this.config.S3_BUCKET,
        Key: asset.object_key,
      }),
      { expiresIn: expiresInSeconds },
    );
  }

  async deleteAccountObjects(accountId: string): Promise<void> {
    const prefix = `accounts/${accountId}/`;
    let continuationToken: string | undefined;

    do {
      const page = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.config.S3_BUCKET,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }),
      );
      const objects = (page.Contents ?? [])
        .map(({ Key }) => Key)
        .filter((key): key is string => Boolean(key))
        .map((Key) => ({ Key }));
      if (objects.length > 0) {
        await this.client.send(
          new DeleteObjectsCommand({
            Bucket: this.config.S3_BUCKET,
            Delete: { Objects: objects, Quiet: true },
          }),
        );
      }
      continuationToken = page.NextContinuationToken;
    } while (continuationToken);
  }
}
