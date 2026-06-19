@isTest
private class sObjectRemoteTEST{

    //Test methods for sObjectRemote class
    //Query
    private static testMethod void queryTest(){
        String query = 'select Id from User limit 1';

        //Start test
        Test.startTest();
        sObjectRemote.QueryResult qr = sObjectRemote.query(query);
        Test.stopTest();

        //Assert records were returned
        system.assert(qr.sObjects.size() > 0);
    }

    //Update
    private static testMethod void updateTest(){
        //Create and insert 200 accounts
        List<sObject> accts = createSObjects(true);

        //Change the name field to something very unique
        for(sObject so : accts){
            so.put('Name','sObjectRemoteUpdateTEST4320930@#$#$#$#!@$Afasdfa3r');
        }

        //Start test and update records
        Test.startTest();
        sObjectRemote.updateSObjects(accts,new Map<String,String>());
        Test.stopTest();

        //Assert all accounts were updated
        List<Account> acctsAfterUpdate = [select Id from Account where Name = 'sObjectRemoteUpdateTEST4320930@#$#$#$#!@$Afasdfa3r'];
        system.assert(acctsAfterUpdate.size() > 0);
    }

    //Delete
    private static testMethod void deleteTest(){
        //Create and insert 200 accounts
        List<sObject> accts = createSObjects(true);

        //Start Test and delete records
        Test.startTest();
        sObjectRemote.deleteSObjects(accts,new Map<String,String>());
        Test.stopTest();

        //Assert all accounts were deleted
        List<Account> acctsAfterUpdate = [select Id from Account where Id IN :accts];
        system.assert(acctsAfterUpdate.size() == 0);
    }

    //DML Options
    private static testMethod void dmlOptionsTest(){
        //Build a map representing every kind of dml option that can be set
        Map<String,String> dmlOptions = new Map<String,String>();

        dmlOptions.put('allowfieldtruncation','true');
        dmlOptions.put('assignmentruleheader','{assignmentruleid=1234,usedefaultrule=true}');
        dmlOptions.put('emailheader','{triggerautoresponseemail=true,triggerotheremail=true,triggeruseremail=true}');
        dmlOptions.put('localeoptions','en_us');
        dmlOptions.put('optallornone','false');

        //Build DMLOptions object based on map
        Test.startTest();
        Database.DMLOptions dmo = sObjectRemote.setDMLoptions(dmlOptions);
        Test.stopTest();

        //Assert DML options where set correctly
        system.assertEquals(true,dmo.allowFieldTruncation);
        system.assertEquals('1234',dmo.assignmentRuleHeader.assignmentRuleID);
        system.assertEquals(true,dmo.assignmentRuleHeader.useDefaultRule);
        system.assertEquals(true,dmo.emailHeader.triggerAutoResponseEmail);
        system.assertEquals(true,dmo.emailheader.triggerOtherEmail);
        system.assertEquals(true,dmo.emailHeader.triggerUserEmail);
        system.assertEquals('en_us',dmo.localeOptions);
        system.assertEquals(false,dmo.optAllOrNone);
    }

    //Test Utility Method to create sObjects
    private static List<Account> createSObjects(Boolean doInsert){
        List<Account> accts = new List<Account>();

        for(Integer i = 0; i < 2; i++){
            accts.add(IntappTestObjectFactory.createAccount(true)); //Add required fields per org to make sure inserts pass validation
        }   
        
        System.assertNotEquals(accts, null);
        return accts; 
        
    }
}