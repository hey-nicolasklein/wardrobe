import * as SecureStore from 'expo-secure-store';

const sessionTokenKey = 'form.native-session-token';

export const sessionTransport = 'token' as const;

export function readSessionToken(): Promise<string | null> {
  return SecureStore.getItemAsync(sessionTokenKey);
}

export async function writeSessionToken(token: string): Promise<void> {
  await SecureStore.setItemAsync(sessionTokenKey, token, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED,
  });
}

export function clearSessionToken(): Promise<void> {
  return SecureStore.deleteItemAsync(sessionTokenKey);
}
