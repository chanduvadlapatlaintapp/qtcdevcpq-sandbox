// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests/e2e',
  timeout: 300_000,          // 5 min per test
  expect: { timeout: 30_000 },
  fullyParallel: false,      // Salesforce org — run sequentially to avoid DML conflicts
  retries: 0,                // no retries — each attempt is slow; fail fast and re-queue
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'tests/e2e/report' }]],
  use: {
    headless: !!process.env.CI,    // false locally (headed), true on GitHub Actions (CI=true)
    viewport: { width: 1920, height: 1080 }, // large viewport → more content visible
    screenshot: 'on',
    video: 'on',                   // always record — uploaded to Salesforce after each run
    trace: 'retain-on-failure',
    actionTimeout: 30_000,
    navigationTimeout: 60_000,
  },
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1920, height: 1080 },
        launchOptions: {
          args: [
            '--start-maximized',        // window fills the entire screen
            '--high-dpi-support=1',     // crisp rendering on retina
          ],
        },
      },
    },
  ],
  outputDir: 'tests/e2e/results',
});
