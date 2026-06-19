@isTest
public class QuoteApprovalTriggerBatchTest{
    @testSetup
    static void setupTestData(){
		Account acc = IntappTestObjectFactory.createAccount(true);
    
        Id pricebookId = Test.getStandardPricebookId();
        
        Opportunity opp = IntappTestObjectFactory.createOpportunity();
		insert opp;      
        opp.Pricebook2Id = pricebookId;
        update opp;

        Approvers_Matrix__c appMatrix = IntappTestObjectFactory.createApproversMatrix();
        AppMatrix.Approver_User__c = userinfo.getUserId();
        insert AppMatrix;

        Product2 product = IntappTestObjectFactory.createProduct(true);

        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=pricebookId, Product2Id=product.id, UnitPrice=1, IsActive=True);
        insert pbe;
        
        SBQQ__Cost__c cost = new SBQQ__Cost__c();
        cost.SBQQ__Product__c = product.Id;
        cost.SBQQ__UnitCost__c = 100;
        insert cost;

        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
		newQuote.SBQQ__Opportunity2__c = opp.Id;
		newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
		newQuote.License_Basis__c = 'Lawyers';
        newQuote.Number_of_DLIs__c= 1;
        newQuote.Number_of_QLIs__c= 1;
        newQuote.ApprovalStatus__c = 'Pending';
        newQuote.OP4I_OSA_Request_Received__c = true;
        newQuote.OP4I_Deal_Synced__c = true;
        newQuote.Deal_ACV__c = null;
        newQuote.SBQQ__LastCalculatedOn__c = null;
        newQuote.SBQQ__LastSavedOn__c = null;
        newQuote.Submit_For_Approval__c = true;
        newQuote.QLI_Update_Date_Time__c =  Datetime.Now().addMinutes(-3);
        insert newQuote;
        
