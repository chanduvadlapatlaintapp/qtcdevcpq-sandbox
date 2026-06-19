/**
 * @description Test class for OpportunityUtil
 * @author      Sonali Kakade
 * @date        2025-07-03
 */
@isTest
public class OpportunityUtilTest {
    
    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    
    /**
     * @description Creates test data for all test methods including Account and Opportunity
     */
    @testSetup
    static void setupTestData() {
        Account acc = (Account) TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States',
                BillingState = 'NY'
            ),
            'AccountDefaults'
        );
        
        Opportunity opp = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = acc.Id
            ),
            'OpportunityDefaults'
        );
    }
    
    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Tests that isAmendmentOpp returns false for a non-amendment opportunity
     */
    @isTest
    static void testAmendment() {
        Opportunity opp = getTestOpportunity();
        
        Test.startTest();
        Boolean flag = OpportunityUtil.isAmendmentOpp(opp);
        Test.stopTest();
        
        System.assertEquals(false, flag, 'isAmendmentOpp should return false for non-amendment opportunity');
    }
    
    /**
     * @description Tests that isRenewalOpp returns false for a non-renewal opportunity
     */
    @isTest
    static void testRenewal() {
        Opportunity opp = getTestOpportunity();
        
        Test.startTest();
        Boolean flag = OpportunityUtil.isRenewalOpp(opp);
        Test.stopTest();
        
        System.assertEquals(false, flag, 'isRenewalOpp should return false for non-renewal opportunity');
    }
    
    /**
     * @description Tests that isAddOnOpp returns false for a default opportunity without deal type
     */
    @isTest
    static void testAddOn() {
        Opportunity opp = getTestOpportunity();
        
        Test.startTest();
        Boolean flag = OpportunityUtil.isAddOnOpp(opp);
        Test.stopTest();
        
        System.assertEquals(false, flag, 'isAddOnOpp should return false for default opportunity');
    }
    
    /**
     * @description BIZ-77189 - Tests that isAddOnOpp returns true for Add-On deal type
     */
    @isTest
    static void testIsAddOnOppAddOnDealType() {
        Opportunity opp = getTestOpportunity();
        opp.Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON;
        update opp;
        
        Test.startTest();
        Boolean result = OpportunityUtil.isAddOnOpp(opp);
        Test.stopTest();
        
        System.assertEquals(true, result, 'isAddOnOpp should return true for Add-On deal type');
    }
    
    /**
     * @description BIZ-77189 - Tests that isAddOnOpp returns true for Uplift deal type
     */
    @isTest
    static void testIsAddOnOppUpliftDealType() {
        Opportunity opp = getTestOpportunity();
        opp.Deal_Type__c = OpportunityConstants.DEAL_TYPE_UPLIFT;
        update opp;
        
        Test.startTest();
        Boolean result = OpportunityUtil.isAddOnOpp(opp);
        Test.stopTest();
        
        System.assertEquals(true, result, 'isAddOnOpp should return true for Uplift deal type');
    }
    
    /**
     * @description BIZ-77189 - Tests that isAddOnOpp returns true for Expansion deal type
     */
    @isTest
    static void testIsAddOnOppExpansionDealType() {
        Opportunity opp = getTestOpportunity();
        opp.Deal_Type__c = OpportunityConstants.DEAL_TYPE_EXPANSION;
        update opp;
        
        Test.startTest();
        Boolean result = OpportunityUtil.isAddOnOpp(opp);
        Test.stopTest();
        
        System.assertEquals(true, result, 'isAddOnOpp should return true for Expansion deal type');
    }
    
    /**
     * @description BIZ-77189 - Tests that isAddOnOpp returns false for non-amendment deal types
     *              such as New_Software, Renewal, and NYMY
     */
    @isTest
    static void testIsAddOnOppOtherDealTypes() {
        Opportunity opp = getTestOpportunity();
        
        Test.startTest();
        // Test New_Software
        opp.Deal_Type__c = OpportunityConstants.DEAL_TYPE_NEWSOFTWARE;
        Boolean newSoftwareResult = OpportunityUtil.isAddOnOpp(opp);
        
        // Test Renewal
        opp.Deal_Type__c = OpportunityConstants.DEAL_TYPE_RENEWAL;
        Boolean renewalResult = OpportunityUtil.isAddOnOpp(opp);
        
        // Test NYMY
        opp.Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY;
        Boolean nymyResult = OpportunityUtil.isAddOnOpp(opp);
        Test.stopTest();
        
        System.assertEquals(false, newSoftwareResult, 'isAddOnOpp should return false for New_Software deal type');
        System.assertEquals(false, renewalResult, 'isAddOnOpp should return false for Renewal deal type');
        System.assertEquals(false, nymyResult, 'isAddOnOpp should return false for NYMY deal type');
    }
    
    /**
     * @description Tests that isNYMYOpp returns false for a non-NYMY opportunity
     */
    @isTest
    static void testNYMYOpp() {
        Opportunity opp = getTestOpportunity();
        
        Test.startTest();
        Boolean flag = OpportunityUtil.isNYMYOpp(opp);
        Test.stopTest();
        
        System.assertEquals(false, flag, 'isNYMYOpp should return false for non-NYMY opportunity');
    }
    
    /**
     * @description Tests that isClosedWon returns false for a non-closed-won opportunity
     */
    @isTest
    static void testClosedWon() {
        Opportunity opp = getTestOpportunity();
        
        Test.startTest();
        Boolean flag = OpportunityUtil.isClosedWon(opp);
        Test.stopTest();
        
        System.assertEquals(false, flag, 'isClosedWon should return false for non-closed-won opportunity');
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Retrieves the test Opportunity from the database
     * @return Opportunity The test opportunity with required fields
     */
    private static Opportunity getTestOpportunity() {
        return [SELECT Id, Type, Deal_Type__c, StageName FROM Opportunity LIMIT 1];
    }
}