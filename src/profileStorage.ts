import type { FittingProfile, FittingProfileDraft } from './types';

const DATABASE = 'form-wardrobe';
const STORE = 'fitting-profile';
const VERSION = 1;

type StorageKey = 'draft' | 'profile';

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (!('indexedDB' in window)) {
      reject(new Error('This browser does not support durable draft storage.'));
      return;
    }
    const request = indexedDB.open(DATABASE, VERSION);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE)) request.result.createObjectStore(STORE);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Could not open draft storage.'));
    request.onblocked = () => reject(new Error('Draft storage is blocked by another FORM tab. Close it and retry.'));
  });
}

async function read<T>(key: StorageKey): Promise<T | null> {
  const database = await openDatabase();
  try {
    return await new Promise<T | null>((resolve, reject) => {
      const request = database.transaction(STORE, 'readonly').objectStore(STORE).get(key);
      request.onsuccess = () => resolve((request.result as T | undefined) ?? null);
      request.onerror = () => reject(request.error ?? new Error('Could not restore the saved draft.'));
    });
  } finally {
    database.close();
  }
}

async function write<T>(key: StorageKey, value: T | null): Promise<void> {
  const database = await openDatabase();
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = database.transaction(STORE, 'readwrite');
      if (value === null) transaction.objectStore(STORE).delete(key);
      else transaction.objectStore(STORE).put(value, key);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error ?? new Error('Could not save this draft.'));
      transaction.onabort = () => reject(transaction.error ?? new Error('Draft storage ran out of space.'));
    });
  } finally {
    database.close();
  }
}

export const loadFittingProfile = () => read<FittingProfile>('profile');
export const saveFittingProfile = (profile: FittingProfile | null) => write('profile', profile);
export const loadFittingDraft = () => read<FittingProfileDraft>('draft');
export const saveFittingDraft = (draft: FittingProfileDraft) => write('draft', draft);
export const clearFittingDraft = () => write('draft', null);