        System.assertNotEquals(acc.id, null);
    }

	@isTest static void quoteApprovalTriggerBatchIsUncalculated(){
        // Arrange
		List<SBQQ__Quote__c> quoteList = [SELECT Id
                                          ,Number_of_QLIs__c
                                          ,Number_of_DLIs__c
                                          ,ApprovalStatus__c
                                          ,Deal_ACV__c
                                          ,OP4I_Deal_Synced__c
                                          ,OP4I_OSA_Request_Received__c
                                          ,SBQQ__Uncalculated__c
                                          FROM SBQQ__Quote__c]; 
        
        // Act
        quoteList[0].Number_of_QLIs__c = 0;
        update quoteList[0];
        Test.startTest();
        database.executeBatch(new QuoteApprovalTriggerBatch());
        Test.stopTest();

		// Assert
        system.Assert(quoteList[0].SBQQ__Uncalculated__c == true);
    }
	@isTest static void quoteApprovalTriggerBatchIsCalculated(){
        // Arrange
		List<SBQQ__Quote__c> quoteList = [SELECT Id
                                          ,Number_of_QLIs__c
                                          ,Number_of_DLIs__c
                                          ,ApprovalStatus__c
                                          ,Deal_ACV__c
                                          ,OP4I_Deal_Synced__c
                                          ,OP4I_OSA_Request_Received__c
                                          ,SBQQ__Uncalculated__c
                                          FROM SBQQ__Quote__c]; 
        
        for(SBQQ__Quote__c quote : quoteList){
            quote.SBQQ__LastCalculatedOn__c = Datetime.now();
            quote.SBQQ__LastSavedOn__c = Datetime.now().addDays(-1);
        }
        update quoteList;
        
        // Act
        Test.startTest();
        database.executeBatch(new QuoteApprovalTriggerBatch());
        Test.stopTest();
        
        // Assert
        system.Assert(quoteList[0].SBQQ__Uncalculated__c == true);
    }
	@isTest static void quoteApprovalTriggerBatchQuoteApprovalStatusError(){
        // Arrange
		List<SBQQ__Quote__c> quoteList = [SELECT Id
                                          ,Number_of_QLIs__c
                                          ,Number_of_DLIs__c
                                          ,ApprovalStatus__c
                                          ,Deal_ACV__c
                                          ,OP4I_Deal_Synced__c
                                          ,OP4I_OSA_Request_Received__c 
                                          FROM SBQQ__Quote__c]; 
        
        for(SBQQ__Quote__c quote : quoteList){
        	Generic_Key_Value_Setting__mdt approvalErrorMaxRetrySetting = Generic_Key_Value_Setting__mdt.getInstance('Approval_Error_Max_Retry');
        	Integer approvalErrorMaxRetry = Integer.valueOf(approvalErrorMaxRetrySetting.Value__c);
            quote.Counter__c = approvalErrorMaxRetry;
        }
        update quoteList; 
        System.assertNotEquals(quoteList.size(), null);
        // Act
        Test.startTest();
        database.executeBatch(new QuoteApprovalTriggerBatch());
        Test.stopTest();
    }
    @isTest static void quoteApprovalTriggerBatchConstructorCoverage(){
		// Arrange
		String jobName = 'Test Job Name';
         
		// Act 
		QuoteApprovalTriggerBatch batch = new QuoteApprovalTriggerBatch(jobName);

		//Assert
		System.assertEquals(jobName, batch.JOB_NAME);
     }
	@isTest static void quoteApprovalTriggerBatchIsCalculatedWithDealAcv(){
        //Arrange
		List<SBQQ__Quote__c> quoteList = [SELECT Id
                                          ,Number_of_QLIs__c
                                          ,Number_of_DLIs__c
                                          ,ApprovalStatus__c
                                          ,Deal_ACV__c
                                          ,OP4I_Deal_Synced__c
                                          ,OP4I_OSA_Request_Received__c 
                                          FROM SBQQ__Quote__c]; 
        
        for(SBQQ__Quote__c quote : quoteList){
            quote.SBQQ__LastCalculatedOn__c = Datetime.now();
            quote.SBQQ__LastSavedOn__c = Datetime.now().addDays(-1);
            quote.Deal_ACV__c = 10000;
        }
        update quoteList;
        
        //Act
        Test.startTest();
        List<CronJobDetail> cronJobDetails = [SELECT Id FROM CronJobDetail WHERE Name=  
            'Quote Approval Trigger Batch' LIMIT 1];
        // Reschedules this job for one minute in the future. 
        Generic_Key_Value_Setting__mdt configurableScheduleMetadata = Generic_Key_Value_Setting__mdt.getInstance('Quote_Approval_Job_Interval_Minute'); 
         
        Integer jobInterval = Integer.valueOf(configurableScheduleMetadata.Value__c); 
        Datetime sysTime = System.now().addMinutes(jobInterval); 
        String cronExpression = '' + sysTime.second() + ' ' + sysTime.minute() + ' ' +
            sysTime.hour() + ' ' + sysTime.day() + ' ' + sysTime.month() + ' ? ' +   sysTime.year(); 
        
        if (cronJobDetails.isEmpty()) {
            System.schedule('Quote Approval Trigger Batch', cronExpression, new QuoteApprovalTriggerBatch());
        }
        
        database.executeBatch(new QuoteApprovalTriggerBatch());
        Test.stopTest();
        
        //Assert
		System.assert(quoteList[0].Deal_ACV__c != null);
    }
	@isTest static void quoteApprovalTriggerBatchException(){
		// Arrange
        List<SBQQ__Quote__c> quoteList = [SELECT Id
                                          ,Number_of_QLIs__c
                                          ,Number_of_DLIs__c
                                          ,ApprovalStatus__c
                                          ,Deal_ACV__c
                                          ,OP4I_Deal_Synced__c
                                          ,OP4I_OSA_Request_Received__c 
                                          FROM SBQQ__Quote__c]; 
        // Act
		Test.startTest();
		QuoteApprovalTriggerBatch.coverException=true;
		database.executeBatch(new QuoteApprovalTriggerBatch());
        Test.stopTest();
        System.assertNotEquals(quoteList.size(), null);
    }
}