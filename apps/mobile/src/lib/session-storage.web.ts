export const sessionTransport = 'cookie' as const;

export async function readSessionToken(): Promise<null> {
  return null;
}

export async function writeSessionToken(_token: string): Promise<void> {
  // Browser credentials live only in the server-issued HTTP-only cookie.
}

export async function clearSessionToken(): Promise<void> {
  // Signing out invalidates and expires the server-issued cookie.
}
