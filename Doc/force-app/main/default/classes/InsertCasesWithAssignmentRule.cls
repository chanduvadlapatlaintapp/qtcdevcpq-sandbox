/**
 * @description
 * This class provides a Flow-invocable Apex method to insert Case records 
 * while applying the active assignment rule. It supports partial success 
 * and returns the list of successfully inserted Case IDs to Flow.
 * 
 * @author Manisha
 * @jira BIZ-68164
 */
public with sharing class InsertCasesWithAssignmentRule {

    /**
     * @description
     * Wrapper class to return Case record IDs back to Flow.
     */
    public class CaseResult {
        @InvocableVariable
        public Id caseId;
    }

    /**
     * @description
     * Flow-invocable method that inserts Case records using the active 
     * assignment rule and returns their IDs if successful.
     * 
     * @param cases List of Case records to insert.
     * @return List of CaseResult containing inserted Case IDs.
     */
    @InvocableMethod(label='Insert Cases With Assignment Rule')
    public static List<CaseResult> insertCases(List<Case> cases) {
        for (Case c : cases) {
            Database.DMLOptions opts = new Database.DMLOptions();
            opts.assignmentRuleHeader.useDefaultRule = true;
            c.setOptions(opts);
        }

        List<Database.SaveResult> results = Database.insert(cases, false);
        ResultHandler.logErrors('InsertCasesWithAssignmentRule', cases, results);

        List<CaseResult> output = new List<CaseResult>();
        for (Database.SaveResult res : results) {
            if (res.isSuccess()) {
                CaseResult cr = new CaseResult();
                cr.caseId = res.getId();
                output.add(cr);
            }
        }

        return output;
    }
}