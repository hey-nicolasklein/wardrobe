// Drive the FORM PWA in an emulated iPhone 13 and capture evidence.
// Run from the repo root so @playwright/test resolves:
//   PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium \
//     node .agents/skills/verify-form/helpers/drive.mjs <hashRoute> <label>
//
// <hashRoute> is a client route the nav uses: owning | wanting | add | settings
//   (also reachable as #owning, #wanting, ...). Defaults to owning.
// <label> names the evidence file. Screenshots + an ARIA snapshot land in
//   the directory named by FORM_VERIFY_OUT (default /tmp/form-verify).
// This is a read-only smoke: it navigates, waits for images, checks for
// horizontal overflow and page errors, and captures state. Mutating flows
// (save/edit/archive/delete) live in apps/web/e2e/mobile.test.mjs.
import { chromium, devices } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';

const route = (process.argv[2] ?? 'owning').replace(/^#/, '');
const label = process.argv[3] ?? route;
const base = process.env.FORM_VERIFY_BASE ?? 'http://127.0.0.1:18444';
const out = process.env.FORM_VERIFY_OUT ?? '/tmp/form-verify';
await mkdir(out, { recursive: true });

const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ?? '/usr/bin/chromium',
  headless: true,
  args: ['--no-sandbox'],
});
const context = await browser.newContext({ ...devices['iPhone 13'], baseURL: base });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));
page.on('response', (r) => {
  if (r.status() >= 400) errors.push(`HTTP ${r.status()} ${r.url()}`);
});

try {
  await page.goto(`/#${route}`);
  // The shell renders a fresh heading per route; wait for the nav to exist.
  await page.getByRole('navigation', { name: 'Hauptnavigation' }).waitFor();
  await page
    .waitForFunction(
      () =>
        [...document.querySelectorAll('img')].every(
          (img) => !img.getAttribute('src') || (img.complete && img.naturalWidth > 0),
        ),
      { timeout: 15_000 },
    )
    .catch(() => {});

  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth > innerWidth,
  );
  const snapshot = await page.locator('main.shell').ariaSnapshot();
  await writeFile(`${out}/${label}.aria.txt`, snapshot);
  await page.screenshot({ path: `${out}/${label}.png`, fullPage: true });

  const report = {
    route,
    base,
    horizontalOverflow: overflow,
    errors,
    screenshot: `${out}/${label}.png`,
    aria: `${out}/${label}.aria.txt`,
  };
  console.log(JSON.stringify(report, null, 2));
  if (overflow || errors.length) process.exitCode = 1;
} finally {
  await page.screenshot({ path: `${out}/${label}.last.png`, fullPage: true }).catch(() => {});
  await browser.close();
}
