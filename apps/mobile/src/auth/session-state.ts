import type { SignInResponse } from '@form/contracts';

export type Session = SignInResponse['session'];

export type SessionState =
  | { status: 'restoring'; session: null }
  | { status: 'restore-error'; session: null }
  | { status: 'signed-out'; session: null }
  | { status: 'signed-in'; session: Session; signOutError: string | null };

export type SessionAction =
  | { type: 'restore-started' }
  | { type: 'restore-failed' }
  | { type: 'signed-in'; session: Session }
  | { type: 'sign-out-failed'; message: string }
  | { type: 'signed-out' };

export const initialSessionState: SessionState = { status: 'restoring', session: null };

export function sessionReducer(state: SessionState, action: SessionAction): SessionState {
  switch (action.type) {
    case 'restore-started':
      return { status: 'restoring', session: null };
    case 'restore-failed':
      return { status: 'restore-error', session: null };
    case 'signed-in':
      return { status: 'signed-in', session: action.session, signOutError: null };
    case 'sign-out-failed':
      return state.status === 'signed-in'
        ? { ...state, signOutError: action.message }
        : state;
    case 'signed-out':
      return { status: 'signed-out', session: null };
  }
}
