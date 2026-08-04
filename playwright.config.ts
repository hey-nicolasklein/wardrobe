import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './apps/mobile/e2e',
  fullyParallel: false,
  reporter: 'line',
  timeout: 60_000,
  use: {
    baseURL: process.env.FORM_SMOKE_BASE_URL ?? 'http://localhost:8082',
    channel: 'chrome',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'desktop',
      use: { viewport: { width: 1365, height: 900 } },
    },
    {
      name: 'phone',
      browserName: 'chromium',
      use: {
        channel: 'chrome',
        viewport: devices['iPhone 13'].viewport,
        deviceScaleFactor: devices['iPhone 13'].deviceScaleFactor,
        hasTouch: true,
        isMobile: true,
        userAgent: devices['iPhone 13'].userAgent,
      },
    },
  ],
});
