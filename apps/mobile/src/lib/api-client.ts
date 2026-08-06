import {
  apiErrorSchema,
  createDownloadUrlResponseSchema,
  createUploadIntentResponseSchema,
  completeSourceUploadResponseSchema,
  detectionProposalsResponseSchema,
  enqueueDetectionResponseSchema,
  enqueueGenerationResponseSchema,
  keepShelfImageResponseSchema,
  permanentlyDeleteWardrobeItemResponseSchema,
  currentSessionResponseSchema,
  signInResponseSchema,
  wardrobeItemDetailResponseSchema,
  wardrobeItemResponseSchema,
  wardrobeItemsResponseSchema,
  type ApiError as ApiErrorPayload,
  type SignInResponse,
  type CreateUploadIntentRequest,
  type DetectionProposalsResponse,
  type ItemMetadata,
  type ItemState,
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

  async uploadSourcePhoto(input: Omit<CreateUploadIntentRequest, 'byteSize'> & { uri: string }) {
    const source = await fetch(input.uri);
    if (!source.ok) throw new Error('The selected photo could not be opened.');
    const blob = await source.blob();
    const intentResponse = await request('/v1/source-photos/upload-intents', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        fileName: input.fileName,
        contentType: input.contentType,
        byteSize: blob.size,
      }),
    });
    const intent = createUploadIntentResponseSchema.parse(await intentResponse.json());
    let upload: Response;
    try {
      upload = await fetch(intent.uploadUrl, {
        method: 'PUT',
        headers: intent.headers,
        body: blob,
      });
    } catch {
      throw new ApiClientError(
        {
          category: 'offline',
          code: 'upload-unreachable',
          message: 'The photo upload was interrupted. Check your connection and try again.',
          retryable: true,
        },
        0,
      );
    }
    if (!upload.ok) throw new Error('The private photo upload could not be completed.');
    const completion = await request('/v1/source-photos/complete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ assetId: intent.assetId, idempotencyKey: idempotencyKey('source') }),
    });
    return completeSourceUploadResponseSchema.parse(await completion.json());
  },

  async enqueueDetection(sourcePhotoId: string) {
    const response = await request(`/v1/source-photos/${sourcePhotoId}/detections`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idempotencyKey: idempotencyKey('detection') }),
    });
    return enqueueDetectionResponseSchema.parse(await response.json());
  },

  async getDetections(sourcePhotoId: string): Promise<DetectionProposalsResponse> {
    const response = await request(`/v1/source-photos/${sourcePhotoId}/detections`);
    return detectionProposalsResponseSchema.parse(await response.json());
  },

  async createWardrobeItem(input: {
    detectionProposalId: string;
    state: Exclude<ItemState, 'archived'>;
    metadata: ItemMetadata;
  }): Promise<WardrobeItem> {
    const response = await request('/v1/wardrobe-items', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...input, idempotencyKey: idempotencyKey('item') }),
    });
    return wardrobeItemResponseSchema.parse(await response.json()).wardrobeItem;
  },

  async enqueueGeneration(wardrobeItemId: string) {
    const response = await request('/v1/generations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        wardrobeItemId,
        quality: 'low',
        size: '816x816',
        idempotencyKey: idempotencyKey('generation'),
      }),
    });
    return enqueueGenerationResponseSchema.parse(await response.json());
  },

  async keepShelfImage(
    wardrobeItemId: string,
    generationAttemptId: string,
    expectedRecordVersion: number,
  ) {
    const response = await request(
      `/v1/wardrobe-items/${wardrobeItemId}/shelf-image-versions/keep`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          generationAttemptId,
          expectedRecordVersion,
          idempotencyKey: idempotencyKey('keep'),
        }),
      },
    );
    return keepShelfImageResponseSchema.parse(await response.json());
  },

  async rejectShelfImage(
    wardrobeItemId: string,
    generationAttemptId: string,
    expectedRecordVersion: number,
  ): Promise<WardrobeItem> {
    const response = await request(
      `/v1/wardrobe-items/${wardrobeItemId}/shelf-image-versions/reject`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          generationAttemptId,
          expectedRecordVersion,
          idempotencyKey: idempotencyKey('reject'),
        }),
      },
    );
    return wardrobeItemResponseSchema.parse(await response.json()).wardrobeItem;
  },

  async permanentlyDeleteWardrobeItem(
    wardrobeItemId: string,
    expectedRecordVersion: number,
  ) {
    const response = await request(`/v1/wardrobe-items/${wardrobeItemId}`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        expectedRecordVersion,
        idempotencyKey: idempotencyKey('delete'),
      }),
    });
    return permanentlyDeleteWardrobeItemResponseSchema.parse(await response.json());
  },

  request,
};

function idempotencyKey(kind: string): string {
  return `mobile-${kind}-${Date.now()}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}
