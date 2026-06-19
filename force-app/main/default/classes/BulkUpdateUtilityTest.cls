/**
 * @description : test class for the BulkUpdateUtility class
**/
@isTest
public without sharing class BulkUpdateUtilityTest {

    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
    * @description Test setup
    **/
    @TestSetup
    private static void testSetup () {

        Test.startTest();

            // create a list of accounts

            TestFactory.createSObjectList(
                new Lead(
                    LastName = 'Test'
                ), 5);

        Test.stopTest();
    }

    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/

    /**
    * @description tests that records are updated when a field key value pairs are provided
    **/
    @IsTest
    public static void specificFieldUpdateTest () {

        // this are the values that we are going to attempt to set on all the Lead records
        String firstNameToSet = 'this_guy';
        Boolean optOutToSet = true;

        List<Lead> leads = getLeads();

        // make sure those values are not currently on the Leads
        for (Lead lead : Leads) {

            System.assertNotEquals( firstNameToSet, lead.FirstName,
                'Uh oh, the Leads data is not appropriate for this test to execute proplerly.');

            System.assertNotEquals( optOutToSet, lead.HasOptedOutOfEmail,
                'Uh oh, the Leads data is not appropriate for this test to execute proplerly.');
        }

        // run the bulk update utility
        Test.startTest();

            // config to set all the first names and opt outs
            Map<String, Object> fieldConfig =
                new Map<String, Object>{
                    'FirstName' => firstNameToSet,
                    'HasOptedOutOfEmail' => optOutToSet
                };

            BulkUpdateUtility.runUpdate('Select Id From Lead', fieldConfig);

        Test.stopTest();

        List<Lead> updatedLeads = getLeads();
            

        for (Lead lead : updatedLeads) {

            System.assertEquals( firstNameToSet, lead.FirstName,
                'Uh oh, the Leads were not updated by the BulkUpdateUtility class.');

            System.assertEquals( optOutToSet, lead.HasOptedOutOfEmail,
                'Uh oh, the Leads were not updated by the BulkUpdateUtility class.');
        }
    }

    /**
    * @description tests that a blind update can be executed against records in a provided query
    **/
    @IsTest
    public static void blindUpdateTest () {

        Test.startTest();

            BulkUpdateUtility.runUpdate('Select Id From Lead');

        Test.stopTest();

        System.assertEquals(true, getLeads().size() > 0, 'Leads were not updated by the BulkUpdateUtility class.');

    }

    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/

    /**
    * @description getter for leads
    * @return List<Lead>
    **/
    private static List<Lead> getLeads () {
        return [SELECT Id, FirstName, HasOptedOutOfEmail FROM Lead];
    }
}