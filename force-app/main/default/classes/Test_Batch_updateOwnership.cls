@isTest
private class Test_Batch_updateOwnership {

    static testmethod void testDC() {
    
    // Create test accounts to be updated
    // by the batch job.
    
        List<Account> accList = new List<Account>();
        for (Integer i=0;i<200;i++) {
            Account m = new Account(Name = 'Account ' + i, Type = 'DealCloud Customer');
            accList.add(m);
        }
        insert accList;
        
        Test.startTest();
            Batch_updateOwnership_DC c = new Batch_updateOwnership_DC('');
            Database.executeBatch(c);
        Test.stopTest();
        
        // Verify accounts updated
        Account[] accUpdatedList = [SELECT Id,Name,Dealcloud__c FROM Account];
        System.assertEquals('DealCloud', accUpdatedList[0].DealCloud__c);
    }
    
    static testmethod void testnonDC() {
    
    // Create test accounts to be updated
    // by the batch job.
    
        List<Account> accList = new List<Account>();
        for (Integer i=0;i<1;i++) {
            Account m = new Account(Name = 'Account ' + i, Type = 'Customer');
            accList.add(m);
        }
        insert accList;
        
        List<Product_Ownership_Detail__c> podList = new List<Product_Ownership_Detail__c>();
        
        Product_line__c experience = new Product_Line__c();
        experience.Name = 'Experience - Cloud';
        experience.Simple_Product_Line__c = 'Experience';
        experience.Active__c = true;
        insert experience;
        
        Product_line__c crm = new Product_Line__c();
        crm.Name = 'CRM - Cloud';
        crm.Simple_Product_Line__c = 'CRM';
        crm.Active__c = true;
        insert crm;
        
        Product_line__c legalKey = new Product_Line__c();
        legalKey.Name = 'LegalKey - Legacy';
        legalKey.Simple_Product_Line__c = 'TFG - Other';
        legalKey.Active__c = true;
        insert legalKey;
        
        License_Basis__c crmcloud = new License_Basis__c();
        crmcloud.Name = 'CRM - Cloud';
        crmcloud.Product_Line__c = crm.id;
        crmcloud.Highest_Package__c = true;
        insert crmcloud;
        
        for(Account a: accList){
            Product_Ownership_Detail__c podexperience = new Product_Ownership_Detail__c();
            podexperience.Product_line_link__c = legalKey.Id;
            podexperience.Account_Name__c = a.Id;
            podexperience.Status__c = 'Own it - Trial';
            podexperience.Support_Level__c = 'Standard (Silver)';
            podList.add(podexperience);
            
            /*
            Product_Ownership_Detail__c pod_crm = new Product_Ownership_Detail__c();
            pod_crm.Product_line_link__c = crm.Id;
            pod_crm.Account_Name__c = a.Id;
            pod_crm.Status__c = 'Own it';
            pod_crm.Support_Level__c = 'Standard (Silver)';
            pod_crm.License_basis_link__c = crmcloud.id;
            
            podList.add(pod_crm);
			*/
        }
        
        insert podList;
        
        Test.startTest();
            Batch_updateOwnership_nonDC c = new Batch_updateOwnership_nonDC('');
            Database.executeBatch(c);
        Test.stopTest();
        
            // Verify accounts updated
        Account[] accUpdatedList = [SELECT Id,Name,Experience__c,TFG_Other__c, LegalKey__c FROM Account];
        System.assertEquals('LegalKey - On Prem', accUpdatedList[0].LegalKey__c);
        
    }
    
