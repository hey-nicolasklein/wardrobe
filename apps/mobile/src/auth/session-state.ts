import type { SignInResponse } from '@form/contracts';

export type Session = SignInResponse['session'];

export type SessionState =
  | { status: 'restoring'; session: null }
  | { status: 'restore-error'; session: null }
  | { status: 'signed-out'; session: null }
  | { status: 'signed-in'; session: Session };

export type SessionAction =
  | { type: 'restore-started' }
  | { type: 'restore-failed' }
  | { type: 'signed-in'; session: Session }
  | { type: 'signed-out' };

export const initialSessionState: SessionState = { status: 'restoring', session: null };

export function sessionReducer(_state: SessionState, action: SessionAction): SessionState {
  switch (action.type) {
    case 'restore-started':
      return { status: 'restoring', session: null };
    case 'restore-failed':
      return { status: 'restore-error', session: null };
    case 'signed-in':
      return { status: 'signed-in', session: action.session };
    case 'signed-out':
      return { status: 'signed-out', session: null };
  }
}
