# SOQL 101 Debug Notes — Bundle + Segment Quantity Save
**Author:** Gaurav Mishra  
**Date:** 13 June 2026  
**Status:** Fixed (as of today's deployment)  
**Related tickets:** BIZ-83493, BIZ-82935, BIZ-83519

---

## Background

We were getting a `System.LimitException: Too many SOQL queries: 101` error when a user changed the quantity of both a segmented (MDQ) product and a bundle product on the same quote and hit Save in AgenticQTC. The weird part was that it only happened when you had both types together — changing only bundles was fine, and changing only segments was also fine. Same quote, same number of lines, just mixing the two product types caused the crash.

One more thing that made it confusing: if `Created_by_Simplified_Quoting__c` was false and `OP4I_Deal_ID__c` was blank, the error never happened even with the mix. That pointed us toward the OP4I publish path being involved somehow.

---

## What We Tried Before Finding the Real Cause

The first theory was that more lines meant more SOQL — maybe adding a bundle increased the line count past some threshold. That turned out to be wrong. I grabbed a log where the quote had 26 lines and it passed fine, then another with the same 26 lines but with both product types and it failed. So line count wasn't it.

Next thought was that publishing the DealEvent was causing the failure. But that was also wrong — a test with 2 bundle products published a DealEvent and passed without any issue.

Then I looked at whether `isChanged()` in `IntegrationUtility` was doing a SOQL per OLI in a loop. It's not — it uses `Field_Tracking__mdt.getAll()` which is in-memory, no queries.

---

## The Controlled Experiment

To isolate the variable properly, I ran three saves on the same quote with the same 26 OLIs. The only difference was which product types were present:

- **Run 1 — 2 bundle products only:** DealEvent published, 6 Opp flow executions, 4 Quote flow executions → **passed**
- **Run 2 — 2 segment products only:** No DealEvent, 6 Opp flow executions, 4 Quote flow executions → **passed**
- **Run 3 — 1 bundle + 1 segment:** DealEvent published, **7 Opp flow executions**, **5 Quote flow executions**, **2 AvaTax executions** → **failed**

Same OLI count. Same DML operations. Same everything — except Run 3 went through the Opp and Quote flow stack one extra time. That one extra cycle is what pushed the SOQL count over 100.

---

## What Was Actually Happening

The save path through AgenticQTC looks like this at a high level:

```
saveQuoteChanges()
  → calculateAndSaveQuote()
      → CPQ QuoteCalculator + QuoteSaver   (calculates and persists the quote)
      → resyncOpportunityProducts()
          → UPDATE Quote Primary=false      (CPQ deletes all OLIs)
          → UPDATE Quote Primary=true       (CPQ re-inserts all OLIs)
              → OLI After Insert trigger
                  → publishEligibleSobjectRecords()
                      → UPDATE updateOli    (sets Opportunity_Prod_Updated__c = true)
                          → Opportunity After Update trigger fires
                              → BIZ-82935 methods run (each with their own SOQL)
                              → Opp flows fire AGAIN  ← the extra cycle
  → advanceToFinalizeOsa()                  (still in the same 100-query budget)
```

The `resyncOpportunityProducts` method toggles `SBQQ__Primary__c` false then true. This is how CPQ's native "primary quote → Opportunity Products" sync works — there's no other way to trigger it. That toggle causes CPQ to delete and re-insert all OLIs. The OLI insert trigger then runs `publishEligibleSobjectRecords` in `IntegrationUtility`, which stamps `Opportunity_Prod_Updated__c = true` on certain OLIs via `update updateOli`. That Opportunity update fires the Opportunity After Update trigger, which fires the Opp flow stack.

The Opp flow stack has no recursion guard. So when the cascade inside the flow triggers another Opp update, the whole stack runs a second time. In the failing log you can see it clearly:

```
DML_BEGIN  Update  Opportunity
→ FLOW_START  Opportunity Before Insert Update
→ FLOW_START  Quote After Insert-Update
→ CODE_UNIT_STARTED  Flow:Opportunity
  → FLOW_START  Opportunity Before Insert Update    ← running again
  → FLOW_START  Opportunity After Insert Update     ← running again
  → FLOW_START  Opportunity : After Insert Or Update ← running again
    → FlowRecordLookup: Consolidated_Quote_s_Contract  (query #99)
    → FlowRecordLookup: Get_Email_for                  (query #101)
    → System.LimitException: Too many SOQL queries: 101
```

### Why only the bundle + segment mix? (PROVEN with anonymous Apex)

The trigger point is the `update updateOli` statement in `OpportunityProductTriggerHelper.publishOppLineItems` (line 296). Whether it fires, and what it carries, is decided by the classification loop just above it (lines 278–292). Every OLI is sorted into exactly one of three "shapes" using `SBQQ__ParentID__c` and the parent-ID map built from the query at lines 261–275:

```apex
Boolean isChild = oliRec.SBQQ__ParentID__c != null;
Boolean isStandalone = !isChild
    && !opportunityIdToParentIdMap.get(oliRec.OpportunityId).contains(oliRec.Id);
// (third shape: bundle PARENT — excluded from publishing)
```

| Line shape | `isChild` | `isStandalone` | Published? | Produced by |
|---|---|---|---|---|
| Bundle parent | false | false | No (excluded) | a bundle |
| Bundle component | **true** | false | Yes | a bundle |
| Standalone / segment | false | **true** | Yes | a segment / standalone product |

A read-only anonymous Apex script was written that replicates this exact classification on a live Opportunity's OLIs. It was run against three real quotes — all with the publish gate open — to isolate the product-mix variable:

| Quote | Gate | PARENT | CHILD | STANDALONE | BOTH SHAPES? | Result |
|---|---|---|---|---|---|---|
| **Bundle + Segment** (Opp 006WA00000MvfRZYAZ) | open | 2 | 18 | 6 | **TRUE** | **FAIL (101)** |
| **Segment only** (Opp 006WA00000MDWOnYAP) | open | 0 | **0** | standalone-shape | **false** | PASS |
| **Bundle only** (Opp 006Vm00000MHSo6IAH) | open | 1 | 4 | **0** | **false** | PASS |

The result is conclusive:

- **Bundle-only** produces only the **CHILD** shape (`STANDALONE = 0`)
- **Segment-only** produces only the **STANDALONE** shape (`CHILD = 0`)
- **Bundle + Segment** is the **only** configuration where **both shapes exist on a single Opportunity** (`CHILD = 18` AND `STANDALONE = 6`)

So `BOTH SHAPES PRESENT = true` is a perfect predictor of the failure — true only for the mix, false for both pure cases.

**Honest caveat:** A non-empty `updateOli` by itself is not unique to the mix — bundle-only also fills it (4 children → `update updateOli` runs). What is unique to the mix is that the publish batch spans **two different line shapes at once**, which route through two different paths in the downstream publish/flow cascade (the bundle parent-child path AND the standalone path). That mixed batch is what drives the extra Opportunity flow re-entry that neither pure case triggers. The shape analysis proves *why the mix has more cascade work to do*; the loop experiment (below) proves *that it does ~8 more queries*; and the controlled logs prove *it runs one extra Opp flow cycle*. Three independent lines of evidence point to the same root cause.

### The gate is the master switch

The same anonymous script also confirmed (independently) that when the publish gate is **closed** — i.e. `OP4I_Deal_ID__c` is blank AND `Created_by_Simplified_Quoting__c = false` — nothing publishes at all, regardless of product mix, and the save passes. This matches the original field observation: "whenever OP4I Deal Id is blank and Created by Simplified Quoting = false, then bundle + segment works fine." The gate (`OP4I_Deal_ID__c` populated OR `Created_by_Simplified_Quoting__c = true`) must be open for the cascade to run.

### Why was it 101 specifically and not more?

Before today's fix, every time the Opportunity `afterUpdate` trigger ran, it was also executing the BIZ-82935 logic:

```apex
// OpportunityTriggerHandler.cls — afterUpdate (old version)
OpportunityTriggerHelper.updateRenewalLetterOnHold(lstNewObject, mapOldObject);
// This one had a SOQL inside:
// SELECT Id, Status__c FROM Proforma_Invoice__c WHERE Renewal_Quote__r.SBQQ__Opportunity2__c IN :oppIds ...

FieldHistoryHandler.trackFieldChanges(lstNewObject, mapOldObject, 'Opportunity');
// This also issued SOQL for field comparison tracking
```

With 6 trigger executions (bundle-only or segment-only), the total SOQL stayed just under 100. With 7 executions (bundle+segment mix), those extra ~2 SOQL per execution × 7 runs pushed it just over 100.

---

## How It Got Fixed

Today "Business Applications" deployed a change that rolled back the BIZ-82935 logic from the Opportunity trigger:

**Removed from `OpportunityTriggerHandler.beforeUpdate`:**
```apex
OpportunityTriggerHelper.blockRenewalHoldClosedWon(lstNewObject, mapOldObject);
FieldHistoryHandler.trackFieldChangesOnInsert(lstNewObject, 'Opportunity');
```

**Removed from `OpportunityTriggerHandler.afterUpdate`:**
```apex
OpportunityTriggerHelper.updateRenewalLetterOnHold(lstNewObject, mapOldObject);
FieldHistoryHandler.trackFieldChanges(lstNewObject, mapOldObject, 'Opportunity');
```

The two methods in `OpportunityTriggerHelper` (`blockRenewalHoldClosedWon` and `updateRenewalLetterOnHold`) were also removed from the helper class — about 66 lines gone total.

The `Quote After Insert-Update` flow also got a new element added for BIZ-83519 (`Sync_Deal_Type_To_Opp`), but that one is gated on `ISCHANGED(Deal_Type__c)` so it doesn't fire during a quantity-change save. It's unrelated to this issue.

With the BIZ-82935 SOQL removed from each Opp trigger execution, the total dropped by roughly 14 queries (2 per execution × 7 executions). That was enough to bring it back under 100.

---

## Mock Replication — Confirmed

After the fix was deployed to UAT and confirmed working, a replication attempt was made in QTC Mock to verify the root cause independently. The issue did not reproduce in mock with the same steps, because the mock environment has a lower SOQL baseline than UAT — the BIZ-82935 queries that were consuming budget in UAT were not contributing the same amount in mock.

To bridge the gap, a temporary debug method was added to `AgenticQTC_CPQAmendmentService.calculateAndSaveQuote` that ran a simple SOQL query in a loop to artificially raise the baseline:

```apex
// DEBUG-ONLY — removed after testing
private static void simulateSoqlBaseline() {
    for (Integer i = 0; i < 8; i++) {
        List<User> u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    }
}
```

With 8 extra queries added, the mock behaviour exactly matched UAT:

| Scenario | Result |
|---|---|
| Bundle only | **No error** |
| Segment only | **No error** |
| Bundle + Segment together | **Too many SOQL queries: 101** |

This independently confirmed that:
1. The recursive extra Opp flow cycle is real and still present — it only triggers for the bundle+segment combination
2. The UAT baseline was sitting approximately 8 queries higher than mock, which is what the BIZ-82935 methods were contributing
3. Removing BIZ-82935 freed those ~8 queries, dropping UAT back under 100

The debug method was removed from the code after testing was complete.

---

## OLI Shape Diagnostic Script (reproducible proof)

This read-only anonymous Apex replicates the exact classification logic from `OpportunityProductTriggerHelper.publishOppLineItems` (lines 261–292). Set the quote name / Opportunity Id at the top and run it in Developer Console → Execute Anonymous. It prints whether the failing condition (`BOTH SHAPES PRESENT`) is true.

```apex
String quoteNameOrOppId = 'Q-90482';   // <-- quote name OR an Opportunity Id

Id oppId;
if (quoteNameOrOppId.startsWith('006')) {
    oppId = (Id) quoteNameOrOppId;
} else {
    oppId = [SELECT SBQQ__Opportunity2__c FROM SBQQ__Quote__c
             WHERE Name = :quoteNameOrOppId LIMIT 1].SBQQ__Opportunity2__c;
}

Opportunity opp = [SELECT Id, OP4I_Deal_ID__c, Deal_Type__c, Created_by_Simplified_Quoting__c
                   FROM Opportunity WHERE Id = :oppId LIMIT 1];
Set<String> allowedDealTypes = new Set<String>();
for (Allowed_Deal_Type_For_Sync__mdt r : Allowed_Deal_Type_For_Sync__mdt.getAll().values()) {
    if (String.isNotBlank(r.DeveloperName)) allowedDealTypes.add(r.DeveloperName.trim());
}
Boolean gateOpen = String.isNotBlank(opp.OP4I_Deal_ID__c)
    || allowedDealTypes.contains(opp.Deal_Type__c)
    || opp.Created_by_Simplified_Quoting__c == true;
System.debug('Gate open? ' + gateOpen);

Map<Id, Set<Id>> parentMap = new Map<Id, Set<Id>>{ oppId => new Set<Id>() };
List<OpportunityLineItem> allOlis = [
    SELECT Id, SBQQ__ParentID__c, OpportunityId, Skip_OP4I_Sync__c,
           Opportunity_Prod_Updated__c, Retrigger_OP4I_Sync__c, CPQ_Option_Type__c
    FROM OpportunityLineItem WHERE OpportunityId = :oppId];
for (OpportunityLineItem o : allOlis) {
    if (o.SBQQ__ParentID__c != null) parentMap.get(oppId).add(o.SBQQ__ParentID__c);
}

Integer parentCnt = 0, childPublish = 0, standalonePublish = 0;
for (OpportunityLineItem o : allOlis) {
    Boolean isChild = o.SBQQ__ParentID__c != null;
    Boolean isStandalone = !isChild && !parentMap.get(o.OpportunityId).contains(o.Id);
    Boolean isParent = !isChild && !isStandalone;
    if (isParent) parentCnt++;
    Boolean passes = (isChild && !o.Skip_OP4I_Sync__c) || isStandalone || o.Retrigger_OP4I_Sync__c;
    if (passes && gateOpen && o.Opportunity_Prod_Updated__c == false) {
        if (isChild) childPublish++;
        if (isStandalone) standalonePublish++;
    }
}
System.debug('PARENT=' + parentCnt + ' CHILD=' + childPublish + ' STANDALONE=' + standalonePublish);
System.debug('>>> BOTH SHAPES PRESENT (the failing condition)? ' + (childPublish > 0 && standalonePublish > 0));
```

Verified results (15 June 2026), all with gate open:

| Quote / Opp | PARENT | CHILD | STANDALONE | BOTH SHAPES? | Result |
|---|---|---|---|---|---|
| Bundle + Segment (006WA00000MvfRZYAZ) | 2 | 18 | 6 | **true** | FAIL |
| Segment only (006WA00000MDWOnYAP) | 0 | 0 | standalone-shape | false | PASS |
| Bundle only (006Vm00000MHSo6IAH) | 1 | 4 | 0 | false | PASS |

---

## One Thing Worth Noting

The underlying recursion in the Opp flow stack is still there. The fix worked by reducing the per-execution SOQL cost, not by stopping the extra cycle. If someone adds even a couple of SOQL queries to the Opp trigger in the future, this will come back.

The proper long-term fix would be a recursion guard on the Opportunity and Quote record-triggered flows — either `ISCHANGED()` entry criteria on the fields they actually care about, or a transaction-level flag like the one already in `ACVChangeCalculationService`:

```apex
private static Boolean isProcessing = false;

if (isProcessing) return;
isProcessing = true;
try {
    // ... actual logic
} finally {
    isProcessing = false;
}
```

That pattern would stop the extra cycle entirely rather than just managing the query budget around it.

---

## The Exact Fix (recommended)

The current state — removing the BIZ-82935 queries — is a mitigation. It lowered the baseline enough that the extra flow lap fits under 100, but the recursion is still there. The targeted, root-cause fix is to **move the flag-stamping `update` out of the save transaction.**

### Where

`OpportunityProductTriggerHelper.publishOppLineItems`, the after-insert branch (lines 283–302). This is the one statement that re-fires the whole cascade:

```apex
if (oldMap == null) {                       // after-insert path (the resync re-insert)
    oliRec.Opportunity_Prod_Updated__c = true;
    updateOli.add(oliRec);
}
...
if (!updateOli.isEmpty()) {
    update updateOli;                       // ← re-fires OLI after-update → Opportunity → Opp flow stack (twice)
}
```

That synchronous `update updateOli` runs inside the save's single 100-query budget. It touches the Opportunity, which runs the unguarded Opportunity flow stack an extra time — and that extra lap is what crosses 100.

### The change

Stamp the flag in a **Queueable** instead of inline, so it runs in its own fresh transaction with its own 100-query budget:

```apex
// instead of: update updateOli;
if (!updateOli.isEmpty()) {
    System.enqueueJob(
        new FlagOliUpdatedQueueable(new Map<Id, OpportunityLineItem>(updateOli).keySet())
    );
}
```

…with a small Queueable that re-queries those Ids and performs the update. From there the normal publish / DealEvent path still runs — just in the async transaction, where there is room.

### Why this is the right fix

- **It targets the real mechanism.** The extra Opportunity flow lap is removed from the save transaction, so the budget the save competes for drops back to where bundle-only and segment-only already sit.
- **Behaviour is preserved.** The flag still gets set and the DealEvent still publishes — just a moment later, in the Queueable's transaction.
- **It is not a blunt instrument.** Unlike the `Automation_Controls__c` bypass (global, kills the whole trigger, and cannot be scoped to the freshly re-inserted OLIs from the resync) or simply removing more queries (a mitigation that breaks the moment someone adds a query), this fixes the cause without disabling unrelated logic.

### Two things to verify when building it

1. **Enqueue limits** — confirm this is a single enqueue per resync batch, not one per record (chained Queueables are capped per transaction).
2. **No synchronous dependency** — confirm nothing later in the same save reads `Opportunity_Prod_Updated__c` back, since it will now be set slightly later. From the current code path nothing does, but worth a quick check.

### Follow-up hardening (lower urgency)

After the async fix is in, add the recursion guard to the Opportunity/Quote flows (the `ISCHANGED()` / run-once pattern above). That stops the flow from ever running a second lap regardless of what the trigger does — so even a future query-heavy change can't bring the 101 back.

---

## Second Issue — Bundle Quantity Not Updating Component

This one was separate. When changing Static Bundle quantity, the Static Component quantity wasn't changing and `Revenue_Allocated__c` wasn't recalculating.

The logic for this lives in the QCP, specifically `setSegmentedBundleKey` around line 490 of `QTC_Calculator_Plugin.Fix.code.js`. It builds a key for the bundle line from `line.parentItemKey` (which comes from `SBQQ__RequiredBy__c`) and matches it against the component's `line.record.Parent_Line_Id_Text__c`. When `SBQQ__RequiredBy__c` is blank on the bundle line, `parentItemKey` comes back as `undefined`, so the bundle key ends up as something like `"1__undefined"` and never matches the component's key of `"1__8"`. No match → no quantity copy → no revenue recompute.

On Q-80294 specifically, `SBQQ__RequiredBy__c` was blank on 15 lines. CPQ normally populates this field when a bundle is added through its standard product configuration flow, but those lines had gone through a different path that didn't set it. A data patch was run on 12 June to populate `SBQQ__RequiredBy__c` on those 15 lines by looking them up against `Parent_Line_Id_Text__c`.

The code fix that needs to go in (not deployed yet) is a one-line change in the QCP:

```javascript
// QTC_Calculator_Plugin.Fix.code.js, line ~512
// Before:
const bundleKey = line.parentItemKey;

// After — falls back to the persisted custom field if RequiredBy is blank:
const bundleKey = line.record.Parent_Line_Id_Text__c || line.parentItemKey;
```

---

## What Still Needs to Happen

- **Async the flag-stamp `update updateOli`** in `publishOppLineItems` (the exact fix above) — moves the extra flow lap out of the save transaction. **High priority.**
- **Recursion guard on Opp/Quote flows** — follow-up hardening so the flow can never run a second lap (do after the async fix)
- **Deploy the QCP one-liner** — `Parent_Line_Id_Text__c || line.parentItemKey` in `setSegmentedBundleKey`
- **Retest Q-80294** — verify bundle qty propagates correctly after the data patch by recalculating the quote
- **Move `advanceToFinalizeOsa` to Queueable** — it currently runs synchronously in the same 100-query budget as the whole save; making it async would give the main transaction more headroom (low priority now that the immediate fix is in)
