import { expect, test } from '@playwright/test';
import path from 'node:path';

const evidenceDirectory = path.resolve(
  process.cwd(),
  'docs/wayfinder/persistent-wardrobe/assets',
);

test('fixture wardrobe browses into provenance-rich item details', async ({ page }, testInfo) => {
  await page.goto('/');
  await expect(page.getByText('FORM', { exact: true })).toBeVisible();

  await page.getByLabel('Email').fill('owner@example.test');
  await page.getByLabel('Password').fill('owner-fixture-password');
  await page.getByRole('button', { name: 'Sign In' }).click();

  await expect(page.getByText('Navy overshirt', { exact: true })).toBeVisible();
  await expect(page.getByText('Black trousers', { exact: true })).toBeVisible();
  await expect(page.getByText('Offline · showing saved wardrobe')).not.toBeVisible();
  await page.screenshot({
    path: path.join(evidenceDirectory, `wardrobe-grid-${testInfo.project.name}.png`),
    fullPage: true,
  });

  await page.getByLabel('Navy overshirt, jacket').click();
  await expect(page.getByText('Source Photo', { exact: true }).first()).toBeVisible();
  await expect(page.getByText('Shelf Image History', { exact: true })).toBeVisible();
  await expect(page.getByText('Current Shelf Image · AI-generated')).toBeVisible();
  await expect(page.getByText('kept · gpt-image-2 · low')).toHaveCount(2);
  await page.screenshot({
    path: path.join(evidenceDirectory, `wardrobe-detail-${testInfo.project.name}.png`),
    fullPage: true,
  });

  await page.getByText('Shelf Image History', { exact: true }).scrollIntoViewIfNeeded();
  await page.screenshot({
    path: path.join(evidenceDirectory, `wardrobe-provenance-${testInfo.project.name}.png`),
    fullPage: true,
  });
});
