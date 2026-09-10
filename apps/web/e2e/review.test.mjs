import { chromium, devices } from '@playwright/test';
import assert from 'node:assert/strict';
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  args: ['--no-sandbox'],
});
const page = await browser.newPage({ ...devices['iPhone 13'] });
try {
  await page.goto('http://127.0.0.1:18444/#owning');
  await page.getByRole('button', { name: /Navy overshirt/ }).click();
  await page.getByRole('button', { name: 'Details bearbeiten' }).waitFor();
  assert.equal(await page.getByText('Dein Bildentwurf').count(), 0);
  assert.equal(
    await page.getByRole('button', { name: 'Bild verwenden', exact: true }).count(),
    0,
  );
  assert.equal(await page.getByRole('button', { name: 'Verwerfen' }).count(), 0);
  assert.equal(
    await page.getByRole('button', { name: 'Originalfoto im Schrank verwenden' }).count(),
    0,
  );
  await page.getByRole('button', { name: /Dieses Bild verwenden/ }).waitFor();
  await page.getByRole('button', { name: /Dieses Bild verwenden/ }).click();
  await page.getByRole('button', { name: /Aktuelles Bild/ }).waitFor();
  await page
    .getByRole('button', { name: 'Originalfoto ansehen', exact: true })
    .click();
  await page
    .getByRole('button', { name: 'Zurück zum Stück', exact: true })
    .waitFor();
  await page
    .getByRole('button', { name: 'Zurück zum Stück', exact: true })
    .click();
  await page
    .getByRole('button', { name: 'Katalogbild erstellen …', exact: true })
    .click();
  await page
    .getByRole('button', {
      name: 'Ein kostenpflichtiges Bild anfordern',
      exact: true,
    })
    .waitFor();
  assert.ok(await page.getByText(/12 US-Cent/).isVisible());
  await page
    .getByRole('button', { name: 'Abbrechen', exact: true })
    .click();
  console.log(
    'PASS: no draft review, restore older version, view source, generation confirmation',
  );
} finally {
  await browser.close();
}
