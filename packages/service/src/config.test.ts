import assert from 'node:assert/strict';
import test from 'node:test';

import { objectStorageConfigSchema } from './config.js';

test('local S3 configuration defaults to path-style addressing', () => {
  const config = objectStorageConfigSchema.parse({
    S3_ENDPOINT: 'http://localhost:9000',
    S3_REGION: 'us-east-1',
    S3_BUCKET: 'form-private-media',
    S3_ACCESS_KEY_ID: 'form',
    S3_SECRET_ACCESS_KEY: 'secret',
  });

  assert.equal(config.S3_FORCE_PATH_STYLE, true);
});

test('explicit false path-style configuration is parsed as a boolean', () => {
  const config = objectStorageConfigSchema.parse({
    S3_ENDPOINT: 'https://storage.example.test',
    S3_REGION: 'eu-west-1',
    S3_BUCKET: 'form-private-media',
    S3_ACCESS_KEY_ID: 'form',
    S3_SECRET_ACCESS_KEY: 'secret',
    S3_FORCE_PATH_STYLE: 'false',
  });

  assert.equal(config.S3_FORCE_PATH_STYLE, false);
});

test('production configuration can sign browser URLs through a public endpoint', () => {
  const config = objectStorageConfigSchema.parse({
    S3_ENDPOINT: 'http://object-storage:9000',
    S3_PUBLIC_ENDPOINT: 'https://wardrobe.example.ts.net',
    S3_REGION: 'us-east-1',
    S3_BUCKET: 'form-private-media',
    S3_ACCESS_KEY_ID: 'form',
    S3_SECRET_ACCESS_KEY: 'secret',
  });

  assert.equal(config.S3_PUBLIC_ENDPOINT, 'https://wardrobe.example.ts.net');
});
