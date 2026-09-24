import { z } from 'zod';
import { itemMetadataSchema } from '@form/contracts';
import { createPhotoItem, itemPreview, resetPersonalWardrobe } from '@form/service';
import { createHmac, timingSafeEqual } from 'node:crypto';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import {
  completeSourceUploadRequestSchema,
  createCharacterSheetRequestSchema,
  activateCharacterSheetRequestSchema,
  createLookRequestSchema,
  retryLookRequestSchema,
  createWardrobeItemRequestSchema,
  createUploadIntentRequestSchema,
  enqueueDetectionRequestSchema,
  enqueueGenerationRequestSchema,
  itemStateSchema,
  keepShelfImageRequestSchema,
  permanentlyDeleteWardrobeItemRequestSchema,
  rejectShelfImageRequestSchema,
  restoreShelfImageVersionRequestSchema,
  signInRequestSchema,
  updateWardrobeItemRequestSchema,
  contractVersion,
  type ApiError,
} from '@form/contracts';
import {
  authenticateSession,
  completeSourceUpload,
  createSession,
  createSourceUploadIntent,
  createWardrobeItemFromDetection,
  enqueueSourcePhotoDetection,
  enqueueShelfImageGeneration,
  getWardrobeItemDetail,
  getLatestDetectionAttempt,
  IdempotencyConflictError,
  InvalidWardrobeTransitionError,
  keepShelfImage,
  listDetectionProposals,
  listWardrobeItems,
  MediaValidationError,
  OwnedResourceNotFoundError,
  permanentlyDeleteWardrobeItem,
  rejectShelfImage,
  restoreShelfImageVersion,
  revokeSession,
  verifyCredentials,
  type Database,
  type DependencyHealth,
  type PrivateObjectStorage,
  type SessionRecord,
  StaleRecordVersionError,
  updateWardrobeItem,
  findOwnedPrivateAsset,
  activateCharacterSheet,
  createCharacterSheet,
  createLook,
  deleteLook,
  generationCosts,
  InspirationValidationError,
  listCharacterSheets,
  listLooks,
  retryLook,
  removeCharacterSheet,
} from '@form/service';
import { deleteCookie, getCookie, setCookie } from 'hono/cookie';
import { cors } from 'hono/cors';
import { Hono } from 'hono';

export type ReadinessCheck = () => Promise<DependencyHealth>;

export type AppDependencies = {
  checkReadiness: ReadinessCheck;
  database?: Database;
  storage?: PrivateObjectStorage;
  sessionSecret?: string;
  sessionLifetimeSeconds?: number;
  secureCookies?: boolean;
  webOrigin?: string;
  publicOrigin?: string;
  detectionModel?: string;
  personalAccountId?: string;
};

const sessionCookie = 'form_session';
const mediaTokenLifetimeSeconds = 300;

function mediaToken(secret: string, accountId: string, assetId: string, expiresAt: number): string {
  const payload = `${accountId}.${assetId}.${expiresAt}`;
  const signature = createHmac('sha256', secret).update(payload).digest('base64url');
  return `${Buffer.from(payload).toString('base64url')}.${signature}`;
}

function verifyMediaToken(
  secret: string,
  token: string,
): { accountId: string; assetId: string } | null {
  const [encodedPayload, signature] = token.split('.');
  if (!encodedPayload || !signature) return null;
  let payload: string;
  try {
    payload = Buffer.from(encodedPayload, 'base64url').toString('utf8');
  } catch {
    return null;
  }
  const [accountId, assetId, expiresAtText] = payload.split('.');
  const expiresAt = Number(expiresAtText);
  if (
    !accountId ||
    !assetId ||
    !Number.isSafeInteger(expiresAt) ||
    expiresAt < Math.floor(Date.now() / 1000)
  )
    return null;
  const expected = createHmac('sha256', secret).update(payload).digest();
  let actual: Buffer;
  try {
    actual = Buffer.from(signature, 'base64url');
  } catch {
    return null;
  }
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return null;
  return { accountId, assetId };
}

function errorPayload(
  category: ApiError['category'],
  code: string,
  message: string,
  retryable = false,
): { error: ApiError } {
  return { error: { category, code, message, retryable } };
}

function bearerToken(authorization: string | undefined): string | null {
  const match = authorization?.match(/^Bearer ([A-Za-z0-9_-]+)$/);
  return match?.[1] ?? null;
}

