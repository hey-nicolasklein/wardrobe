import { randomUUID } from 'node:crypto';

import type { Database } from './database.js';

export type RemoteImageJobKind =
  | 'detect-source-photo'
  | 'generate-shelf-image';
export type RemoteImageJobState =
  | 'queued'
  | 'processing'
  | 'succeeded'
  | 'failed';

export interface RemoteImageJob<Payload = unknown> {
  id: string;
  accountId: string;
  kind: RemoteImageJobKind;
  payload: Payload;
  state: RemoteImageJobState;
  attemptCount: number;
  maxAttempts: number;
  leaseOwner: string | null;
  leaseExpiresAt: Date | null;
}

export type JobFailureCategory =
  | 'connection'
  | 'timeout'
  | 'rate-limit'
  | 'provider-server'
  | 'validation'
  | 'conversion'
  | 'moderation'
  | 'authentication'
  | 'quota'
  | 'accounting'
  | 'chroma-validation'
  | 'internal';

const transientCategories = new Set<JobFailureCategory>([
  'connection',
  'timeout',
  'rate-limit',
  'provider-server',
]);

export function shouldRetryJob(
  category: JobFailureCategory,
  attemptCount: number,
  maxAttempts: number,
): boolean {
  return transientCategories.has(category) && attemptCount < maxAttempts;
}

function rowToJob(row: Record<string, unknown>): RemoteImageJob {
  return {
    id: String(row.id),
    accountId: String(row.account_id),
    kind: row.kind as RemoteImageJobKind,
    payload: row.payload,
    state: row.state as RemoteImageJobState,
    attemptCount: Number(row.attempt_count),
    maxAttempts: Number(row.max_attempts),
    leaseOwner: row.lease_owner ? String(row.lease_owner) : null,
    leaseExpiresAt: row.lease_expires_at
      ? new Date(String(row.lease_expires_at))
      : null,
  };
}

export class DurableJobQueue {
  constructor(private readonly database: Database) {}

  async enqueue<Payload>(input: {
    accountId: string;
    kind: RemoteImageJobKind;
    payload: Payload;
    idempotencyKey: string;
  }): Promise<RemoteImageJob<Payload>> {
    const result = await this.database.query(
      `INSERT INTO remote_image_jobs
        (id, account_id, kind, payload, idempotency_key)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (account_id, idempotency_key)
       DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
       RETURNING *`,
      [
        randomUUID(),
        input.accountId,
        input.kind,
        JSON.stringify(input.payload),
        input.idempotencyKey,
      ],
    );
    return rowToJob(result.rows[0]!) as RemoteImageJob<Payload>;
  }

  async claim(input: {
    workerId: string;
    kinds: RemoteImageJobKind[];
    leaseSeconds: number;
    perAccountConcurrency: number;
  }): Promise<RemoteImageJob | null> {
    if (input.kinds.length === 0) return null;

    const result = await this.database.query(
      `WITH candidate AS (
         SELECT job.id
         FROM remote_image_jobs job
         WHERE job.state = 'queued'
           AND job.available_at <= now()
           AND job.kind = ANY($1::text[])
           AND (
             SELECT count(*)
             FROM remote_image_jobs active
             WHERE active.account_id = job.account_id
               AND active.state = 'processing'
               AND active.lease_expires_at > now()
           ) < $2
         ORDER BY job.available_at, job.created_at
         FOR UPDATE SKIP LOCKED
         LIMIT 1
       )
       UPDATE remote_image_jobs job
       SET state = 'processing', attempt_count = attempt_count + 1,
           lease_owner = $3,
           lease_expires_at = now() + ($4 * interval '1 second'),
           updated_at = now()
       FROM candidate
       WHERE job.id = candidate.id
       RETURNING job.*`,
      [
        input.kinds,
        input.perAccountConcurrency,
        input.workerId,
        input.leaseSeconds,
      ],
    );
    return result.rows[0] ? rowToJob(result.rows[0]) : null;
  }

