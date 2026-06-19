/**
* @description Test class for RecordTypeUtil
* @author Sahal Mohamed
* @CreatedDate - Feb 12, 2025
**/
@isTest
public without sharing class RecordTypeUtilTest {

    /**
    * @description this methods test whether the RecordTypeUtil returns the right name when Id is provided
    **/
    @isTest
    static void getRecordTypeIdAndNameTest() {

        String migrationOppRT = RecordTypeUtil.getRecordTypeId(Opportunity.sObjectType, OpportunityConstants.RT_MIGRATION_OPP);

        // Assertions
        Assert.areEqual(
            OpportunityConstants.RT_MIGRATION_OPP, 
            RecordTypeUtil.getRecordTypeDevName(Opportunity.sObjectType, migrationOppRT), 
            'Record Type Name queried does not match'
        );
    }
}