import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';

import { chromium, devices } from '@playwright/test';
import {
  createDatabase,
  fixtureIds,
  readDatabaseConfig,
  recordDetectionProposals,
} from '@form/service';
import sharp from 'sharp';

const database = createDatabase(readDatabaseConfig());
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
let detectionRequests = 0;
page.on('pageerror', (error) => errors.push(error.message));

await mkdir('/tmp/form-auto-add-qa', { recursive: true });
try {
  await page.route('**/v1/source-photos/*/detections', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();

    const response = await route.fetch();
    const responseBody = await response.json();
    const sourcePhotoId = new URL(route.request().url()).pathname.split('/')[3];
    detectionRequests++;
    if (detectionRequests === 1)
      await recordDetectionProposals(database, {
        accountId: fixtureIds.populatedAccount,
        sourcePhotoId,
        detections: [
          {
            id: randomUUID(),
            name: 'Grünes Testhemd',
            category: 'top',
            colors: ['Grün'],
            boundingBox: { x: 90, y: 80, width: 440, height: 520 },
          },
          {
            id: randomUUID(),
            name: 'Blaue Testhose',
            category: 'pants',
            colors: ['Blau'],
            boundingBox: { x: 560, y: 250, width: 350, height: 650 },
          },
        ],
      });
    await database.query(
      `UPDATE detection_attempts SET state = 'succeeded', provider_request_id = 'browser-fixture',
         finished_at = now() WHERE id = $1`,
      [responseBody.detectionAttemptId],
    );
    await route.fulfill({
      status: response.status(),
      headers: response.headers(),
      contentType: 'application/json',
      body: JSON.stringify(responseBody),
    });
  });

  await page.goto('/#add');
  const svg =
    '<svg width="800" height="1000" xmlns="http://www.w3.org/2000/svg"><rect width="800" height="1000" fill="#eee9df"/><rect x="90" y="80" width="350" height="520" rx="30" fill="#6e8271"/><rect x="500" y="250" width="240" height="650" rx="30" fill="#436078"/></svg>';
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  await page.locator('#library-input').setInputFiles({
    name: 'outfit.png',
    mimeType: 'image/png',
    buffer: png,
  });

  await page.getByRole('heading', { name: '2 Stücke erkannt' }).waitFor();
  assert.equal(await page.locator('.detection-box').count(), 2);
  await page.getByRole('button', { name: 'Blaue Testhose abwählen' }).click();
  await page.getByRole('button', { name: '1 Stück hinzufügen' }).waitFor();
  await page.screenshot({
    path: '/tmp/form-auto-add-qa/selection.png',
    fullPage: true,
  });
  await writeFile(
    '/tmp/form-auto-add-qa/selection.aria.txt',
    await page.locator('body').ariaSnapshot(),
  );

  await page.getByRole('button', { name: '1 Stück hinzufügen' }).click();
  await page.getByRole('heading', { name: 'Dein Kleiderschrank.' }).waitFor();
  const generatedItem = page.getByRole('button', { name: /Grünes Testhemd/ });
  await generatedItem.waitFor();
  await generatedItem.locator('.wardrobe-image-progress').waitFor({ timeout: 2_000 });
  assert.equal(await generatedItem.locator('.photo img').count(), 0);
  await generatedItem.click();
  const detailDialog = page.locator('dialog');
  await detailDialog.locator('.wardrobe-image-progress').waitFor({ timeout: 2_000 });
  assert.equal(await detailDialog.locator('.gallery .slide').first().locator('img').count(), 0);
  await detailDialog.getByRole('button', { name: 'Schließen' }).click();

  const itemsResponse = await context.request.get('/v1/wardrobe-items');
  const itemNames = ((await itemsResponse.json()).wardrobeItems).map(
    (item) => item.metadata.name,
  );
  assert.equal(itemNames.includes('Grünes Testhemd'), true);
  assert.equal(itemNames.includes('Blaue Testhose'), false);

  const generation = await database.query(
    `SELECT attempts.auto_keep, attempts.state
     FROM generation_attempts attempts
     JOIN wardrobe_items items ON items.id = attempts.wardrobe_item_id
     WHERE items.name = 'Grünes Testhemd'`,
  );
  assert.deepEqual(generation.rows[0], { auto_keep: true, state: 'queued' });

  await page.getByRole('button', { name: 'Hinzufügen', exact: true }).click();
  await page.locator('#library-input').setInputFiles({
    name: 'unknown.png',
    mimeType: 'image/png',
    buffer: png,
  });
  await page.getByRole('heading', { name: 'Selbst hinzufügen' }).waitFor();
  const manualForm = page.locator('[data-manual-save]');
  await manualForm.getByLabel('Name', { exact: true }).fill('Manuelles Teststück');
  await manualForm.getByLabel('Farben', { exact: true }).fill('Creme');
  await page.screenshot({
    path: '/tmp/form-auto-add-qa/manual-fallback.png',
    fullPage: true,
  });
  await manualForm.getByRole('button', { name: 'Stück hinzufügen' }).click();
  await page.getByRole('heading', { name: 'Dein Kleiderschrank.' }).waitFor();
  await page.getByRole('button', { name: /Manuelles Teststück/ }).waitFor();

  assert.equal(
    await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    true,
  );
  assert.deepEqual(errors, []);
  console.log(
    'PASS: automatic detection, selectable boxes, selective import, manual fallback, and durable auto-adopt enqueue',
  );
} finally {
  await page.screenshot({
    path: '/tmp/form-auto-add-qa/result.png',
    fullPage: true,
  });
  await browser.close();
  await database.end();
}
