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
page.on('pageerror', (error) => errors.push(error.message));
page.on('response', (response) => {
  if (response.status() >= 400) console.log(response.status(), response.url());
});
await mkdir('/tmp/form-pwa-qa', { recursive: true });
try {
  await page.goto('/');
  await page.getByRole('heading', { name: 'Dein Kleiderschrank.' }).waitFor();
  await page.waitForFunction(() =>
    [...document.querySelectorAll('.photo img')].every(
      (img) => img.complete && img.naturalWidth > 0,
    ),
  );
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
    true,
  );
  await page.screenshot({
    path: '/tmp/form-pwa-qa/wardrobe.png',
    fullPage: true,
  });
  await page.locator('.item').first().click();
  await page.getByRole('button', { name: 'Änderungen speichern' }).waitFor();
  await page
    .locator('dialog')
    .getByLabel('Name', { exact: true })
    .fill('Browser-Test Hemd');
  await page.getByRole('button', { name: 'Änderungen speichern' }).click();
  await page.getByRole('button', { name: /Browser-Test Hemd/ }).waitFor();
  await page.getByRole('button', { name: 'Hinzufügen', exact: true }).click();
  const svg =
    '<svg width="600" height="800" xmlns="http://www.w3.org/2000/svg"><rect width="600" height="800" fill="#eee9df"/><path d="M160 150 240 110 360 110 440 150 530 260 440 320 400 265 400 650 200 650 200 265 160 320 70 260Z" fill="#6e8271"/></svg>';
  const sharp = (await import('sharp')).default;
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  await page
    .locator('#library-input')
    .setInputFiles({
      name: 'test-shirt.png',
      mimeType: 'image/png',
      buffer: png,
    });
  await page.locator('[data-save]').waitFor();
  await page
    .locator('[data-save]')
    .getByLabel('Name', { exact: true })
    .fill('Grünes Testhemd');
  await page
    .locator('[data-save]')
    .getByLabel('Farben', { exact: true })
    .fill('Grün');
  await page.screenshot({
    path: '/tmp/form-pwa-qa/import.png',
    fullPage: true,
  });
  await page.getByRole('button', { name: 'In den Schrank aufnehmen' }).click();
  await page.locator('[data-save]').waitFor({ state: 'detached' });
  await page.getByRole('button', { name: 'Schrank', exact: true }).click();
  await page.getByRole('button', { name: /Grünes Testhemd/ }).click();
  await page.getByRole('button', { name: 'Änderungen speichern' }).waitFor();
  await page
    .locator('.gallery .slide img')
    .first()
    .evaluate((img) => img.decode());
  await page.screenshot({
    path: '/tmp/form-pwa-qa/detail.png',
    fullPage: true,
  });
  await page
    .getByRole('button', { name: 'Ins Archiv legen', exact: true })
    .click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  await page
    .getByRole('button', { name: 'Einstellungen', exact: true })
    .click();
  await page.getByRole('button', { name: /Archiv öffnen/ }).click();
  await page.getByRole('button', { name: /Grünes Testhemd/ }).click();
  await page
    .getByRole('button', { name: 'Zurück in den Schrank', exact: true })
    .click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Schrank', exact: true }).click();
  await page
    .getByRole('textbox', { name: 'Kleiderschrank durchsuchen' })
    .count()
    .catch(() => 0);
  await page.getByRole('searchbox').fill('Grünes Testhemd');
  assert.equal(await page.locator('.item').count(), 1);
  await page.getByRole('button', { name: /Grünes Testhemd/ }).click();
  await page.getByRole('button', { name: 'Stück endgültig löschen …' }).click();
  await page
    .getByRole('button', { name: 'Stück endgültig löschen', exact: true })
    .click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.locator('.item').count(), 0);
  await page
    .getByRole('button', { name: 'Einstellungen', exact: true })
    .click();
  await page.screenshot({
    path: '/tmp/form-pwa-qa/settings.png',
    fullPage: true,
  });
  assert.deepEqual(errors, []);
  console.log(
    'PASS: mobile import, save, edit, search, archive, restore, delete, no overflow, no browser errors',
  );
} finally {
  await page.screenshot({ path: '/tmp/form-pwa-qa/last.png', fullPage: true });
  await browser.close();
}
