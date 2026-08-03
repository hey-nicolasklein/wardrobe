import {
  createHmac,
  randomBytes,
  randomUUID,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';

import type { Database } from './database.js';

const scrypt = promisify(scryptCallback);
const scryptKeyLength = 64;
const sessionTokenBytes = 32;

export type AuthenticatedAccount = {
  id: string;
  email: string;
};

export type SessionRecord = AuthenticatedAccount & {
  expiresAt: Date;
};

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const derivedKey = (await scrypt(password, salt, scryptKeyLength)) as Buffer;
  return `scrypt$${salt.toString('base64url')}$${derivedKey.toString('base64url')}`;
}

export async function verifyPassword(password: string, encodedHash: string): Promise<boolean> {
  const [algorithm, encodedSalt, encodedKey] = encodedHash.split('$');
  if (algorithm !== 'scrypt' || !encodedSalt || !encodedKey) return false;

  try {
    const salt = Buffer.from(encodedSalt, 'base64url');
    const expected = Buffer.from(encodedKey, 'base64url');
    const actual = (await scrypt(password, salt, expected.byteLength)) as Buffer;
    return expected.byteLength > 0 && timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

export async function createAccount(
  database: Database,
  input: { email: string; password: string },
): Promise<AuthenticatedAccount> {
  const email = input.email.trim().toLowerCase();
  const passwordHash = await hashPassword(input.password);
  const result = await database.query<AuthenticatedAccount>(
    `INSERT INTO accounts (id, email, password_hash)
     VALUES ($1, $2, $3)
     RETURNING id, email`,
    [randomUUID(), email, passwordHash],
  );
  return result.rows[0]!;
}

export async function verifyCredentials(
  database: Database,
  input: { email: string; password: string },
): Promise<AuthenticatedAccount | null> {
  const result = await database.query<AuthenticatedAccount & { password_hash: string }>(
    `SELECT id, email, password_hash
     FROM accounts
     WHERE email = $1 AND disabled_at IS NULL`,
    [input.email.trim().toLowerCase()],
  );
  const account = result.rows[0];
  if (!account || !(await verifyPassword(input.password, account.password_hash))) return null;
  return { id: account.id, email: account.email };
}

function hashSessionToken(token: string, secret: string): string {
  return createHmac('sha256', secret).update(token).digest('base64url');
}

export async function createSession(
  database: Database,
  account: AuthenticatedAccount,
  secret: string,
  lifetimeSeconds: number,
): Promise<{ token: string; session: SessionRecord }> {
  const token = randomBytes(sessionTokenBytes).toString('base64url');
  const expiresAt = new Date(Date.now() + lifetimeSeconds * 1_000);
  await database.query(
    `INSERT INTO sessions (id, account_id, token_hash, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [randomUUID(), account.id, hashSessionToken(token, secret), expiresAt],
  );
  return { token, session: { ...account, expiresAt } };
}

export async function authenticateSession(
  database: Database,
  token: string,
  secret: string,
): Promise<SessionRecord | null> {
  const result = await database.query<{
    id: string;
    account_id: string;
    email: string;
    expires_at: Date;
  }>(
    `UPDATE sessions AS session
     SET last_used_at = now()
     FROM accounts AS account
     WHERE session.token_hash = $1
       AND session.account_id = account.id
       AND session.expires_at > now()
       AND account.disabled_at IS NULL
     RETURNING session.id, account.id AS account_id, account.email, session.expires_at`,
    [hashSessionToken(token, secret)],
  );
  const session = result.rows[0];
  return session
    ? { id: session.account_id, email: session.email, expiresAt: session.expires_at }
    : null;
}

export async function revokeSession(
  database: Database,
  token: string,
  secret: string,
): Promise<void> {
  await database.query('DELETE FROM sessions WHERE token_hash = $1', [
    hashSessionToken(token, secret),
  ]);
}