function wardrobeError(error: unknown): {
  status: 404 | 409;
  payload: { error: ApiError };
} | null {
  if (error instanceof OwnedResourceNotFoundError) {
    return {
      status: 404,
      payload: errorPayload('not-found', 'wardrobe-item-not-found', 'Wardrobe Item not found.'),
    };
  }
  if (error instanceof IdempotencyConflictError) {
    return {
      status: 409,
      payload: errorPayload('conflict', 'idempotency-key-reused', error.message),
    };
  }
  if (error instanceof StaleRecordVersionError) {
    return {
      status: 409,
      payload: errorPayload('conflict', 'stale-record-version', error.message),
    };
  }
  if (error instanceof InvalidWardrobeTransitionError) {
    return {
      status: 409,
      payload: errorPayload('conflict', 'invalid-wardrobe-transition', error.message),
    };
  }
  return null;
}

export function createApp(dependencies: AppDependencies | ReadinessCheck): Hono {
  const resolved: AppDependencies =
    typeof dependencies === 'function' ? { checkReadiness: dependencies } : dependencies;
  const app = new Hono();

  if (resolved.webOrigin) {
    app.use(
      '/v1/*',
      cors({
        origin: resolved.webOrigin,
        credentials: true,
        allowHeaders: ['Content-Type', 'Authorization'],
      }),
    );
  }

  app.get('/', (context) =>
    context.json({ service: 'form-api', status: 'ready', contractVersion }),
  );

  app.get('/v1/meta', (context) => {
    context.header('Cache-Control', 'no-store');
    return context.json({ service: 'form-api', contractVersion });
  });

  app.get('/health/live', (context) => context.json({ service: 'form-api', status: 'alive' }));

  app.get('/health/ready', async (context) => {
    const health = await resolved.checkReadiness();
    return context.json(health, health.status === 'ready' ? 200 : 503);
  });

  if (!resolved.database || !resolved.storage || !resolved.sessionSecret) return app;
  const database = resolved.database;
  const storage = resolved.storage;
  const secret = resolved.sessionSecret;
  const lifetimeSeconds = resolved.sessionLifetimeSeconds ?? 60 * 60 * 24 * 30;
  const secureCookies = resolved.secureCookies ?? true;
  const publicOrigin = resolved.publicOrigin;
  const detectionModel = resolved.detectionModel ?? 'gpt-5.6-luna';

  function publicUrl(path: string, requestUrl: string): URL {
    return new URL(path, publicOrigin ?? requestUrl);
  }

  let resetting = false;
  let activeWrites = 0;
  // The two media routes address immutable bytes and set their own caching
  // headers. Everything else under /v1 is account state that must not be cached.
  const mediaRoute = /^\/v1\/(wardrobe-items\/[^/]+\/preview|assets\/[^/]+\/content)$/;
  app.use('/v1/*', async (context, next) => {
    if (!mediaRoute.test(context.req.path)) context.header('Cache-Control', 'no-store');
    if (resetting)
      return context.json(
        errorPayload('conflict', 'reset-in-progress', 'Der Kleiderschrank wird gerade geleert.'),
        409,
      );
    const origin = context.req.header('Origin');
    if (
      !['GET', 'HEAD', 'OPTIONS'].includes(context.req.method) &&
      ((origin && resolved.webOrigin && origin !== resolved.webOrigin) ||
        context.req.header('Sec-Fetch-Site') === 'cross-site')
    ) {
      return context.json(
        errorPayload('authorization', 'origin-not-allowed', 'Request origin not allowed.'),
        403,
      );
    }
    const isWrite = !['GET', 'HEAD', 'OPTIONS'].includes(context.req.method);
    const isReset = context.req.path === '/v1/personal/reset';
    if (isReset && activeWrites > 0)
      return context.json(
        errorPayload(
          'conflict',
          'write-in-progress',
          'Bitte warte, bis Speichern und Hochladen abgeschlossen sind.',
        ),
        409,
      );
    if (isReset) resetting = true;
    if (isWrite) activeWrites++;
    try {
      await next();
    } finally {
      if (isWrite) activeWrites--;
      if (isReset) resetting = false;
    }
  });

  async function currentSession(context: Parameters<typeof getCookie>[0]): Promise<{
    session: SessionRecord;
    token: string;
  } | null> {
    if (resolved.personalAccountId) {
      const account = await database.query<{ id: string; email: string }>(
        'SELECT id, email FROM accounts WHERE id = $1 AND disabled_at IS NULL',
        [resolved.personalAccountId],
      );
      if (!account.rows[0]) return null;
      return {
        session: {
          ...account.rows[0],
          expiresAt: new Date(Date.now() + lifetimeSeconds * 1000),
        },
        token: '',
      };
    }
    const token =
      bearerToken(context.req.header('Authorization')) ?? getCookie(context, sessionCookie) ?? null;
    if (!token) return null;
    const session = await authenticateSession(database, token, secret);
    return session ? { session, token } : null;
  }

  app.post('/v1/personal/reset', async (context) => {
    const authenticated = await currentSession(context);
    if (!resolved.personalAccountId || !authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Private wardrobe required.'),
        401,
      );
    const body = await context.req.json().catch(() => null);
    if (body?.confirmation !== 'ALLES LÖSCHEN')
      return context.json(
        errorPayload(
          'validation',
          'confirmation-required',
          'Bestätige das Leeren des Kleiderschranks.',
        ),
        400,
      );
    resetting = true;
    try {
      await resetPersonalWardrobe(database, storage, authenticated.session.id);
      return context.body(null, 204);
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    } finally {
      resetting = false;
    }
  });

  app.post('/v1/wardrobe-items/from-photo', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    const parsed = z
      .object({
        sourcePhotoId: z.uuid(),
        metadata: itemMetadataSchema,
        state: z.enum(['owning', 'wanting']),
        idempotencyKey: z.uuid(),
      })
      .strict()
      .safeParse(await context.req.json().catch(() => null));
    if (!parsed.success)
      return context.json(
        errorPayload('validation', 'invalid-photo-item', 'Bitte prüfe Name, Kategorie und Farben.'),
        400,
      );
    try {
      return context.json(
        {
          wardrobeItem: await createPhotoItem(database, {
            accountId: authenticated.session.id,
            ...parsed.data,
          }),
        },
        201,
      );
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.get('/v1/wardrobe-items/:wardrobeItemId/preview', async (context) => {
    const authenticated = await currentSession(context);
    // Set per response, not through `context.header`: a prepared header is
    // merged over whatever the handler returns and would defeat the caching
    // headers on the image itself.
    const uncached = { 'Cache-Control': 'no-store' } as const;
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
        uncached,
      );
    try {
      const variant = context.req.query('variant') === 'source' ? 'source' : 'display';
      const bytes = await itemPreview(
        database,
        storage,
        authenticated.session.id,
        context.req.param('wardrobeItemId'),
        variant,
      );
      // Callers pass the item's record version, which every image and status
      // change bumps, so a versioned URL always names the same bytes and can be
      // served from the browser cache without a revalidation round trip.
      const versioned = Boolean(context.req.query('v'));
      return new Response(new Uint8Array(bytes), {
        headers: {
          'Content-Type': 'image/webp',
          'Cache-Control': versioned
            ? 'private, max-age=31536000, immutable'
            : 'private, max-age=60',
        },
      });
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status, uncached);
      throw error;
    }
  });

  app.post('/v1/auth/sign-in', async (context) => {
    const parsed = signInRequestSchema.safeParse(await context.req.json().catch(() => null));
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-sign-in-request', 'Enter a valid email and password.'),
        400,
      );
    }
    const account = await verifyCredentials(database, parsed.data);
    if (!account) {
      return context.json(
        errorPayload(
          'authentication',
          'invalid-credentials',
          'The email or password is incorrect.',
        ),
        401,
      );
    }
    const created = await createSession(database, account, secret, lifetimeSeconds);
    if (parsed.data.transport === 'cookie') {
      setCookie(context, sessionCookie, created.token, {
        httpOnly: true,
        secure: secureCookies,
        sameSite: 'Strict',
        path: '/',
        maxAge: lifetimeSeconds,
      });
    }
    return context.json({
      session: {
        accountId: account.id,
        email: account.email,
        expiresAt: created.session.expiresAt.toISOString(),
        nativeToken: parsed.data.transport === 'token' ? created.token : null,
      },
    });
  });

  app.get('/v1/auth/session', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to continue.'),
        401,
      );
    }
    return context.json({
      session: {
        accountId: authenticated.session.id,
        email: authenticated.session.email,
        expiresAt: authenticated.session.expiresAt.toISOString(),
        nativeToken: null,
      },
    });
  });

  app.post('/v1/auth/sign-out', async (context) => {
    const authenticated = await currentSession(context);
    if (authenticated) await revokeSession(database, authenticated.token, secret);
    deleteCookie(context, sessionCookie, { path: '/', secure: secureCookies });
    return context.body(null, 204);
  });

  app.post('/v1/source-photos/upload-intents', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to upload a photo.'),
        401,
      );
    }
    const parsed = createUploadIntentRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-upload-intent', 'Choose a supported image file.'),
        400,
      );
    }
    try {
      const intent = await createSourceUploadIntent(database, storage, {
        accountId: authenticated.session.id,
        contentType: parsed.data.contentType,
        byteSize: parsed.data.byteSize,
      });
      const expiresAt = Math.floor(intent.expiresAt.getTime() / 1_000);
      const token = mediaToken(secret, authenticated.session.id, intent.assetId, expiresAt);
      const uploadUrl = publicUrl(`/v1/assets/${intent.assetId}/content`, context.req.url);
      uploadUrl.searchParams.set('token', token);
      return context.json(
        {
          ...intent,
          uploadUrl: uploadUrl.toString(),
          expiresAt: intent.expiresAt.toISOString(),
        },
        201,
      );
    } catch (error) {
      if (error instanceof MediaValidationError) {
        return context.json(
          errorPayload('validation', error.code, error.message),
          error.code === 'upload-missing' ? 409 : 400,
        );
      }
      throw error;
    }
  });

  app.post('/v1/source-photos/complete', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to complete an upload.'),
        401,
      );
    }
    const parsed = completeSourceUploadRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload(
          'validation',
          'invalid-upload-completion',
          'The upload completion is invalid.',
        ),
        400,
      );
    }
    try {
      const completed = await completeSourceUpload(database, storage, {
        accountId: authenticated.session.id,
        ...parsed.data,
      });
      return context.json({
        sourcePhoto: {
          id: completed.sourcePhotoId,
          assetId: completed.asset.id,
          createdAt: completed.sourcePhotoCreatedAt.toISOString(),
        },
        asset: {
          id: completed.asset.id,
          purpose: completed.asset.purpose,
          contentType: completed.asset.contentType,
          byteSize: completed.asset.byteSize,
          pixelWidth: completed.asset.pixelWidth,
          pixelHeight: completed.asset.pixelHeight,
          createdAt: completed.asset.createdAt.toISOString(),
        },
      });
    } catch (error) {
      if (error instanceof IdempotencyConflictError) {
        return context.json(errorPayload('conflict', 'idempotency-key-reused', error.message), 409);
      }
      if (error instanceof MediaValidationError) {
        return context.json(
          errorPayload('validation', error.code, error.message),
          error.code === 'upload-missing' ? 409 : 400,
        );
      }
      if (error instanceof OwnedResourceNotFoundError) {
        return context.json(errorPayload('not-found', 'asset-not-found', 'Asset not found.'), 404);
      }
      throw error;
    }
  });

  app.get('/v1/assets/:assetId/download', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to view this media.'),
        401,
      );
    }
    const asset = await findOwnedPrivateAsset(
      database,
      authenticated.session.id,
      context.req.param('assetId'),
    );
    if (!asset || asset.state !== 'ready' || !asset.objectVersionId) {
      return context.json(errorPayload('not-found', 'asset-not-found', 'Asset not found.'), 404);
    }
    const expiresAt = Math.floor(Date.now() / 1000) + mediaTokenLifetimeSeconds;
    const token = mediaToken(secret, authenticated.session.id, asset.id, expiresAt);
    const downloadUrl = publicUrl(`/v1/assets/${asset.id}/content`, context.req.url);
    downloadUrl.searchParams.set('token', token);
    return context.json({
      assetId: asset.id,
      downloadUrl: downloadUrl.toString(),
      expiresAt: new Date(expiresAt * 1_000).toISOString(),
    });
  });

  app.get('/v1/assets/:assetId/content', async (context) => {
    // See the preview route: prepared headers would win over the response's own.
    const uncached = { 'Cache-Control': 'no-store' } as const;
    const assetId = context.req.param('assetId');
    const token = context.req.query('token');
    const verified = token ? verifyMediaToken(secret, token) : null;
    // Two ways in. A signed link carries its own expiry and is meant to be
    // shared out of the app; the session is how the app itself asks, and it
    // lets the URL stay the same so the browser can keep the picture.
    const accountId =
      verified?.assetId === assetId
        ? verified.accountId
        : ((await currentSession(context))?.session.id ?? null);
    if (!accountId) {
      return context.json(
        errorPayload(
          'authentication',
          'invalid-media-token',
          'This media link is invalid or expired.',
        ),
        401,
        uncached,
      );
    }
    const asset = await findOwnedPrivateAsset(database, accountId, assetId);
    if (!asset || asset.state !== 'ready' || !asset.objectVersionId) {
      return context.json(
        errorPayload('not-found', 'asset-not-found', 'Asset not found.'),
        404,
        uncached,
      );
    }
    const object = await storage.client.send(
      new GetObjectCommand({
        Bucket: storage.bucket,
        Key: asset.objectKey,
        VersionId: asset.objectVersionId,
      }),
    );
    if (!object.Body) {
      return context.json(
        errorPayload('not-found', 'asset-content-missing', 'Asset content not found.'),
        404,
        uncached,
      );
    }
    // A ready asset names one pinned object version, so the bytes behind this
    // URL never change. Signed links stop being cacheable when their token
    // dies; the session URL is stable and can be kept for good.
    return new Response(object.Body.transformToWebStream(), {
      headers: {
        'Cache-Control': verified
          ? `private, max-age=${mediaTokenLifetimeSeconds}`
          : 'private, max-age=31536000, immutable',
        'Content-Type': asset.contentType,
      },
    });
  });

  app.put('/v1/assets/:assetId/content', async (context) => {
    const verified = verifyMediaToken(secret, context.req.query('token') ?? '');
    if (!verified || verified.assetId !== context.req.param('assetId')) {
      return context.json(
        errorPayload(
          'authentication',
          'invalid-media-token',
          'This upload link is invalid or expired.',
        ),
        401,
      );
    }
    const asset = await findOwnedPrivateAsset(database, verified.accountId, verified.assetId);
    if (!asset || asset.state === 'deleted' || asset.purpose !== 'source-photo') {
      return context.json(
        errorPayload('not-found', 'upload-intent-not-found', 'Upload intent not found.'),
        404,
      );
    }
    if (context.req.header('Content-Type') !== asset.contentType) {
      return context.json(
        errorPayload(
          'validation',
          'upload-content-type-mismatch',
          'The uploaded photo type does not match the upload intent.',
        ),
        400,
      );
    }
    const bytes = new Uint8Array(await context.req.arrayBuffer());
    if (bytes.byteLength !== asset.byteSize) {
      return context.json(
        errorPayload(
          'validation',
          'upload-size-mismatch',
          'The uploaded photo size does not match the upload intent.',
        ),
        400,
      );
    }
    await storage.client.send(
      new PutObjectCommand({
        Bucket: storage.bucket,
        Key: asset.objectKey,
        Body: bytes,
        ContentType: asset.contentType,
        ContentLength: bytes.byteLength,
      }),
    );
    return context.body(null, 200);
  });

  app.get('/v1/wardrobe-items', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to view your wardrobe.'),
        401,
      );
    }
    const stateValue = context.req.query('state');
    const state = stateValue === undefined ? undefined : itemStateSchema.safeParse(stateValue);
    if (state && !state.success) {
      return context.json(
        errorPayload('validation', 'invalid-item-state', 'Choose Wanting, Owning, or Archive.'),
        400,
      );
    }
    return context.json({
      wardrobeItems: await listWardrobeItems(database, {
        accountId: authenticated.session.id,
        state: state?.data,
      }),
    });
  });

  app.get('/v1/character-sheets', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    return context.json({
      characterSheets: await listCharacterSheets(database, authenticated.session.id),
    });
  });

  app.post('/v1/character-sheets', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    const parsed = createCharacterSheetRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success)
      return context.json(
        errorPayload('validation', 'invalid-character-sheet', 'Speichere eine Fotocollage als Referenz.'),
        400,
      );
    try {
      return context.json(
        await createCharacterSheet(database, {
          accountId: authenticated.session.id,
          ...parsed.data,
        }),
        201,
      );
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post('/v1/character-sheets/:characterSheetId/activate', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    const parsed = activateCharacterSheetRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success)
      return context.json(
        errorPayload('validation', 'invalid-activation', 'Aktivierung ungültig.'),
        400,
      );
    try {
      await activateCharacterSheet(database, {
        accountId: authenticated.session.id,
        characterSheetId: context.req.param('characterSheetId'),
      });
      return context.body(null, 204);
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.delete('/v1/character-sheets/:characterSheetId', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    try {
      await removeCharacterSheet(database, {
        accountId: authenticated.session.id,
        characterSheetId: context.req.param('characterSheetId'),
      });
      return context.body(null, 204);
    } catch (error) {
      if (error instanceof InspirationValidationError)
        return context.json(errorPayload('conflict', error.code, error.message), 409);
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.get('/v1/looks', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    return context.json({
      looks: await listLooks(database, authenticated.session.id),
    });
  });

  app.post('/v1/looks', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    const parsed = createLookRequestSchema.safeParse(await context.req.json().catch(() => null));
    if (!parsed.success)
      return context.json(
        errorPayload('validation', 'invalid-look', 'Prüfe die gewählten Stücke und Kategorien.'),
        400,
      );
    try {
      return context.json(
        await createLook(database, {
          accountId: authenticated.session.id,
          ...parsed.data,
        }),
        202,
      );
    } catch (error) {
      if (error instanceof InspirationValidationError)
        return context.json(errorPayload('validation', error.code, error.message), 409);
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post('/v1/looks/:lookId/retry', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    const parsed = retryLookRequestSchema.safeParse(await context.req.json().catch(() => null));
    if (!parsed.success)
      return context.json(
        errorPayload('validation', 'invalid-retry', 'Wiederholung ungültig.'),
        400,
      );
    try {
      return context.json(
        await retryLook(database, {
          accountId: authenticated.session.id,
          lookId: context.req.param('lookId'),
          ...parsed.data,
        }),
        202,
      );
    } catch (error) {
      if (error instanceof InspirationValidationError)
        return context.json(errorPayload('conflict', error.code, error.message), 409);
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.delete('/v1/looks/:lookId', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    try {
      await deleteLook(database, {
        accountId: authenticated.session.id,
        lookId: context.req.param('lookId'),
      });
      return context.body(null, 204);
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.get('/v1/generation-costs', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Session required.'),
        401,
      );
    const week = context.req.query('week') || undefined;
    return context.json({
      costs: await generationCosts(database, authenticated.session.id, week),
    });
  });

  app.get('/v1/wardrobe-items/:wardrobeItemId', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to view this item.'),
        401,
      );
    }
    const detail = await getWardrobeItemDetail(database, {
      accountId: authenticated.session.id,
      wardrobeItemId: context.req.param('wardrobeItemId'),
    });
    return detail
      ? context.json(detail)
      : context.json(
          errorPayload('not-found', 'wardrobe-item-not-found', 'Wardrobe Item not found.'),
          404,
        );
  });

  app.get('/v1/source-photos/:sourcePhotoId/detections', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to view detections.'),
        401,
      );
    }
    const detections = await listDetectionProposals(database, {
      accountId: authenticated.session.id,
      sourcePhotoId: context.req.param('sourcePhotoId'),
    });
    return detections
      ? context.json({
          detections,
          attempt: await getLatestDetectionAttempt(database, {
            accountId: authenticated.session.id,
            sourcePhotoId: context.req.param('sourcePhotoId'),
          }),
        })
      : context.json(
          errorPayload('not-found', 'source-photo-not-found', 'Source Photo not found.'),
          404,
        );
  });

  app.post('/v1/source-photos/:sourcePhotoId/detections', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to analyze a photo.'),
        401,
      );
    }
    const parsed = enqueueDetectionRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-detection-request', 'The analysis request is invalid.'),
        400,
      );
    }
    try {
      const queued = await enqueueSourcePhotoDetection(database, {
        accountId: authenticated.session.id,
        sourcePhotoId: context.req.param('sourcePhotoId'),
        model: detectionModel,
        idempotencyKey: parsed.data.idempotencyKey,
      });
      return context.json(queued, 202);
    } catch (error) {
      if (error instanceof OwnedResourceNotFoundError) {
        return context.json(
          errorPayload('not-found', 'source-photo-not-found', 'Source Photo not found.'),
          404,
        );
      }
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post('/v1/wardrobe-items', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to add an item.'),
        401,
      );
    }
    const parsed = createWardrobeItemRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-wardrobe-item', 'Review the proposed item details.'),
        400,
      );
    }
    try {
      const wardrobeItem = await createWardrobeItemFromDetection(database, {
        accountId: authenticated.session.id,
        ...parsed.data,
      });
      return context.json({ wardrobeItem }, 201);
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.patch('/v1/wardrobe-items/:wardrobeItemId', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to edit this item.'),
        401,
      );
    }
    const parsed = updateWardrobeItemRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-wardrobe-edit', 'Review the item changes.'),
        400,
      );
    }
    try {
      const wardrobeItem = await updateWardrobeItem(database, {
        accountId: authenticated.session.id,
        wardrobeItemId: context.req.param('wardrobeItemId'),
        ...parsed.data,
      });
      return context.json({ wardrobeItem });
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post('/v1/generations', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to generate an image.'),
        401,
      );
    }
    const parsed = enqueueGenerationRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-generation-request', 'Review the generation settings.'),
        400,
      );
    }
    try {
      return context.json(
        await enqueueShelfImageGeneration(database, {
          accountId: authenticated.session.id,
          ...parsed.data,
        }),
        202,
      );
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post('/v1/wardrobe-items/:wardrobeItemId/shelf-image-versions/keep', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to keep this image.'),
        401,
      );
    }
    const parsed = keepShelfImageRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-keep-request', 'Refresh the item and try again.'),
        400,
      );
    }
    try {
      return context.json(
        await keepShelfImage(database, {
          accountId: authenticated.session.id,
          wardrobeItemId: context.req.param('wardrobeItemId'),
          ...parsed.data,
        }),
      );
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post('/v1/wardrobe-items/:wardrobeItemId/generations/reject', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated)
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to reject this image.'),
        401,
      );
    const parsed = rejectShelfImageRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success)
      return context.json(
        errorPayload('validation', 'invalid-reject-request', 'Refresh the item and try again.'),
        400,
      );
    try {
      return context.json(
        await rejectShelfImage(database, {
          accountId: authenticated.session.id,
          wardrobeItemId: context.req.param('wardrobeItemId'),
          ...parsed.data,
        }),
      );
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  app.post(
    '/v1/wardrobe-items/:wardrobeItemId/shelf-image-versions/:versionId/restore',
    async (context) => {
      const authenticated = await currentSession(context);
      if (!authenticated)
        return context.json(
          errorPayload(
            'authentication',
            'authentication-required',
            'Sign in to restore this image.',
          ),
          401,
        );
      const parsed = restoreShelfImageVersionRequestSchema.safeParse(
        await context.req.json().catch(() => null),
      );
      if (!parsed.success)
        return context.json(
          errorPayload('validation', 'invalid-restore-request', 'Refresh the item and try again.'),
          400,
        );
      try {
        return context.json(
          await restoreShelfImageVersion(database, {
            accountId: authenticated.session.id,
            wardrobeItemId: context.req.param('wardrobeItemId'),
            shelfImageVersionId: context.req.param('versionId'),
            ...parsed.data,
          }),
        );
      } catch (error) {
        const mapped = wardrobeError(error);
        if (mapped) return context.json(mapped.payload, mapped.status);
        throw error;
      }
    },
  );

  app.delete('/v1/wardrobe-items/:wardrobeItemId', async (context) => {
    const authenticated = await currentSession(context);
    if (!authenticated) {
      return context.json(
        errorPayload('authentication', 'authentication-required', 'Sign in to delete this item.'),
        401,
      );
    }
    const parsed = permanentlyDeleteWardrobeItemRequestSchema.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!parsed.success) {
      return context.json(
        errorPayload('validation', 'invalid-permanent-deletion', 'Refresh the item and try again.'),
        400,
      );
    }
    try {
      return context.json(
        await permanentlyDeleteWardrobeItem(database, storage, {
          accountId: authenticated.session.id,
          wardrobeItemId: context.req.param('wardrobeItemId'),
          ...parsed.data,
        }),
      );
    } catch (error) {
      const mapped = wardrobeError(error);
      if (mapped) return context.json(mapped.payload, mapped.status);
      throw error;
    }
  });

  return app;
}
