import {
  apiErrorSchema,
  createDownloadUrlResponseSchema,
  currentSessionResponseSchema,
  signInResponseSchema,
  wardrobeItemDetailResponseSchema,
  wardrobeItemResponseSchema,
  wardrobeItemsResponseSchema,
  type ApiError as ApiErrorPayload,
  type SignInResponse,
  type UpdateWardrobeItemRequest,
  type WardrobeItem,
  type WardrobeItemDetailResponse,
} from '@form/contracts';
import { fetch } from 'expo/fetch';

import {
  clearSessionToken,
  readSessionToken,
  requiresServerSignOut,
  sessionTransport,
  writeSessionToken,
} from './session-storage';

export class ApiClientError extends Error {
  constructor(readonly detail: ApiErrorPayload, readonly status: number) {
    super(detail.message);
    this.name = 'ApiClientError';
  }
}

function apiUrl(path: string): string {
  const baseUrl = process.env.EXPO_PUBLIC_API_URL;
  if (!baseUrl) throw new Error('EXPO_PUBLIC_API_URL is not configured.');
  return new URL(path, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`).toString();
}

async function request(path: string, options: RequestInit = {}): Promise<Response> {
  const headers = new Headers(options.headers);
  const token = await readSessionToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);
  let response: Response;
  try {
    response = await fetch(apiUrl(path), {
      ...options,
      credentials: 'include',
      headers,
    });
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') throw error;
    throw new ApiClientError(
      {
        category: 'offline',
        code: 'service-unreachable',
        message: 'The wardrobe service is unreachable. Check your connection and try again.',
        retryable: true,
      },
      0,
    );
  }
  if (response.ok) return response;

  const candidate = await response.json().catch(() => null);
  const parsed = apiErrorSchema.safeParse(
    typeof candidate === 'object' && candidate !== null && 'error' in candidate
      ? candidate.error
      : candidate,
  );
  throw new ApiClientError(
    parsed.success
      ? parsed.data
      : {
          category: 'internal',
          code: 'unexpected-api-response',
          message: 'The service returned an unexpected response.',
          retryable: response.status >= 500,
        },
    response.status,
  );
}

export const apiClient = {
  async signIn(email: string, password: string): Promise<SignInResponse['session']> {
    const response = await request('/v1/auth/sign-in', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, transport: sessionTransport }),
    });
    const result = signInResponseSchema.parse(await response.json());
    if (result.session.nativeToken) await writeSessionToken(result.session.nativeToken);
    return { ...result.session, nativeToken: null };
  },

  async restoreSession(signal?: AbortSignal): Promise<SignInResponse['session'] | null> {
    try {
      const response = await request('/v1/auth/session', { signal });
      return currentSessionResponseSchema.parse(await response.json()).session;
    } catch (error) {
      if (error instanceof ApiClientError && error.status === 401) {
        await clearSessionToken();
        return null;
      }
      throw error;
    }
  },

  async signOut(): Promise<void> {
    try {
      await request('/v1/auth/sign-out', { method: 'POST' });
    } catch (error) {
      if (requiresServerSignOut) throw error;
    } finally {
      await clearSessionToken();
    }
  },

  async listWardrobeItems(
    state: WardrobeItem['state'],
    signal?: AbortSignal,
  ): Promise<WardrobeItem[]> {
    const response = await request(`/v1/wardrobe-items?state=${state}`, { signal });
    return wardrobeItemsResponseSchema.parse(await response.json()).wardrobeItems;
  },

  async getWardrobeItem(
    wardrobeItemId: string,
    signal?: AbortSignal,
  ): Promise<WardrobeItemDetailResponse> {
    const response = await request(`/v1/wardrobe-items/${wardrobeItemId}`, { signal });
    return wardrobeItemDetailResponseSchema.parse(await response.json());
  },

  async updateWardrobeItem(
    wardrobeItemId: string,
    update: UpdateWardrobeItemRequest,
  ): Promise<WardrobeItem> {
    const response = await request(`/v1/wardrobe-items/${wardrobeItemId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(update),
    });
    return wardrobeItemResponseSchema.parse(await response.json()).wardrobeItem;
  },

  async createDownloadUrl(assetId: string): Promise<string> {
    const response = await request(`/v1/assets/${assetId}/download`);
    return createDownloadUrlResponseSchema.parse(await response.json()).downloadUrl;
  },

  request,
};
