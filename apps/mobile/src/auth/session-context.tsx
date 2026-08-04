import { createContext, type PropsWithChildren, use, useCallback, useEffect, useReducer } from 'react';

import { apiClient } from '@/lib/api-client';

import {
  initialSessionState,
  sessionReducer,
  type Session,
  type SessionState,
} from './session-state';

type SessionContextValue = SessionState & {
  restore: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: PropsWithChildren) {
  const [state, dispatch] = useReducer(sessionReducer, initialSessionState);

  const restore = useCallback(async (signal?: AbortSignal) => {
    dispatch({ type: 'restore-started' });
    try {
      const session = await apiClient.restoreSession(signal);
      dispatch(session ? { type: 'signed-in', session } : { type: 'signed-out' });
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') return;
      dispatch({ type: 'restore-failed' });
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void restore(controller.signal);
    return () => controller.abort();
  }, [restore]);

  const signIn = useCallback(async (email: string, password: string) => {
    const session = await apiClient.signIn(email, password);
    dispatch({ type: 'signed-in', session });
  }, []);

  const signOut = useCallback(async () => {
    try {
      await apiClient.signOut();
      dispatch({ type: 'signed-out' });
    } catch {
      dispatch({
        type: 'sign-out-failed',
        message: 'Couldn’t sign out. Your session is still active. Check your connection and try again.',
      });
    }
  }, []);

  return (
    <SessionContext.Provider value={{ ...state, restore, signIn, signOut }}>
      {children}
    </SessionContext.Provider>
  );
}

export function useSession(): SessionContextValue {
  const context = use(SessionContext);
  if (!context) throw new Error('useSession must be used inside SessionProvider.');
  return context;
}

export type { Session };
