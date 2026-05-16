@isTest
public class QuoteTriggerHandlerTestPooja {
	
    
    @isTest
    static void testUpdateSubsidiary_ForAustria() {
        // Arrange
        //Opportunity opp = getOpportunity();
    
        // Create subsidiary Account
        Account acc = new Account(Name = 'Intapp Ireland Limited', Type = AccountConstants.TYPE_PROSPECT);
        insert acc;
        // Create subsidiary Account
        Account acc1 = new Account(Name = 'Intapp Ireland Limited', Type = AccountConstants.TYPE_PROSPECT);
        insert acc1;
        
        // Create test Opportunities
        List<Opportunity> opp = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = acc.Id
            ), 1, 'OpportunityDefaults'
        );
    
        // Create Address using your data factory
        List<Address__c> addrList = TestDataFactory.createAddress(1, false, acc.Id);
        Address__c addr = addrList[0];
    
        // Update the Address to represent Austria
        addr.Status__c = 'Verification Approved';
        addr.Address__CountryCode__s = 'AT';   // ISO code for Austria
        //addr.Country__c = 'Austria';           // Explicit country name (for mapping logic)
        addr.Address__City__s = 'Vienna';
        addr.Address__PostalCode__s = '1010';
        addr.Address__Street__s = 'Mariahilfer Straße';
        addr.Address__StateCode__s = '';
        addr.Account__c=acc.Id;
        insert addr;
        
        addr.Default_Shipping_Address__c = true;
        addr.Country__c = 'Austria';
    	update addr;
        
        System.debug('addr -> ' + addr);
        Map<Id, Address__c> addressMap = new Map<Id, Address__c>(
            [SELECT Id, Country__c, Address__c, Address__CountryCode__s FROM Address__c]
        );
    	System.debug('addressMap -> ' + addressMap);
        
        addr.Country__c = 'Austria'; 
        update addr;
        
        // Update Account to "Verification Approved" to meet logic conditions
        acc.Status__c = 'Verification Approved';
        update acc;
    
        // Create a Quote that triggers the subsidiary mapping
        SBQQ__Quote__c austriaQuote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp[0].Id,
            SBQQ__Account__c = acc.Id,
            Ship_To_Account__c = acc.Id
        );
        insert austriaQuote; // Trigger calls updateSubsidiary internally
    
        // Act
        Test.startTest();
        
        austriaQuote.Ship_To_Address__c = addr.Id;
        austriaQuote.SBQQ__Account__c = acc1.Id;
        update austriaQuote;
        Test.stopTest();
    
        // Assert
        SBQQ__Quote__c result = [
            SELECT Id, Subsidiary__c, Account_Type__c
            FROM SBQQ__Quote__c
            WHERE Id = :austriaQuote.Id
        ];
    
        System.assertEquals(
            '40:Intapp Ireland Limited',
            result.Subsidiary__c,
            'Subsidiary__c should match the subsidiary name for Austria.'
        );
    }
}