  async heartbeat(
    jobId: string,
    workerId: string,
    leaseSeconds: number,
  ): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE remote_image_jobs
       SET lease_expires_at = now() + ($3 * interval '1 second'), updated_at = now()
       WHERE id = $1 AND state = 'processing' AND lease_owner = $2`,
      [jobId, workerId, leaseSeconds],
    );
    return result.rowCount === 1;
  }

  async succeed(jobId: string, workerId: string, result: unknown): Promise<void> {
    const update = await this.database.query(
      `UPDATE remote_image_jobs
       SET state = 'succeeded', result = $3, lease_owner = NULL,
           lease_expires_at = NULL, completed_at = now(), updated_at = now()
       WHERE id = $1 AND state = 'processing' AND lease_owner = $2`,
      [jobId, workerId, JSON.stringify(result)],
    );
    if (update.rowCount !== 1) throw new Error('Job lease was lost before success');
  }

  async fail(input: {
    job: RemoteImageJob;
    workerId: string;
    category: JobFailureCategory;
    message: string;
    retryDelaySeconds?: number;
  }): Promise<'queued' | 'failed'> {
    const retry = shouldRetryJob(
      input.category,
      input.job.attemptCount,
      input.job.maxAttempts,
    );
    const nextState = retry ? 'queued' : 'failed';
    const update = await this.database.query(
      `UPDATE remote_image_jobs
       SET state = $3, lease_owner = NULL, lease_expires_at = NULL,
           available_at = CASE WHEN $3 = 'queued'
             THEN now() + ($6 * interval '1 second') ELSE available_at END,
           completed_at = CASE WHEN $3 = 'failed' THEN now() ELSE NULL END,
           last_error_category = $4, last_error_message = $5, updated_at = now()
       WHERE id = $1 AND state = 'processing' AND lease_owner = $2`,
      [
        input.job.id,
        input.workerId,
        nextState,
        input.category,
        input.message.slice(0, 2_000),
        input.retryDelaySeconds ?? 5,
      ],
    );
    if (update.rowCount !== 1) throw new Error('Job lease was lost before failure');
    return nextState;
  }

  async recoverExpiredLeases(): Promise<number> {
    const retried = await this.database.query(
      `UPDATE remote_image_jobs
       SET state = 'queued', lease_owner = NULL, lease_expires_at = NULL,
           available_at = now(), updated_at = now(),
           last_error_category = 'connection',
           last_error_message = 'Worker lease expired; job recovered'
       WHERE state = 'processing' AND lease_expires_at <= now()
         AND attempt_count < max_attempts`,
    );
    const failed = await this.database.query(
      `UPDATE remote_image_jobs
       SET state = 'failed', lease_owner = NULL, lease_expires_at = NULL,
           completed_at = now(), updated_at = now(),
           last_error_category = 'connection',
           last_error_message = 'Worker lease expired after the final attempt'
       WHERE state = 'processing' AND lease_expires_at <= now()
         AND attempt_count >= max_attempts`,
    );
    return (retried.rowCount ?? 0) + (failed.rowCount ?? 0);
  }
}

export class JobExecutionError extends Error {
  constructor(
    readonly category: JobFailureCategory,
    message: string,
  ) {
    super(message);
  }
}

export type RemoteImageJobHandler = (
  job: RemoteImageJob,
  signal: AbortSignal,
) => Promise<unknown>;

export interface QueueWorkerOptions {
  queue: DurableJobQueue;
  workerId: string;
  handlers: Partial<Record<RemoteImageJobKind, RemoteImageJobHandler>>;
  globalConcurrency: number;
  perAccountConcurrency: number;
  leaseSeconds?: number;
  pollMilliseconds?: number;
  signal: AbortSignal;
}

async function delay(milliseconds: number, signal: AbortSignal): Promise<void> {
  await new Promise<void>((resolve) => {
    if (signal.aborted) return resolve();
    const finish = (): void => {
      clearTimeout(timer);
      signal.removeEventListener('abort', finish);
      resolve();
    };
    const timer = setTimeout(finish, milliseconds);
    signal.addEventListener('abort', finish, { once: true });
  });
}

export async function runQueueWorker(options: QueueWorkerOptions): Promise<void> {
  const kinds = Object.keys(options.handlers) as RemoteImageJobKind[];
  const leaseSeconds = options.leaseSeconds ?? 60;
  const pollMilliseconds = options.pollMilliseconds ?? 1_000;

  async function runLane(lane: number): Promise<void> {
    while (!options.signal.aborted) {
      if (lane === 0) await options.queue.recoverExpiredLeases();

      const job = await options.queue.claim({
        workerId: `${options.workerId}:${lane}`,
        kinds,
        leaseSeconds,
        perAccountConcurrency: options.perAccountConcurrency,
      });
      if (!job) {
        await delay(pollMilliseconds, options.signal);
        continue;
      }

      const handler = options.handlers[job.kind];
      if (!handler) throw new Error(`No handler registered for ${job.kind}`);
      const laneWorkerId = `${options.workerId}:${lane}`;
      const heartbeat = setInterval(() => {
        void options.queue
          .heartbeat(job.id, laneWorkerId, leaseSeconds)
          .catch(() => undefined);
      }, Math.max(1_000, Math.floor((leaseSeconds * 1_000) / 3)));

      try {
        const result = await handler(job, options.signal);
        await options.queue.succeed(job.id, laneWorkerId, result);
      } catch (error) {
        const failure =
          error instanceof JobExecutionError
            ? error
            : new JobExecutionError(
                'internal',
                error instanceof Error ? error.message : String(error),
              );
        await options.queue.fail({
          job,
          workerId: laneWorkerId,
          category: failure.category,
          message: failure.message,
        });
      } finally {
        clearInterval(heartbeat);
      }
    }
  }

  await Promise.all(
    Array.from({ length: options.globalConcurrency }, (_, lane) => runLane(lane)),
  );
}