    static testmethod void testnonDC2() {
        List<Account> accList = new List<Account>();
        List<Product_Ownership_Detail__c> podList = new List<Product_Ownership_Detail__c>();
        
        for (Integer i=0;i<1;i++) {
            Account m = new Account(Name = 'Account ' + i, Type = 'Customer', TFG_Other__c = 'LegalKey - Legacy');
            accList.add(m);
        }
        insert accList;
        
        Product_line__c legalKey = new Product_Line__c();
        legalKey.Name = 'LegalKey - Legacy';
        legalKey.Simple_Product_Line__c = 'TFG - Other';
        legalKey.Active__c = true;
        insert legalKey;
        
        for(Account a: accList){
            Product_Ownership_Detail__c podexperience = new Product_Ownership_Detail__c();
            podexperience.Product_line_link__c = legalKey.Id;
            podexperience.Account_Name__c = a.Id;
            podexperience.Status__c = 'Lapsed';
            podexperience.Support_Level__c = 'Standard (Silver)';
            podList.add(podexperience);
        }
        
        insert podList;
        
        Test.startTest();
            Batch_updateOwnership_nonDC c = new Batch_updateOwnership_nonDC('');
            Database.executeBatch(c);
        System.assertEquals('Standard (Silver)', podList[0].Support_Level__c);
        Test.stopTest();
    }
    static testmethod void testnonDC3() {
        List<Account> accList = new List<Account>();
        List<Product_Ownership_Detail__c> podList = new List<Product_Ownership_Detail__c>();
        
        for (Integer i=0;i<1;i++) {
            Account m = new Account(Name = 'Account ' + i, Type = 'Customer', TFG_Other__c = 'LegalKey - Legacy');
            accList.add(m);
        }
        insert accList;
        
        Product_line__c legalKey = new Product_Line__c();
        legalKey.Name = 'LegalKey - Legacy';
        legalKey.Simple_Product_Line__c = 'CRM';
        legalKey.Active__c = true;
        insert legalKey;
        
         Product_line__c crm = new Product_Line__c();
        crm.Name = 'CRM - Cloud';
        crm.Simple_Product_Line__c = 'CRM';
        crm.Active__c = true;
        insert crm;
        
        License_Basis__c crmcloud = new License_Basis__c();
        crmcloud.Name = 'CRM - Cloud';
        crmcloud.Product_Line__c = legalKey.id;
        crmcloud.Highest_Package__c = true;
        
        insert crmcloud;
        
        for(Account a: accList){
            Product_Ownership_Detail__c podexperience = new Product_Ownership_Detail__c();
            podexperience.Product_line_link__c = legalKey.Id;
            podexperience.Account_Name__c = a.Id;
            podexperience.Status__c = 'Entitled';
            podexperience.Support_Level__c = 'Standard (Silver)';
            podexperience.License_basis_link__c=crmcloud.Id;
            podList.add(podexperience);
        }
        
        insert podList;
        
        Test.startTest();
            Batch_updateOwnership_nonDC c = new Batch_updateOwnership_nonDC('');
            Database.executeBatch(c);
         System.assertEquals('Standard (Silver)', podList[0].Support_Level__c);
        Test.stopTest();
    }
    
    static testmethod void testschedulerDC(){
        List<Account> accList = new List<Account>();
        for (Integer i=0;i<200;i++) {
            Account m = new Account(Name = 'Account ' + i, Type = 'DealCloud Customer');
            accList.add(m);
        }
        insert accList;
        String cronEXP = '0 0 0 15 3 ? *';
        String jobId = System.schedule('ScheduleApexClassTest',  cronEXP, new Batch_updateOwnership_DC_scheduler());
        Account[] accUpdatedList = [SELECT Id,Type FROM Account];
        System.assertEquals('DealCloud Customer', accUpdatedList[0].Type);
    }
    
    static testmethod void testschedulernonDC(){
        List<Account> accList = new List<Account>();
        for (Integer i=0;i<1;i++) {
            Account m = new Account(Name = 'Account ' + i, Type = 'Customer');
            accList.add(m);
        }
        insert accList;
        
        List<Product_Ownership_Detail__c> podList = new List<Product_Ownership_Detail__c>();
        
        Product_line__c experience = new Product_Line__c();
        experience.Name = 'Experience - Cloud';
        experience.Simple_Product_Line__c = 'Experience';
        experience.Active__c = true;
        insert experience;
        
        Product_line__c crm = new Product_Line__c();
        crm.Name = 'CRM - Cloud';
        crm.Simple_Product_Line__c = 'CRM';
        crm.Active__c = true;
        insert crm;
        
        Product_line__c legalKey = new Product_Line__c();
        legalKey.Name = 'LegalKey - Legacy';
        legalKey.Simple_Product_Line__c = 'TFG - Other';
        legalKey.Active__c = true;
        insert legalKey;
        
        License_Basis__c crmcloud = new License_Basis__c();
        crmcloud.Name = 'CRM - Cloud';
        crmcloud.Product_Line__c = crm.id;
        crmcloud.Highest_Package__c = true;
        insert crmcloud;
        
        for(Account a: accList){
            Product_Ownership_Detail__c podexperience = new Product_Ownership_Detail__c();
            podexperience.Product_line_link__c = legalKey.Id;
            podexperience.Account_Name__c = a.Id;
            podexperience.Status__c = 'Own it - Trial';
            podexperience.Support_Level__c = 'Standard (Silver)';
            podList.add(podexperience);
            
            /*
            Product_Ownership_Detail__c pod_crm = new Product_Ownership_Detail__c();
            pod_crm.Product_line_link__c = crm.Id;
            pod_crm.Account_Name__c = a.Id;
            pod_crm.Status__c = 'Own it';
            pod_crm.Support_Level__c = 'Standard (Silver)';
            pod_crm.License_basis_link__c = crmcloud.id;
            
            podList.add(pod_crm);
			*/
        }
        
        insert podList;

        String cronEXP = '0 0 0 15 3 ? *';
        String jobId = System.schedule('ScheduleApexClassTest',  cronEXP, new Batch_updateOwnership_nonDC_scheduler());
        Account[] accUpdatedList = [SELECT Id,Type FROM Account];
        System.assertEquals('Customer', accUpdatedList[0].Type);
    }
}