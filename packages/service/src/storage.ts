import {
  CreateBucketCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutBucketVersioningCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { ObjectStorageConfig } from './config.js';

export type PrivateObjectStorage = {
  bucket: string;
  client: S3Client;
  signingClient: S3Client;
};

export function createPrivateObjectStorage(config: ObjectStorageConfig): PrivateObjectStorage {
  const clientOptions = {
    endpoint: config.S3_ENDPOINT,
    region: config.S3_REGION,
    forcePathStyle: config.S3_FORCE_PATH_STYLE,
    credentials: {
      accessKeyId: config.S3_ACCESS_KEY_ID,
      secretAccessKey: config.S3_SECRET_ACCESS_KEY,
    },
  };
  return {
    bucket: config.S3_BUCKET,
    client: new S3Client(clientOptions),
    signingClient: new S3Client({ ...clientOptions, endpoint: config.S3_PUBLIC_ENDPOINT ?? config.S3_ENDPOINT }),
  };
}

export async function ensurePrivateBucket(storage: PrivateObjectStorage): Promise<void> {
  try {
    await storage.client.send(new HeadBucketCommand({ Bucket: storage.bucket }));
  } catch (error) {
    const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
    if (status !== 404 && (error as { name?: string }).name !== 'NotFound') throw error;
    await storage.client.send(new CreateBucketCommand({ Bucket: storage.bucket }));
  }

  await storage.client.send(
    new PutBucketVersioningCommand({
      Bucket: storage.bucket,
      VersioningConfiguration: { Status: 'Enabled' },
    }),
  );
}

export async function checkObjectStorage(storage: PrivateObjectStorage): Promise<void> {
  await storage.client.send(new HeadBucketCommand({ Bucket: storage.bucket }));
}

export async function createSignedUploadUrl(
  storage: PrivateObjectStorage,
  objectKey: string,
  contentType: string,
  byteSize: number,
  expiresInSeconds = 300,
): Promise<string> {
  return getSignedUrl(
    storage.signingClient,
    new PutObjectCommand({
      Bucket: storage.bucket,
      Key: objectKey,
      ContentType: contentType,
      ContentLength: byteSize,
    }),
    { expiresIn: expiresInSeconds },
  );
}

export async function createSignedDownloadUrl(
  storage: PrivateObjectStorage,
  objectKey: string,
  objectVersionId: string,
  expiresInSeconds = 300,
): Promise<string> {
  return getSignedUrl(
    storage.signingClient,
    new GetObjectCommand({
      Bucket: storage.bucket,
      Key: objectKey,
      VersionId: objectVersionId,
    }),
    { expiresIn: expiresInSeconds },
  );
}
