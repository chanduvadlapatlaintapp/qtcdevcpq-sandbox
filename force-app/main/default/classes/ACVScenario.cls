/**
 * @description Enum representing the different ACV calculation scenarios.
 * @author Sahal Mohamed
 * @date 2026-02-04
 */
public enum ACVScenario {
    NONE,
    NEW_SALE_AMENDMENT,    // Scenario 1: Segment 1 New Sale or Amendment (Software)
    CONSOLIDATION_CREDIT,  // Scenario 2: Consolidation Credit Lines
    RENEWAL,               // Scenario 3: Segment 1 Renewal (Software, Maintenance, Support)
    MULTI_YEAR             // Scenario 4: Segment > 1 (Multi-year Software)
}