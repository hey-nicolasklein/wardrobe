import assert from 'node:assert/strict';
import { chromium, devices } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  headless: true,
  args: ['--no-sandbox'],
});
const context = await browser.newContext({
  ...devices['iPhone 13'],
  baseURL: 'http://127.0.0.1:18444',
});
const page = await context.newPage();
const errors = [];
const readyItemId = '40000000-0000-4000-8000-000000000001';
const lookAssetId = '20000000-0000-4000-8000-000000000001';
await page.route('**/v1/looks', async (route) => {
  if (route.request().method() !== 'GET') return route.continue();
  await route.fulfill({
    contentType: 'application/json',
    body: JSON.stringify({
      looks: [
        {
          id: '90000000-0000-4000-8000-000000000001',
          state: 'ready',
          assetId: lookAssetId,
          wardrobeItemIds: [readyItemId],
          characterSheetId: '80000000-0000-4000-8000-000000000001',
          parentLookId: null,
          concept: null,
          model: 'fixture',
          quality: 'medium',
          size: '1024x1280',
          providerRequestId: 'fixture',
          costMicrounits: 0,
          failureCategory: null,
          createdAt: '2026-01-15T12:00:00.000Z',
          finishedAt: '2026-01-15T12:00:00.000Z',
        },
      ],
    }),
  });
});
await page.route('**/v1/character-sheets', async (route) => {
  if (route.request().method() !== 'GET') return route.continue();
  await route.fulfill({
    contentType: 'application/json',
    body: JSON.stringify({
      characterSheets: [
        {
          id: '80000000-0000-4000-8000-000000000001',
          state: 'ready',
          referenceAssetIds: [lookAssetId],
          note: null,
          assetId: lookAssetId,
          active: true,
          model: 'fixture',
          quality: 'high',
          size: '864x1536',
          providerRequestId: 'fixture',
          costMicrounits: 0,
          failureCategory: null,
          createdAt: '2026-01-15T12:00:00.000Z',
          finishedAt: '2026-01-15T12:00:00.000Z',
        },
        {
          id: '80000000-0000-4000-8000-000000000002',
          state: 'ready',
          referenceAssetIds: [lookAssetId],
          note: null,
          assetId: lookAssetId,
          active: false,
          model: 'fixture',
          quality: 'high',
          size: '864x1536',
          providerRequestId: 'fixture',
          costMicrounits: 0,
          failureCategory: null,
          createdAt: '2026-01-02T12:00:00.000Z',
          finishedAt: '2026-01-02T12:00:00.000Z',
        },
        {
          id: '80000000-0000-4000-8000-000000000003',
          state: 'processing',
          referenceAssetIds: [lookAssetId],
          note: null,
          assetId: null,
          active: false,
          model: 'fixture',
          quality: 'high',
          size: '864x1536',
          providerRequestId: null,
          costMicrounits: null,
          failureCategory: null,
          createdAt: '2026-01-16T12:00:00.000Z',
          finishedAt: null,
        },
      ],
    }),
  });
});
page.on('pageerror', (error) => errors.push(error.message));
page.on('response', (response) => {
  if (response.status() >= 400) console.log(response.status(), response.url());
});
await mkdir('/tmp/form-pwa-qa', { recursive: true });
try {
  await page.goto('/');
  await page.getByRole('heading', { name: 'Für heute.' }).waitFor();
  await page.waitForFunction(() =>
    [...document.querySelectorAll('.look-card img')].every(
      (image) => image.complete && image.naturalWidth > 0,
    ),
  );
  await page.evaluate(() => {
    window.__feedImages = [...document.querySelectorAll('.look-card img')];
  });
  await page.getByRole('button', { name: 'Schrank', exact: true }).click();
  await page.getByRole('heading', { name: 'Dein Schrank.' }).waitFor();
  await page.getByRole('button', { name: 'Feed', exact: true }).click();
  await page.getByRole('heading', { name: 'Für heute.' }).waitFor();
  assert.equal(
    await page.evaluate(() => {
      const current = [...document.querySelectorAll('.look-card img')];
      return (
        current.length === window.__feedImages.length &&
        current.every((image, index) => image === window.__feedImages[index])
      );
    }),
    true,
  );
  await page.getByRole('button', { name: 'Look erstellen' }).click();
  await page.getByRole('heading', { name: 'Was möchtest du tragen?' }).waitFor();
  const composerLayout = await page.evaluate(() => {
    const sheet = document.querySelector('#sheet');
    const clothing = document.querySelector('.composer-items');
    const categories = document.querySelector('.composer-categories');
    const label = categories.querySelector('label');
    const checkbox = label.querySelector('input');
    const labelRect = label.getBoundingClientRect();
    const checkboxRect = checkbox.getBoundingClientRect();
    return {
      noSheetOverflow: sheet.scrollWidth === sheet.clientWidth,
      noClothingOverflow: clothing.scrollWidth === clothing.clientWidth,
      noCategoryOverflow: categories.scrollWidth === categories.clientWidth,
      categoryLayout: getComputedStyle(label).display,
      categoryCenterDelta: Math.abs(
        checkboxRect.top + checkboxRect.height / 2 - (labelRect.top + labelRect.height / 2),
      ),
    };
  });
  assert.deepEqual(composerLayout, {
    noSheetOverflow: true,
    noClothingOverflow: true,
    noCategoryOverflow: true,
    categoryLayout: 'flex',
    categoryCenterDelta: 0,
  });
  await page.screenshot({ path: '/tmp/form-pwa-qa/look-composer.png', fullPage: true });
  await page.getByRole('button', { name: 'Schließen' }).click();
  await page.getByRole('button', { name: 'Schrank', exact: true }).click();
  await page.getByRole('heading', { name: 'Dein Schrank.' }).waitFor();
  await page.waitForFunction(() =>
    [...document.querySelectorAll('.photo > img:not(.photo-source)')].every(
      (img) => img.complete && img.naturalWidth > 0,
    ),
  );
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.screenshot({
    path: '/tmp/form-pwa-qa/wardrobe.png',
    fullPage: true,
  });
  await page.locator('.item').first().click();
  await page.getByRole('button', { name: 'Details bearbeiten' }).click();
  await page.getByRole('button', { name: 'Änderungen speichern' }).waitFor();
  await page.locator('dialog').getByLabel('Name', { exact: true }).fill('Browser-Test Hemd');
  await page.getByRole('button', { name: 'Änderungen speichern' }).click();
  await page.getByRole('button', { name: /Browser-Test Hemd/ }).waitFor();
  await page.getByRole('button', { name: /Browser-Test Hemd/ }).click();
  await page.getByRole('button', { name: 'Details bearbeiten' }).waitFor();
  await page
    .locator('.gallery .slide img')
    .first()
    .evaluate((img) => img.decode());
  await page.screenshot({
    path: '/tmp/form-pwa-qa/detail.png',
    fullPage: true,
  });
  await page.getByRole('button', { name: 'Ins Archiv legen', exact: true }).click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: /Archiv öffnen/ }).click();
  await page.getByRole('button', { name: /Browser-Test Hemd/ }).click();
  await page.getByRole('button', { name: 'Zurück in den Schrank', exact: true }).click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Schrank', exact: true }).click();
  await page
    .getByRole('textbox', { name: 'Kleiderschrank durchsuchen' })
    .count()
    .catch(() => 0);
  await page.getByRole('searchbox').fill('Browser-Test Hemd');
  // Filtering hides tiles instead of rebuilding the grid, so count what is shown.
  assert.equal(await page.locator('.item:not([hidden])').count(), 1);
  await page.getByRole('button', { name: /Browser-Test Hemd/ }).click();
  await page.getByRole('button', { name: 'Stück endgültig löschen …' }).click();
  await page.getByRole('button', { name: 'Stück endgültig löschen', exact: true }).click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.locator('.item:not([hidden])').count(), 0);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.screenshot({
    path: '/tmp/form-pwa-qa/settings.png',
    fullPage: true,
  });
  // Settings keep the active sheet visible and show an in-progress replacement.
  assert.equal(await page.locator('.character-current').count(), 2);
  assert.equal(await page.locator('.character-current-pending').count(), 1);
  assert.equal(await page.locator('.character-version').count(), 0);
  await page.getByRole('button', { name: 'Frühere Versionen · 2' }).click();
  assert.equal(await page.locator('.character-version').count(), 2);
  assert.equal(await page.locator('.character-version .spinner').count(), 1);
  await page.getByRole('button', { name: /Character Sheet vom 2\.1\.2026/ }).click();
  await page.getByRole('button', { name: 'Als aktiv verwenden' }).waitFor();
  await page.getByRole('button', { name: 'Schließen' }).click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  // A finished reference starts the photo-collage flow from its detail view.
  await page.locator('.character-current:not(.character-current-pending)').click();
  await page.getByRole('button', { name: 'Neue Fotocollage erstellen' }).click();
  const portrait = Buffer.from('<svg width="800" height="1200" xmlns="http://www.w3.org/2000/svg"><rect width="800" height="1200" fill="#e8e2d8"/><circle cx="400" cy="330" r="170" fill="#c68f72"/><rect x="200" y="500" width="400" height="600" rx="120" fill="#344d3f"/></svg>');
  await page.locator('#character-form input[type=file]').setInputFiles([
    { name: 'portrait-one.svg', mimeType: 'image/svg+xml', buffer: portrait },
    { name: 'portrait-two.svg', mimeType: 'image/svg+xml', buffer: portrait },
  ]);
  await page.getByRole('button', { name: 'Weiter zum Zuschneiden' }).click();
  await page.getByRole('heading', { name: 'Zeig, was dich ausmacht.' }).waitFor();
  assert.equal(await page.locator('#crop-x, #crop-y').count(), 0);
  assert.equal(await page.locator('#crop-zoom').count(), 1);
  assert.equal(await page.locator('#crop-zoom').evaluate((input) => getComputedStyle(input).accentColor), 'rgb(52, 77, 63)');
  const crop = page.locator('#character-crop');
  const cropBox = await crop.boundingBox();
  await page.mouse.move(cropBox.x + cropBox.width / 2, cropBox.y + cropBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(cropBox.x + cropBox.width / 2 + 30, cropBox.y + cropBox.height / 2 + 30);
  await page.mouse.up();
  await page.getByRole('button', { name: 'Nächstes Foto' }).click();
  await page.getByRole('button', { name: 'Collage prüfen' }).click();
  await page.locator('#character-collage-preview').waitFor();
  await page.screenshot({
    path: '/tmp/form-pwa-qa/character-collage.png',
    fullPage: true,
  });
  await page.getByRole('button', { name: 'Schließen' }).click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  assert.deepEqual(errors, []);
  console.log(
    'PASS: mobile edit, search, archive, restore, delete, no overflow, no browser errors',
  );
} finally {
  await page.screenshot({ path: '/tmp/form-pwa-qa/last.png', fullPage: true });
  await browser.close();
}
