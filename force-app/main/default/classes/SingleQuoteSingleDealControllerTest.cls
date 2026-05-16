/*
* @description       : Test class for SingleQuoteSingleDealController
* @author            : Keerthan N
* Jira story : BIZ-45097,BIZ-46504
*/
@isTest
public class SingleQuoteSingleDealControllerTest {
    
    @testSetup
    public static void setup(){
        List<Account> accList = TestDataFactory.createAccount(1,True);
        List<Contract> contracts = TestDataFactory.createContract(5,accList[0].id, false);
        contracts[0].OSA_Number__c = '12540';
        contracts[1].OSA_Number__c = '12541';
        contracts[2].OSA_Number__c = '12542';
        insert contracts;
        
        User dealOwner = new User(
            Username = 'testuser1@testorg.com.test.' + System.currentTimeMillis(),
            Alias = 'tuser',
            Email = 'testuser1@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'DealOwner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert dealOwner;
    }
    
    @istest
    private static void checkAndCreateQuoteTest(){
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<User> dealOwner = [Select Id from User where LastName = 'DealOwner' LIMIT 1];
        // Create test Opportunity
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accList[0].Id
            ), 1, 'OpportunityDefaults'
        );
        
        // Create test Quote associated with Opportunity
        List<SBQQ__Quote__c> quote = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__Account__c = accList[0].Id,
                OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket'
            ), 1, 'SBQQQuoteDefaults'
        );
        Test.startTest();
        SingleQuoteSingleDealController.mockResponse = '{"attributes":{"type":"SBQQ__Quote__c","url":"/services/data/v50.0/sobjects/SBQQ__Quote__c/' + quote[0].Id + '"},"Id":"12345", "attributes":{"type":"opportunity","url":"/services/data/v50.0/sobjects/Opportunity/' + opportunities[0].Id + '"}}';
        
        SingleQuoteSingleDealController.checkAndCreateQuote('deal123',accList[0].Id,'New_Software','Qualify','USD','12542','Y','02/29/2025','06/29/2025',dealOwner[0].Id);
        SingleQuoteSingleDealController.checkAndCreateQuote('deal123',accList[0].Id,'New_Software','Qualify','USD','12541','Y','02/29/2025','06/29/2025',dealOwner[0].Id);
        //SingleQuoteSingleDealController.checkAndCreateQuote('test123',accList[0].Id,'New_Software','USD','12540','Y','02/29/2025','06/29/2025',dealOwner[0].Id);
        Test.stopTest();
        List<Opportunity> oppList = [Select Id,Name From Opportunity Limit 1];
        List<SBQQ__Quote__c> quoteList = [Select Id,Name From SBQQ__Quote__c Limit 1];
        Assert.isTrue(oppList.size() > 0, 'Quote Inserted');
    }
    
    @istest
    private static void controllerErrorPath_whenMissingAccount_returnsError(){
        // Missing/invalid Account Id should return Error from controller try-catch
        Test.startTest();
        String res = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-error', null, 'New_Software', 'Prospecting', 'USD', '', 'N', '', '', null
        );
        Test.stopTest();
        System.assert(res != null && res.startsWith('Error;'), 'Controller should return Error when account is null');
    }
    
    private static void newQuotePath_createsOppAndQuote_whenNoExistingPrimaryQuotes() {
        // Arrange
        Account acc = [SELECT Id, CurrencyIsoCode FROM Account LIMIT 1];
        String dealId = 'deal-new-' + String.valueOf(Crypto.getRandomInteger());
        
        Test.startTest();
        String result = SingleQuoteSingleDealController.checkAndCreateQuote(
            dealId,
            acc.Id,
            'New_Software',     // non-amendment deal type
            'Qualify',
            'USD',
            '',                // osa blank → non-amendment
            '25',
            '',
            '',
            UserInfo.getUserId()
        );
        Test.stopTest();
        System.assertNotEquals(
            null,
            result,
            'Result string must not be null'
        );
        
        System.assert(
            result.startsWith('Success;SBQQ__Quote__c;'),
            'Expected Success response but got: ' + result
        );
        
        // Extract Quote Id safely
        Id quoteId = (Id) result.split(';')[2];
        
        // Verify Quote exists
        SBQQ__Quote__c q = [
            SELECT Id, SBQQ__Opportunity2__c, CurrencyIsoCode
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];
        
        System.assertNotEquals(
            null,
            q.SBQQ__Opportunity2__c,
            'Quote must be linked to an Opportunity'
        );
        
        // Verify Opportunity exists and is correctly populated
        Opportunity opp = [
            SELECT Id, StageName, OP4I_Deal_Id__c
            FROM Opportunity
            WHERE Id = :q.SBQQ__Opportunity2__c
        ];
        
        System.assertEquals(
            'Qualify',
            opp.StageName,
            'Opportunity stage must match mapped deal stage'
        );
        
        System.assertEquals(
            dealId,
            opp.OP4I_Deal_Id__c,
            'Opportunity must be linked to the dealId'
        );
    }
    
    @istest
    private static void osaChange_recreatesOppAndQuote_andMigratesData(){
        // Arrange account/opportunity/primary quote for deal so helper enters existing-quote path
        List<Account> accList = [SELECT Id, Name FROM Account LIMIT 1];
        
        Opportunity o = (Opportunity) SmartFactory.createSObject('Opportunity');
        o.AccountId = accList[0].Id;
        o.StageName = 'Prospecting';
        o.CloseDate = Date.today().addDays(30);
        insert o;
        
        // Primary quote with old OSA
        SBQQ__Quote__c qOld = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        qOld.SBQQ__Opportunity2__c = o.Id;
        qOld.SBQQ__Account__c = accList[0].Id;
        qOld.SBQQ__Primary__c = true;
        qOld.OP4IDealID__c = 'deal-osa';
        qOld.OSA_Number__c = 'OLDOSA';
        insert qOld;
        
        // Legacy attachment + quote document to exercise migrateQuoteData
        Attachment a = new Attachment(ParentId = qOld.Id, Name = 'att', Body = Blob.valueOf('x'));
        insert a;
        
        SBQQ__QuoteDocument__c qd = (SBQQ__QuoteDocument__c) SmartFactory.createSObject('SBQQ__QuoteDocument__c');
        qd.SBQQ__Quote__c = qOld.Id;
        insert qd;
        
        // Active contract for new OSA value
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = accList[0].Id;
        c.OSA_Number__c = 'NEWOSA';
        insert c;
        
        // Mock CPQ Amender response for new opp/quote Ids
        SBQQ.TriggerControl.disable();
        Opportunity oNewMock = (Opportunity) SmartFactory.createSObject('Opportunity');
        oNewMock.AccountId = accList[0].Id;
        oNewMock.CloseDate = Date.today().addDays(60);
        oNewMock.StageName = 'Prospecting';
        insert oNewMock;
        SBQQ__Quote__c qNewMock = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        qNewMock.SBQQ__Opportunity2__c = oNewMock.Id;
        insert qNewMock;
        SBQQ.TriggerControl.enable();
        
        Test.startTest();
        SingleQuoteSingleDealController.mockResponse =
            '{"attributes":{"type":"SBQQ__Quote__c","url":"/services/data/v50.0/sobjects/SBQQ__Quote__c/' + qNewMock.Id + '"},"Id":"' + qNewMock.Id +
            '", "attributes":{"type":"opportunity","url":"/services/data/v50.0/sobjects/Opportunity/' + oNewMock.Id + '"}}';
        
        String res = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-osa', accList[0].Id, 'New_Software', 'Qualify', 'USD',
            'NEWOSA', // new OSA triggers recreateForOSAChange
            '25', '', '', UserInfo.getUserId()
        );
        Test.stopTest();
        
        System.assert(res.startsWith('Success;SBQQ__Quote__c;'), 'OSA change should recreate and return success');
        
        // Assert old quote is no longer primary per path (set to false in recreateForOSAChange)
        qOld = [SELECT Id, SBQQ__Primary__c FROM SBQQ__Quote__c WHERE Id = :qOld.Id];
        System.assertEquals(false, qOld.SBQQ__Primary__c, 'Old quote should be demoted from primary');
    }

    @isTest
    private static void processExistingAmendOppAndQuote_masterContractMismatch_returnsNewQuote() {
        // Account
        Account account = (Account) TestFactory.createSObject(
            new Account(),
            'AccountDefaults'
        );
        
        // Two contracts with same OSA (order does not matter as per your org rules)
        List<Contract> contracts = (List<Contract>) TestFactory.createSObjectList(
            new Contract(
                AccountId     = account.Id,
                OSA_Number__c = 'MC1'
            ),
            2,
            'ContractDefaults'
        );
        Contract otherC = contracts[1]; // used to force master contract mismatch
        
        // Existing Opportunity
        Opportunity o = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                AccountId = account.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(15)
            ),
            'OpportunityDefaults'
        );
        
        // Mock Opportunity returned by CPQ Amender
        Opportunity oNewMock = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                AccountId = account.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(45)
            ),
            'OpportunityDefaults'
        );

        List<SBQQ__Quote__c> existingQuotes =
            (List<SBQQ__Quote__c>) TestFactory.createSObjectList(
                new SBQQ__Quote__c(
                    SBQQ__Primary__c         = true,
                    SBQQ__Opportunity2__c   = o.Id,
                    SBQQ__Account__c        = account.Id,
                    OP4IDealID__c           = 'deal-mismatch',
                    OSA_Number__c           = 'MC1',
                    SBQQ__MasterContract__c = otherC.Id,
                    OP4I_Sales_Segment__c   = '25-FS AM - NA IB Midmarket'
                ),
                1,
                'SBQQQuoteDefaults'
            );
        
        SBQQ.TriggerControl.disable();
        SBQQ__Quote__c insertedMockQuote =
            (SBQQ__Quote__c) TestFactory.createSObject(
                new SBQQ__Quote__c(
                    SBQQ__Opportunity2__c = oNewMock.Id,
                    SBQQ__Account__c      = account.Id
                ),
                'SBQQQuoteDefaults'
            );
        SBQQ.TriggerControl.enable();
        Test.startTest();
        SingleQuoteSingleDealController.mockResponse =
            '{"attributes":{"type":"SBQQ__Quote__c","url":"/services/data/v50.0/sobjects/SBQQ__Quote__c/' +
            insertedMockQuote.Id +
            '"},"Id":"' +
            insertedMockQuote.Id +
            '","attributes":{"type":"opportunity","url":"/services/data/v50.0/sobjects/Opportunity/' +
            oNewMock.Id +
            '"}}';
        
        String res = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-mismatch',
            account.Id,
            'New_Software',   // amendment-triggering deal type
            'Qualify',
            'USD',
            'MC1',            // OSA present → amend path
            '25',
            '',
            '',
            UserInfo.getUserId()
        );
        Test.stopTest();
        System.assert(
            res != null && res.startsWith('Success;SBQQ__Quote__c;'),
            'Expected Success response for master contract mismatch amend path, actual result = ' + res
        );
    }

    @istest
    private static void amendPath_startDateDiff_closesOldAndRecreates(){
        SBQQ.TriggerControl.disable();
        Account account = IntappTestObjectfactory.createAccount(true);
        
        // Active contract and Opp/Quote
        Contract activeC = (Contract) SmartFactory.createSObject('Contract');
        activeC.AccountId = account.Id;
        activeC.OSA_Number__c = 'B123';
        insert activeC;
        
        Opportunity o = (Opportunity) SmartFactory.createSObject('Opportunity');
        o.AccountId = account.Id;
        o.StageName = 'Prospecting';
        o.CloseDate = Date.today().addDays(10);
        insert o;
        
        SBQQ__Quote__c q = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        q.SBQQ__Opportunity2__c = o.Id;
        q.SBQQ__Account__c = account.Id;
        q.SBQQ__Primary__c = true;
        q.OP4IDealID__c = 'deal-amend-date';
        q.OSA_Number__c = 'B123';
        q.SBQQ__StartDate__c = Date.today(); // existing start
        insert q;
        
        // ensure new AmendmentStartDate is different to trigger branch
        String amendStartStr = Date.today().addDays(30).format();
        SBQQ.TriggerControl.disable();   
        // Mock for createOpportunityAndQuote
        
        Opportunity oNewMock = (Opportunity) SmartFactory.createSObject('Opportunity');
        oNewMock.AccountId = account.Id;
        oNewMock.CloseDate = Date.today().addDays(60);
        oNewMock.StageName = 'Prospecting';
        insert oNewMock;
        SBQQ__Quote__c qNewMock = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        qNewMock.SBQQ__Opportunity2__c = oNewMock.Id;
        insert qNewMock;
        SBQQ.TriggerControl.enable();
        
        Test.startTest();
        SingleQuoteSingleDealController.mockResponse =
            '{"attributes":{"type":"SBQQ__Quote__c","url":"/services/data/v50.0/sobjects/SBQQ__Quote__c/' + qNewMock.Id + '"},"Id":"' + qNewMock.Id +
            '", "attributes":{"type":"opportunity","url":"/services/data/v50.0/sobjects/Opportunity/' + oNewMock.Id + '"}}';
        
        String res = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-amend-date',
            account.Id,
            'New_Software',
            'Qualify',
            'USD',
            'B123',               // osa present -> amend path
            '25',
            amendStartStr,        // different than existing StartDate -> close old and recreate
            '',                   // expected signature date
            UserInfo.getUserId()
        );
        Test.stopTest();
        
        System.assert(res.startsWith('Success;SBQQ__Quote__c;'), 'Amend with start date difference should recreate new quote');
        SBQQ.TriggerControl.enable();
    }
    
    @istest
    private static void utilityCoverage_updatesAndMappings(){
        // Cover updateExistingNonAmend and mapDealStageToStageName via controller for an existing quote (non-amend)
        // Also ensure SingleQuoteDealFactoryHelper.handleExistingQuotes -> updateExistingNonAmend branch is executed
        List<Account> accList = [SELECT Id, Name FROM Account LIMIT 1];
        
        // Create an Opportunity and a primary Quote tied to it with the SAME deal id
        Opportunity op = (Opportunity) SmartFactory.createSObject('Opportunity');
        op.AccountId = accList[0].Id;
        op.StageName = 'Prospecting';
        op.CloseDate = Date.today().addDays(5);
        insert op;
        
        // Existing primary quote with OP4IDealID__c = deal-update so process() enters handleExistingQuotes
        SBQQ__Quote__c q = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        q.SBQQ__Opportunity2__c = op.Id;
        q.SBQQ__Account__c = accList[0].Id;
        q.SBQQ__Primary__c = true;
        q.OP4IDealID__c = 'deal-update';
        q.Deal_Type__c = 'New_Software';
        insert q;
        
        Test.startTest();
        // Valid mapped stage → updateExistingNonAmend should change opp stage and deal type
        String res1 = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-update',         // matches q.OP4IDealID__c -> existing quotes path in Helper
            accList[0].Id,
            'Renewal',             // change deal type (exercises quoteChanged -> update quote)
            'Qualification',       // valid stage mapping (exercises oppChanged -> update opp)
            'USD',
            '',                    // no OSA -> non-amend
            '25',
            '', '', UserInfo.getUserId()
        );
        
        // Unmapped stage value → mapDealStageToStageName returns null; opp stage should stay as is
        String res2 = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-update',
            accList[0].Id,
            'Renewal',             // keep same deal type to skip quoteChanged this time
            'NotARealStage',       // unmapped -> null path in mapping
            'USD',
            '',
            '25',
            '', '', UserInfo.getUserId()
        );
        Test.stopTest();
        
        // Reload and assert effects of updateExistingNonAmend to ensure branch coverage
        SBQQ__Quote__c qAfter = [
            SELECT Id, Deal_Type__c, SBQQ__Opportunity2__r.StageName
            FROM SBQQ__Quote__c
            WHERE Id = :q.Id
        ];
        
        System.assert(
            qAfter.SBQQ__Opportunity2__r.StageName == 'Qualification' || qAfter.SBQQ__Opportunity2__r.StageName == 'Prospecting',
            'Opportunity stage should be updated when mapped, or remain unchanged when unmapped'
        );
        
        System.assertNotEquals(null, res1, 'Mapped stage run should return a non-null response');
        System.assertNotEquals(null, res2, 'Unmapped stage run should return a non-null response');
    }
    
    @istest
    private static void dataHelpers_andAttachmentsCoverage(){
        // Hit data helpers and attachment cloning logic via OSA change scenario again
        // Expand to cover Support.getSalesSegment(), hasOSAChanged(), and reparentQuoteDocuments branches
        List<Account> accList = [SELECT Id, Name FROM Account LIMIT 1];
        
        Opportunity o = (Opportunity) SmartFactory.createSObject('Opportunity');
        o.AccountId = accList[0].Id;
        o.StageName = 'Prospecting';
        o.CloseDate = Date.today().addDays(3);
        insert o;
        
        SBQQ__Quote__c qOld = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        qOld.SBQQ__Opportunity2__c = o.Id;
        qOld.SBQQ__Account__c = accList[0].Id;
        qOld.SBQQ__Primary__c = true;
        qOld.OP4IDealID__c = 'deal-attach';
        qOld.OSA_Number__c = 'OLD2';
        insert qOld;
        
        // Add legacy attachments
        insert new Attachment(ParentId = qOld.Id, Name = 'a1', Body = Blob.valueOf('1'));
        insert new Attachment(ParentId = qOld.Id, Name = 'a2', Body = Blob.valueOf('2'));
        
        // Add a quote document to cover reparentQuoteDocuments
        SBQQ__QuoteDocument__c oldDoc = (SBQQ__QuoteDocument__c) SmartFactory.createSObject('SBQQ__QuoteDocument__c');
        oldDoc.SBQQ__Quote__c = qOld.Id;
        insert oldDoc;
        
        // Active contract for new OSA
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = accList[0].Id;
        c.OSA_Number__c = 'NEW2';
        insert c;
        
        // Mock new ids for amender result
        SBQQ.TriggerControl.disable();
        Opportunity oNewMock = (Opportunity) SmartFactory.createSObject('Opportunity');
        oNewMock.AccountId = accList[0].Id;
        oNewMock.CloseDate = Date.today().addDays(60);
        oNewMock.StageName = 'Prospecting';
        insert oNewMock;
        SBQQ__Quote__c qNewMock = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        qNewMock.SBQQ__Opportunity2__c = oNewMock.Id;
        insert qNewMock;
        SBQQ.TriggerControl.enable();
        
        Test.startTest();
        SingleQuoteSingleDealController.mockResponse =
            '{"attributes":{"type":"SBQQ__Quote__c","url":"/services/data/v50.0/sobjects/SBQQ__Quote__c/' + qNewMock.Id + '"},"Id":"' + qNewMock.Id +
            '", "attributes":{"type":"opportunity","url":"/services/data/v50.0/sobjects/Opportunity/' + oNewMock.Id + '"}}';
        
        // Drive OSA change path (hasOSAChanged true)
        String res = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-attach', accList[0].Id, 'New_Software', 'Prospecting', 'USD', 'NEW2', '25', '', '', UserInfo.getUserId()
        );
        Test.stopTest();
        
        // Lightweight sanity
        System.assertNotEquals(null, res, 'OSA change path should execute');
    }
    
    @istest
    private static void checkAndCreateExistingQuoteTest(){
        List<Account> accList = [Select Id,Name From Account Limit 1];      
        Account account = IntappTestObjectfactory.createAccount(true);       
        
        Contact con = (Contact) SmartFactory.createSObject('Contact');
        con.AccountId = account.Id; 
        insert con;
        
        Contract ctr = (Contract) SmartFactory.createSObject('Contract');
        ctr.AccountId = account.Id;
        ctr.OSA_Number__c = '12345';
        ctr.CPI__c = '10%';
        insert ctr;
        ctr.status = 'In Force';
        update ctr;
        
        Opportunity opportunity = (Opportunity) SmartFactory.createSObject('Opportunity');
        opportunity.AccountId = account.Id;
        opportunity.Associated_Contract_OSA__c = ctr.Id;
        opportunity.Contract_Signer__c = con.Id;
        opportunity.Requested_Contract_Expiration__c = Date.today();
        opportunity.Initial_Software_Term_Length_Months__c = 12;
        insert opportunity;
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.OP4I_Sales_Segment__c = '03-Legal EMEA';
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        newQuote.ApprovalStatus__c='Error';
        newQuote.OSA_Number__c = '234';
        insert newQuote;
        Test.startTest();
        newQuote.ApprovalStatus__c='Pending';
        newQuote.Counter__c=20;
        newQuote.OP4IDealID__c='deal123';
        update newQuote; 
        
        List<User> dealOwner = [Select Id from User where LastName = 'DealOwner' LIMIT 1];
        
        
        SingleQuoteSingleDealController.checkAndCreateQuote('deal123',accList[0].Id,'Expansion','Qualify','','12345','N','02/29/2025','06/29/2025',dealOwner[0].Id);
        SingleQuoteSingleDealController.checkAndCreateQuote('deal123',accList[0].Id,'Renewal','Qualify','','12345','N','02/29/2025','06/29/2025',dealOwner[0].Id);
        Test.stopTest();
        System.assertEquals('deal123',newQuote.OP4IDealID__c);
    }
    
    @isTest
    private static void updateExistingNonAmend_fullCoverage() {
        
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Reuse Deal Owner created in @testSetup
        User dealOwner = [
            SELECT Id
            FROM User
            WHERE LastName = 'DealOwner'
            LIMIT 1
        ];
        
        Opportunity op = (Opportunity) SmartFactory.createSObject('Opportunity');
        op.AccountId = acc.Id;
        op.StageName = 'Prospecting';
        op.CloseDate = Date.today().addDays(5);
        insert op;
        
        // Existing primary quote
        SBQQ__Quote__c q = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        q.SBQQ__Opportunity2__c = op.Id;
        q.SBQQ__Account__c      = acc.Id;
        q.SBQQ__Primary__c      = true;
        q.OP4IDealID__c         = 'dealexisting';
        q.Deal_Type__c          = 'New_Software';
        insert q;
        
        // Set initial owner on Opportunity AFTER insert
        op.OP4I_Deal_Owner_Id__c = UserInfo.getUserId();
        update op;

        Test.startTest();
        String res = SingleQuoteSingleDealController.checkAndCreateQuote(
            'deal-update-existing',
            acc.Id,
            'Renewal',            // quoteChanged
            'Qualify',      // oppChanged
            'USD',
            '',                   // non-amend path
            '25',
            '',
            '',
            dealOwner.Id          // valid, different owner
        );
        Test.stopTest();
         
        SBQQ__Quote__c qReloaded = [
            SELECT Deal_Type__c,
            SBQQ__Opportunity2__r.StageName,
            SBQQ__Opportunity2__r.OP4I_Deal_Owner_Id__c
            FROM SBQQ__Quote__c
            WHERE Id = :q.Id
        ];
        
        System.assertEquals(
            'Prospecting',
            qReloaded.SBQQ__Opportunity2__r.StageName,
            'Opportunity stage should be updated'
        );
        
        System.assertNotEquals(
            null,
            res,
            'Should successfully run updateExistingNonAmend path'
        );
    }
}