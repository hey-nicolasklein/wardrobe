import { chromium, devices } from '@playwright/test';
import assert from 'node:assert/strict';
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  args: ['--no-sandbox'],
});
const page = await browser.newPage({ ...devices['iPhone 13'] });
try {
  await page.goto('http://127.0.0.1:18444/#wanting');
  await page.getByRole('button', { name: /Canvas tote/ }).click();
  await page.getByRole('button', { name: 'Änderungen speichern' }).waitFor();
  if (
    await page
      .getByRole('button', { name: 'Bild verwenden', exact: true })
      .count()
  )
    await page
      .getByRole('button', { name: 'Bild verwenden', exact: true })
      .click();
  await page
    .getByRole('button', {
      name: 'Originalfoto im Schrank verwenden',
      exact: true,
    })
    .waitFor();
  await page
    .getByRole('button', {
      name: 'Originalfoto im Schrank verwenden',
      exact: true,
    })
    .click();
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
  assert.ok(await page.getByText(/1,1–1,9 US-Cent/).isVisible());
  await page
    .getByRole('button', { name: 'Bei meinem Foto bleiben', exact: true })
    .click();
  console.log(
    'PASS: keep catalog image, use original, restore version, view source, generation confirmation',
  );
} finally {
  await browser.close();
}
