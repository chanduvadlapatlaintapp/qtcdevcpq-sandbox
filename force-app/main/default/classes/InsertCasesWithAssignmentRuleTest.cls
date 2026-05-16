/**
 * @description
 * Test class for InsertCasesWithAssignmentRule.
 * Verifies assignment rule execution and returned Case IDs using TestFactory utilities.
 * 
 * @author Manisha
 * @jira BIZ-68164
 */
@isTest
private class InsertCasesWithAssignmentRuleTest {

    /**
     * @description
     * Tests the insertCases method with valid input using TestFactory.
     */
    @isTest
    static void testInsertCasesWithAssignmentRule() {
        Case testCase = (Case) TestFactory.buildSObject(
            new Case(
                Subject = 'Test Case',
                Status = 'New',
                Origin = 'Phone'
            )
        );

        List<Case> inputCases = new List<Case>{ testCase };
        Test.startTest();
        List<InsertCasesWithAssignmentRule.CaseResult> results =
            InsertCasesWithAssignmentRule.insertCases(inputCases);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'One CaseResult should be returned.');
        System.assertNotEquals(null, results[0].caseId, 'Returned Case ID should not be null.');
    }
}