import { randomUUID } from 'node:crypto';

import type { Database, DatabaseClient } from './database.js';
import type { RemoteImageJobKind } from './jobs.js';

type Queryable = Pick<Database, 'query'> | Pick<DatabaseClient, 'query'>;

// Credits charged when a job is enqueued. Detection is free so onboarding a
// photo never blocks on the balance.
export const jobCreditCost: Record<RemoteImageJobKind, number> = {
  'detect-source-photo': 0,
  'generate-shelf-image': 1,
  'generate-character-sheet': 2,
  'generate-look': 2,
};

export const signupCredits = 40;

// Queued plus running jobs a metered account may have at once.
export const maxActiveJobsPerAccount = 5;

export class InsufficientCreditsError extends Error {
  constructor(
    readonly balance: number,
    readonly required: number,
  ) {
    super('Not enough credits for this generation.');
  }
}

export class ActiveJobLimitError extends Error {
  constructor() {
    super('Too many generations are already running.');
  }
}

export async function creditBalance(database: Queryable, accountId: string): Promise<number> {
  const result = await database.query<{ balance: string }>(
    'SELECT COALESCE(SUM(delta), 0) AS balance FROM credit_ledger WHERE account_id = $1',
    [accountId],
  );
  return Number(result.rows[0]!.balance);
}

export async function creditSummary(
  database: Queryable,
  accountId: string,
): Promise<{ metered: boolean; balance: number }> {
  const account = await database.query<{ metered: boolean }>(
    'SELECT metered FROM accounts WHERE id = $1',
    [accountId],
  );
  return {
    metered: account.rows[0]?.metered ?? false,
    balance: await creditBalance(database, accountId),
  };
}

export async function grantCredits(
  database: Queryable,
  input: { accountId: string; amount: number; reason: 'signup' | 'grant'; note?: string },
): Promise<void> {
  await database.query(
    `INSERT INTO credit_ledger (id, account_id, delta, reason, note) VALUES ($1, $2, $3, $4, $5)`,
    [randomUUID(), input.accountId, input.amount, input.reason, input.note ?? null],
  );
}

// Runs inside the enqueue transaction, right after a new job row was inserted.
// Locks the account row so concurrent enqueues cannot overdraw the balance.
// Throwing rolls the job insert back.
export async function chargeJob(
  client: Queryable,
  input: { accountId: string; jobId: string; kind: RemoteImageJobKind },
): Promise<void> {
  const account = await client.query<{ metered: boolean }>(
    'SELECT metered FROM accounts WHERE id = $1 FOR UPDATE',
    [input.accountId],
  );
  if (!account.rows[0]?.metered) return;

  const active = await client.query<{ count: string }>(
    `SELECT count(*) FROM remote_image_jobs
     WHERE account_id = $1 AND state IN ('queued', 'leased') AND id <> $2`,
    [input.accountId, input.jobId],
  );
  if (Number(active.rows[0]!.count) >= maxActiveJobsPerAccount) throw new ActiveJobLimitError();

  const cost = jobCreditCost[input.kind];
  if (cost === 0) return;
  const balance = await creditBalance(client, input.accountId);
  if (balance < cost) throw new InsufficientCreditsError(balance, cost);
  await client.query(
    `INSERT INTO credit_ledger (id, account_id, delta, reason, job_id) VALUES ($1, $2, $3, 'job', $4)`,
    [randomUUID(), input.accountId, -cost, input.jobId],
  );
}

// Returns the charge of jobs that ended in `failed`. Safe to call repeatedly.
export async function refundFailedJobs(database: Queryable, jobIds: string[]): Promise<void> {
  if (jobIds.length === 0) return;
  await database.query(
    `INSERT INTO credit_ledger (id, account_id, delta, reason, job_id)
     SELECT gen_random_uuid(), charge.account_id, -charge.delta, 'refund', charge.job_id
     FROM credit_ledger charge
     JOIN remote_image_jobs job ON job.id = charge.job_id AND job.state = 'failed'
     WHERE charge.reason = 'job' AND charge.job_id = ANY($1::uuid[])
     ON CONFLICT DO NOTHING`,
    [jobIds],
  );
}
