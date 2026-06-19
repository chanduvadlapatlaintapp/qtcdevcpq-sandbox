# Claude Rules — qtcdevcpq-sandbox

## ACTIVE TASK SCOPE — Playwright Automation Tool ONLY
Only touch Playwright Automation Tool components:
- LWC: `agenticQtcTestDashboard`
- Apex: `AgenticQTC_TestRunnerController`, `AgenticQTC_TestRunnerController_Test`
- Local agent files: `~/.qtc-runner/agent.js`, `runner.js`, `uploader.js`, `auth.js`
- Test specs: `tests/e2e/`
- Custom objects: `Test_Run__c`, `Test_Result__c`, `Test_Progress__e`

**DO NOT read, edit, deploy, or retrieve any Amendments / Quote Editor Tool component.** If a task would require touching those components, stop and flag it instead.

## Always proceed without asking for confirmation
Do not ask for permission before running deploys, file edits, agent restarts, or any standard development operations. Just do it.

## Always fetch from qtcmock before editing any component
Before modifying any LWC or Apex class, always retrieve the latest version from the `qtcmock` org first. Others are actively developing on this sandbox and local files may be stale.

```bash
export PATH="$HOME/.local/node-v20.12.2-darwin-arm64/bin:$PATH"
```

### For a single LWC component:
```bash
sf project retrieve start --metadata "LightningComponentBundle:<componentName>" --target-org qtcmock
```

### For a single Apex class:
```bash
sf project retrieve start --metadata "ApexClass:<ClassName>" --target-org qtcmock
```

### For multiple components at once:
```bash
sf project retrieve start \
  --metadata "LightningComponentBundle:agenticQtcQuoteEditor" \
  --metadata "ApexClass:AgenticQTC_CPQController" \
  --target-org qtcmock
```

## Always deploy to qtcmock (not the default org)
The `sf` CLI default org is `qtcdevcpq` (marked with 🍁). Always pass `--target-org qtcmock` on every deploy command. Never omit it.

```bash
sf deploy metadata --source-dir <path> --target-org qtcmock --wait 15
```

## sf CLI path
The `sf` binary lives at:
```
~/.local/node-v20.12.2-darwin-arm64/bin/sf
```
Always set PATH before running sf commands:
```bash
export PATH="$HOME/.local/node-v20.12.2-darwin-arm64/bin:$PATH"
```

## Component inventory

### Amendments / Quote Editor Tool — LWC
- `agenticQtcApp` — root shell
- `agenticQtcQuoteEditor` — MDQ line editor
- `agenticQtcQuoteLineCard` — individual line card
- `agenticQtcMdqProductGroup` — MDQ product group
- `agenticQtcMdqRowLayout` — MDQ row layout
- `agenticQtcMdqTermGroup` — MDQ term group
- `agenticQtcChatSidebar` — AI chat panel
- `agenticQtcAccountSearch` — account/contract search
- `agenticQtcAddProduct` — product catalogue
- `agenticQtcOsaSelector` — OSA template selector
- `agenticQtcPreviewSend` — preview/send/approval modal
- `agenticQtcLoading` — shared spinner
- `agenticQTCAppFormulas` — ACV/TCV formula service module

### Amendments / Quote Editor Tool — Apex
- `AgenticQTC_AmendContractController`
- `AgenticQTC_QuoteAmendmentService`
- `AgenticQTC_AmendmentQueueable`
- `AgenticQTC_CPQController`
- `AgenticQTC_ProductService`
- `AgenticQTC_AccountSearchService`
- `AgenticQTC_ContractService`
- `AgenticQTC_OrderContractService`
- `AgenticQTC_AiChatController`
- `AgenticQTC_AiToolExecutor`
- `AgenticQTC_ApprovalLogicService`
- `AgenticQTC_ConfigService`
- `AgenticQTC_OsaDocumentService`
- `AgenticQTC_OsaTemplateController`
- `AgenticQTC_ContractOpsCaseService`
- `AgenticQTC_CalculatorCallback`
- `AgenticQTC_Tests`

### Playwright Automation Tool — LWC
- `agenticQtcTestDashboard` — test runner dashboard

### Playwright Automation Tool — Apex
- `AgenticQTC_TestRunnerController`
- `AgenticQTC_TestRunnerController_Test`
