// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests/e2e',
  timeout: 600_000,          // 10 min per test — OSA suite with Conga PDF generation can take up to 5+ min
  expect: { timeout: 30_000 },
  workers: 1,                // one worker — prevents the same spec running in multiple shards
  fullyParallel: false,      // Salesforce org — run sequentially to avoid DML conflicts
  retries: 0,                // no retries — each attempt is slow; fail fast and re-queue
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'tests/e2e/report' }]],
  use: {
    headless: !!process.env.CI,    // false locally (headed), true on GitHub Actions (CI=true)
    // CI: explicit 1920x1080 so headless renders deterministically.
    // Local headed: per-project override below uses viewport: null so the page
    // fills the maximized window naturally (no apparent zoom on Windows DPI).
    viewport: { width: 1920, height: 1080 },
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
        // In CI (headless): inherit the 1920x1080 from `use` above.
        // Locally (headed): let the page fill the maximized window so it renders
        // at the OS's native DPI (no scaling). devices['Desktop Chrome'] sets a
        // deviceScaleFactor that conflicts with viewport:null, so clear it.
        ...(process.env.CI ? {} : { viewport: null, deviceScaleFactor: undefined }),
        launchOptions: {
          args: [
            ...(process.env.CI ? [] : ['--start-maximized']),
            '--high-dpi-support=1',
          ],
        },
      },
    },
  ],
  outputDir: 'tests/e2e/results',
});
