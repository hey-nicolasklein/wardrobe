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
    [...document.querySelectorAll('.photo > img:not(.photo-source)')].every(
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
  await page.getByRole('button', { name: 'Details bearbeiten' }).click();
  await page.getByRole('button', { name: 'Änderungen speichern' }).waitFor();
  await page
    .locator('dialog')
    .getByLabel('Name', { exact: true })
    .fill('Browser-Test Hemd');
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
  await page
    .getByRole('button', { name: 'Ins Archiv legen', exact: true })
    .click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  await page
    .getByRole('button', { name: 'Einstellungen', exact: true })
    .click();
  await page.getByRole('button', { name: /Archiv öffnen/ }).click();
  await page.getByRole('button', { name: /Browser-Test Hemd/ }).click();
  await page
    .getByRole('button', { name: 'Zurück in den Schrank', exact: true })
    .click();
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
  await page
    .getByRole('button', { name: 'Stück endgültig löschen', exact: true })
    .click();
  await page.locator('dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.locator('.item:not([hidden])').count(), 0);
  await page
    .getByRole('button', { name: 'Einstellungen', exact: true })
    .click();
  await page.screenshot({
    path: '/tmp/form-pwa-qa/settings.png',
    fullPage: true,
  });
  assert.deepEqual(errors, []);
  console.log(
    'PASS: mobile edit, search, archive, restore, delete, no overflow, no browser errors',
  );
} finally {
  await page.screenshot({ path: '/tmp/form-pwa-qa/last.png', fullPage: true });
  await browser.close();
}
