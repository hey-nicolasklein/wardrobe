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
  await expect(page.getByText('gpt-image-2 · low · 816x816 · prompt laid-flat-v1')).toHaveCount(2);
  await expect(page.getByText('$0.012 total', { exact: true })).toHaveCount(2);
  await page.screenshot({
    path: path.join(evidenceDirectory, `wardrobe-detail-${testInfo.project.name}.png`),
    fullPage: true,
  });

  await page.getByText('Shelf Image History', { exact: true }).scrollIntoViewIfNeeded();
  await page.screenshot({
    path: path.join(evidenceDirectory, `wardrobe-provenance-${testInfo.project.name}.png`),
    fullPage: true,
  });

  await page.goto('/40000000-0000-4000-8000-000000000002');
  await expect(page.getByText('Review Shelf Image', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Keep', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Reject', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Regenerate', exact: true })).toBeVisible();

  await page.goto('/40000000-0000-4000-8000-000000000004');
  await expect(page.getByText('Permanent Deletion', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Delete Permanently…', exact: true })).toBeVisible();
});
