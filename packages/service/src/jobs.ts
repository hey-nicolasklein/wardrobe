import { randomUUID } from 'node:crypto';

import type { Database, DatabaseClient } from './database.js';
import { withTransaction } from './database.js';

export type RemoteImageJobKind = 'detect-source-photo' | 'generate-shelf-image';
export type RemoteImageJob = {
  id: string;
  accountId: string;
  wardrobeItemId: string | null;
  generationAttemptId: string | null;
  kind: RemoteImageJobKind;
  payload: unknown;
  attempts: number;
  maxAttempts: number;
  leaseExpiresAt: Date;
};

type JobRow = {
  id: string;
  account_id: string;
  wardrobe_item_id: string | null;
  generation_attempt_id: string | null;
  kind: RemoteImageJobKind;
  payload: unknown;
  attempts: number;
  max_attempts: number;
  lease_expires_at: Date;
};

function mapJob(row: JobRow): RemoteImageJob {
  return {
    id: row.id,
    accountId: row.account_id,
    wardrobeItemId: row.wardrobe_item_id,
    generationAttemptId: row.generation_attempt_id,
    kind: row.kind,
    payload: row.payload,
    attempts: row.attempts,
    maxAttempts: row.max_attempts,
    leaseExpiresAt: row.lease_expires_at,
  };
}

export type EnqueueJobInput = {
  accountId: string;
  wardrobeItemId?: string;
  generationAttemptId?: string;
  kind: RemoteImageJobKind;
  payload: unknown;
  idempotencyKey: string;
  availableAt?: Date;
};

export async function enqueueJob(
  database: Database | DatabaseClient,
  input: EnqueueJobInput,
): Promise<string> {
  const id = randomUUID();
  const result = await database.query<{ id: string }>(
    `INSERT INTO remote_image_jobs (
       id, account_id, wardrobe_item_id, generation_attempt_id, kind, payload,
       idempotency_key, available_at
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (account_id, idempotency_key)
     DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
     RETURNING id`,
    [
      id,
      input.accountId,
      input.wardrobeItemId ?? null,
      input.generationAttemptId ?? null,
      input.kind,
      JSON.stringify(input.payload),
      input.idempotencyKey,
      input.availableAt ?? new Date(),
    ],
  );
  return result.rows[0]!.id;
}

export type ClaimJobsOptions = {
  workerId: string;
  limit: number;
  perAccountLimit: number;
  leaseSeconds: number;
};

export async function claimJobs(
  database: Database,
  options: ClaimJobsOptions,
): Promise<RemoteImageJob[]> {
  return withTransaction(database, async (client) => {
    const claimed: RemoteImageJob[] = [];
    for (let index = 0; index < options.limit; index += 1) {
      const result = await client.query<JobRow>(
        `WITH candidate AS (
         SELECT jobs.id
         FROM remote_image_jobs jobs
         WHERE jobs.state = 'queued'
           AND jobs.available_at <= now()
           AND (SELECT count(*) FROM remote_image_jobs active
                WHERE active.state = 'leased' AND active.lease_expires_at > now()) < $2
           AND (SELECT count(*) FROM remote_image_jobs active
                WHERE active.account_id = jobs.account_id
                  AND active.state = 'leased' AND active.lease_expires_at > now()) < $1
           AND pg_try_advisory_xact_lock(hashtextextended(jobs.account_id::text, 0))
         ORDER BY jobs.available_at, jobs.created_at
         FOR UPDATE OF jobs SKIP LOCKED
         LIMIT 1
       )
       UPDATE remote_image_jobs jobs
       SET state = 'leased',
           attempts = jobs.attempts + 1,
           lease_owner = $3,
           lease_expires_at = now() + ($4 * interval '1 second'),
           updated_at = now()
       FROM candidate
       WHERE jobs.id = candidate.id
       RETURNING jobs.id, jobs.account_id, jobs.wardrobe_item_id,
         jobs.generation_attempt_id, jobs.kind, jobs.payload, jobs.attempts,
         jobs.max_attempts, jobs.lease_expires_at`,
        [options.perAccountLimit, options.limit, options.workerId, options.leaseSeconds],
      );
      const row = result.rows[0];
      if (!row) break;
      claimed.push(mapJob(row));
    }
    return claimed;
  });
}

export async function completeJob(
  database: Database,
  jobId: string,
  workerId: string,
): Promise<boolean> {
  const result = await database.query(
    `UPDATE remote_image_jobs
     SET state = 'succeeded', lease_owner = NULL, lease_expires_at = NULL,
         finished_at = now(), updated_at = now()
     WHERE id = $1 AND state = 'leased' AND lease_owner = $2`,
    [jobId, workerId],
  );
  return result.rowCount === 1;
}

export type FailJobOptions = {
  retryable: boolean;
  category: string;
  detail: string;
  retryDelaySeconds?: number;
};

export async function failJob(
  database: Database,
  jobId: string,
  workerId: string,
  failure: FailJobOptions,
): Promise<'retried' | 'failed' | 'not-owned'> {
  const result = await database.query<{ state: 'queued' | 'failed' }>(
    `UPDATE remote_image_jobs
     SET state = CASE WHEN $3 AND attempts < max_attempts THEN 'queued' ELSE 'failed' END,
         available_at = CASE WHEN $3 AND attempts < max_attempts
           THEN now() + ($6 * interval '1 second') ELSE available_at END,
         lease_owner = NULL,
         lease_expires_at = NULL,
         last_error_category = $4,
         last_error_detail = $5,
         finished_at = CASE WHEN $3 AND attempts < max_attempts THEN NULL ELSE now() END,
         updated_at = now()
     WHERE id = $1 AND state = 'leased' AND lease_owner = $2
     RETURNING state`,
    [jobId, workerId, failure.retryable, failure.category, failure.detail, failure.retryDelaySeconds ?? 5],
  );
  const state = result.rows[0]?.state;
  if (!state) return 'not-owned';
  return state === 'queued' ? 'retried' : 'failed';
}

export async function recoverExpiredLeases(database: Database): Promise<number> {
  const result = await database.query(
    `UPDATE remote_image_jobs
     SET state = CASE WHEN attempts < max_attempts THEN 'queued' ELSE 'failed' END,
         available_at = CASE WHEN attempts < max_attempts THEN now() ELSE available_at END,
         lease_owner = NULL,
         lease_expires_at = NULL,
         last_error_category = 'abandoned-lease',
         last_error_detail = 'The worker lease expired before completion.',
         finished_at = CASE WHEN attempts < max_attempts THEN NULL ELSE now() END,
         updated_at = now()
     WHERE state = 'leased' AND lease_expires_at <= now()`,
  );
  return result.rowCount ?? 0;
}
