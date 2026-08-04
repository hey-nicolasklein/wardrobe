import assert from 'node:assert/strict';
import test from 'node:test';

import { initialSessionState, sessionReducer, type Session } from './session-state';

const session: Session = {
  accountId: '00000000-0000-4000-8000-000000000001',
  email: 'owner@example.com',
  expiresAt: '2026-09-01T12:00:00.000Z',
  nativeToken: null,
};

test('restored credentials enter the authenticated shell', () => {
  assert.deepEqual(sessionReducer(initialSessionState, { type: 'signed-in', session }), {
    status: 'signed-in',
    session,
    signOutError: null,
  });
});

test('an invalid or revoked credential reaches sign in', () => {
  assert.deepEqual(sessionReducer(initialSessionState, { type: 'signed-out' }), {
    status: 'signed-out',
    session: null,
  });
});

test('a failed restoration is distinct from an unauthenticated session', () => {
  assert.deepEqual(sessionReducer(initialSessionState, { type: 'restore-failed' }), {
    status: 'restore-error',
    session: null,
  });
});

test('a failed browser sign-out keeps the active session and exposes an error', () => {
  const signedIn = sessionReducer(initialSessionState, { type: 'signed-in', session });

  assert.deepEqual(
    sessionReducer(signedIn, {
      type: 'sign-out-failed',
      message: 'Your session is still active.',
    }),
    {
      status: 'signed-in',
      session,
      signOutError: 'Your session is still active.',
    },
  );
});
