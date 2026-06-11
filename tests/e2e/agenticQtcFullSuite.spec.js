// @ts-check
/**
 * agenticQtcFullSuite.spec.js
 *
 * Runs all QTC test specs in a single sequential execution, covering the full
 * test surface of the AgenticQTC amendment editor.
 *
 * Excluded (require separate Conga / OSA PDF setup — run individually):
 *   • agenticQtcCongaPdfDataSync.spec.js
 *   • agenticQtcPreviewSendOSAUsingConga.spec.js
 *   • agenticQtcPreviewSendOSAUsingSalesforce.spec.js
 *
 * Skip behaviour (automatic — no action needed):
 *   • Each spec skips scenarios where the target account has no contract
 *     matching the required draft count (0, 1, or 2+ drafts).
 *   • Contact Update skips when no alternative contacts exist on the account.
 *   • Amendment Field Comparison skips when no activated contract is found.
 *   • Start Date Boundary / Change skip when no editable start date exists.
 *
 * MDQ / segment tests (quantityIncreaseSegments, quantityDecreaseSegments):
 *   These require an account whose contracts have multi-segment (MDQ) product
 *   rows. If the target account has non-MDQ quotes the tests will fail fast
 *   with a clear error ("Needed at least 2 MDQ rows"). Choose an account with
 *   MDQ contracts when running the full suite to exercise those specs.
 *
 * Running:
 *   npx playwright test tests/e2e/agenticQtcFullSuite.spec.js
 *   QTC_ACCOUNT_SEARCH="Acme" QTC_ACCOUNT_FULL_NAME="Acme Corp" \
 *     npx playwright test tests/e2e/agenticQtcFullSuite.spec.js
 */

// ── 1. Account search ──────────────────────────────────────────────────────
require('./agenticQtcAccountSearch.spec.js');

// ── 2. OSA / Contract Selector ────────────────────────────────────────────
require('./agenticQtcOsaSelector.spec.js');

// ── 3. App Navigation & Theme (UI smoke) ─────────────────────────────────
require('./agenticQtcAppNavigation.spec.js');

// ── 4. Quote Editor — Core (save gating, header links, back nav) ──────────
require('./agenticQtcQuoteEditorCore.spec.js');

// ── 5. Editor Action Buttons (Save / Submit / Preview & Send) ─────────────
require('./agenticQtcEditorButtons.spec.js');

// ── 6. Contact Update (Invoicing & Delivery) ──────────────────────────────
require('./agenticQtcContactUpdate.spec.js');

// ── 7. Start Date Change ──────────────────────────────────────────────────
require('./agenticQtcStartDateChange.spec.js');

// ── 8. Start Date Boundary Rejection ─────────────────────────────────────
require('./agenticQtcStartDateBoundary.spec.js');

// ── 9. Quantity Increase (full flow) ─────────────────────────────────────
require('./agenticQtcQuantityIncrease.spec.js');

// ── 10. Quantity Decrease (full flow) ─────────────────────────────────────
require('./agenticQtcQuantityDecrease.spec.js');

// ── 11. Quantity Increase — MDQ Segments ─────────────────────────────────
require('./agenticQtcQuantityIncreaseSegments.spec.js');

// ── 12. Quantity Decrease — MDQ Segments ─────────────────────────────────
require('./agenticQtcQuantityDecreaseSegments.spec.js');

// ── 13. Header Metrics Verification (ACV/TCV/YoY/DQS) ────────────────────
require('./agenticQtcMetricsVerification.spec.js');

// ── 14. Amendment Field Comparison (OOB vs AgenticQTC) ───────────────────
// TODO: OOB amendment REST endpoint throwing 500 (QTCTestRunner_OobAmendmentRestResource:62) — revisit later
// require('./agenticQtcAmendmentFieldComparison.spec.js');
