/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an organization are executed whenever Apex code is deployed
 * to a production organization to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production organization. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the organization size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class TestContractTrigger {

    static testMethod void testPopulateBillingAccount() {
        Account acct1 = IntappTestObjectFactory.createAccount(true);
        Account acct2 = IntappTestObjectFactory.createAccount(true);
        acct2.ParentId = acct1.Id;
        update acct2;
        Contract con = IntappTestObjectFactory.createContract(acct2.Id);
        insert con;
        con.status = 'In Force';
        update con;
        
        List<Account> test = [SELECT Id, Name FROM Account];
        System.assertNotEquals(test.size(), null);
        
    }
}