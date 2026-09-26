import {
  createHmac,
  randomBytes,
  randomUUID,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';

import { createRemoteJWKSet, jwtVerify } from 'jose';

import { grantCredits, signupCredits } from './credits.js';
import type { Database } from './database.js';
import { withTransaction } from './database.js';

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
     WHERE email = $1 AND disabled_at IS NULL AND password_hash IS NOT NULL`,
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

export type IdentityProvider = 'apple' | 'google' | 'dev';

export type VerifiedIdentity = {
  provider: IdentityProvider;
  subject: string;
  email: string;
};

// Checks a provider ID token and returns who it belongs to, or null when the
// token is invalid, expired, or issued for another app.
export type IdentityTokenVerifier = (
  provider: 'apple' | 'google',
  idToken: string,
) => Promise<VerifiedIdentity | null>;

const providerKeys = {
  apple: {
    jwks: createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys')),
    issuer: ['https://appleid.apple.com'],
  },
  google: {
    jwks: createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs')),
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
  },
};

// `audiences` are the client IDs a token may be issued for: iOS bundle IDs for
// Apple, the OAuth client IDs (iOS and server) for Google.
export function createIdentityTokenVerifier(audiences: {
  apple: string[];
  google: string[];
}): IdentityTokenVerifier {
  return async (provider, idToken) => {
    if (audiences[provider].length === 0) return null;
    try {
      const { payload } = await jwtVerify(idToken, providerKeys[provider].jwks, {
        issuer: providerKeys[provider].issuer,
        audience: audiences[provider],
      });
      // Apple sends email_verified as a string, Google as a boolean.
      const verified = payload.email_verified === true || payload.email_verified === 'true';
      if (!payload.sub || typeof payload.email !== 'string' || !verified) return null;
      return { provider, subject: payload.sub, email: payload.email.trim().toLowerCase() };
    } catch {
      return null;
    }
  };
}

// Finds the account behind an identity or creates one. A verified email that
// already belongs to an account links the new identity to it, so Apple and
// Google sign-in with the same address land in the same wardrobe.
export async function signInWithIdentity(
  database: Database,
  identity: VerifiedIdentity,
): Promise<AuthenticatedAccount | null> {
  return withTransaction(database, async (client) => {
    const existing = await client.query<AuthenticatedAccount & { disabled: boolean }>(
      `SELECT account.id, account.email, account.disabled_at IS NOT NULL AS disabled
       FROM account_identities identity JOIN accounts account ON account.id = identity.account_id
       WHERE identity.provider = $1 AND identity.subject = $2`,
      [identity.provider, identity.subject],
    );
    if (existing.rows[0]) {
      const { disabled, ...account } = existing.rows[0];
      return disabled ? null : account;
    }

    const byEmail = await client.query<AuthenticatedAccount & { disabled: boolean }>(
      `SELECT id, email, disabled_at IS NOT NULL AS disabled FROM accounts WHERE email = $1 FOR UPDATE`,
      [identity.email],
    );
    let account: AuthenticatedAccount;
    if (byEmail.rows[0]) {
      const { disabled, ...found } = byEmail.rows[0];
      if (disabled) return null;
      account = found;
    } else {
      const created = await client.query<AuthenticatedAccount>(
        `INSERT INTO accounts (id, email, metered) VALUES ($1, $2, true) RETURNING id, email`,
        [randomUUID(), identity.email],
      );
      account = created.rows[0]!;
      await grantCredits(client, { accountId: account.id, amount: signupCredits, reason: 'signup' });
    }
    await client.query(
      `INSERT INTO account_identities (id, account_id, provider, subject, email)
       VALUES ($1, $2, $3, $4, $5)`,
      [randomUUID(), account.id, identity.provider, identity.subject, identity.email],
    );
    return account;
  });
}
