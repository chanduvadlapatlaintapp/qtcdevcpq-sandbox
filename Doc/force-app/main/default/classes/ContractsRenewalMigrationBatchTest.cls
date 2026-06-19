/**
 * @description Test class for ContractsRenewalMigrationBatch
 * @author      Manisha
 * @date        2025-06-30
 * @jira        BIZ-70776
 */
@isTest
public class ContractsRenewalMigrationBatchTest {

    /***********************************************************************************************
    *
    * Shared Test Data Setup
    *
    ***********************************************************************************************/
    
    /**
     * @description Insert shared test data using TestFactory.
     */
    @testSetup
    static void setup() {
        List<User> userList = new List<User>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (Integer i = 1; i <= 4; i++) {
                User u = (User)TestFactory.buildSObject(
                    new User(LastName = 'TestUser' + i),
                    'AdminUserDefaults'
                );
                userList.add(u);
            }
            insert userList;
        }

        Account account = (Account)TestFactory.buildSObject(
            new Account(
                Name = 'Intapp',
                Type = 'Customer',
                CRD__c = userList[1].Id,
                OwnerId = userList[3].Id,
                Create_Prospect__c = '01',
                BillingStreet = '123 Street',
                BillingCity = 'New York',
                BillingPostalCode = '10001',
                BillingCountry = 'United States',
                BillingState = 'NY',
                ShippingStreet = '456 Avenue',
                ShippingCity = 'New York',
                ShippingPostalCode = '10001',
                ShippingCountry = 'United States',
                ShippingState = 'NY'
            ),
            'AccountDefaults'
        );
        insert account;

        Opportunity opp = (Opportunity)TestFactory.buildSObject(
            new Opportunity(
                Name = 'Test Opp',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = account.Id
            ),
            'OpportunityDefaults'
        );
        insert opp;

        List<Contract> contracts = new List<Contract>();
        for (Integer i = 0; i < 3; i++) {
            Contract con = (Contract)TestFactory.buildSObject(
                new Contract(
                    Migration_Status__c = 'Renewal Ready',
                    EndDate = Date.today().addDays(100),
                    SBQQ__RenewalForecast__c = false,
                    SBQQ__RenewalQuoted__c = false,
                    AccountId = account.Id,
                    SBQQ__Opportunity__c = opp.Id
                ),
                'ContractDefaults'
            );
            contracts.add(con);
        }
        insert contracts;

        OP4I_Entitlement_Renewal_View__c op4i = new OP4I_Entitlement_Renewal_View__c(
            OSA__c = contracts[0].id,
            Product_Id__c = 'test'
        );
        insert op4i;
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description test method to verify ContractsRenewalMigrationBatch when contract numbers are provided.
     * It asserts that the SBQQ__RenewalForecast__c field is set to true.
    */
    @isTest
    static void testBatchWithContractNumbers() {
        List<Contract> contracts = getTestContract();
        List<String> contractSuffixes = new List<String>();
        for (Contract con : contracts) {
            contractSuffixes.add(con.ContractNumber.right(1));
        }

        ContractsRenewalMigrationBatch batch = new ContractsRenewalMigrationBatch(contractSuffixes);

        Test.startTest();
        Id jobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        for (Contract con : getTestContract()) {
            System.assertEquals(true, con.SBQQ__RenewalForecast__c, 'Forecast should be true');
        }
    }

    /**
     * @description test method to verify ContractsRenewalMigrationBatch when no contract numbers are provided.
     * It ensures all matching contracts are processed and updated correctly.
     */
    @isTest
    static void testBatchWithoutContractNumbers() {
        ContractsRenewalMigrationBatch batch = new ContractsRenewalMigrationBatch();

        Test.startTest();
        Id jobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        for (Contract con : getTestContract()) {
            System.assertEquals(true, con.SBQQ__RenewalForecast__c, 'Forecast should be true');
            System.assertEquals(false, con.SBQQ__RenewalQuoted__c, 'Quoted should be false if EndDate > 90 days');
        }
    }
    
    /***********************************************************************************************
    *
    * Getter Methods for Shared Data
    *
    ***********************************************************************************************/
    
    private static List<Contract> getTestContract() {
        return [SELECT SBQQ__RenewalForecast__c,SBQQ__RenewalQuoted__c, EndDate, ContractNumber FROM Contract];
    }

}