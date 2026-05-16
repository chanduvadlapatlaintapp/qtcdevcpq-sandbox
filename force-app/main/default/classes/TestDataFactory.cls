/**
* @description       : 
* @author            : Keshav Das
* @group             : 
* @last modified on  : 07-07-2023
* @last modified by  : Keshav Das
* Modifications Log
* Ver   Date         Author         Modification
* 1.0   07-07-2023   Keshav Das   Initial Version
**/
@isTest
public without sharing class TestDataFactory 
{
    public static List<Account> createAccount(Integer noOfAccounts,Boolean doInsert)
    {
        List<Account> accList= new List<Account>();
        for(Integer i=0;i<noOfAccounts;i++) {
            Account acc = new Account();
            acc.Name='Test Account'+i;
            acc.Type='Prospect';
            acc.currencyIsoCode = 'USD';
            accList.add(acc);
        }
        if(doInsert){
            insert accList;
        }   
        return accList;
    }
    
    public static List<AVA_MAPPER__Entity_Use_code__c> createEntityUseCode(Integer noOfCodes,Boolean doInsert)
    {
        List<AVA_MAPPER__Entity_Use_code__c> avaList= new List<AVA_MAPPER__Entity_Use_code__c>();
        for(Integer i=0; i < noOfCodes ;i++) {
            AVA_MAPPER__Entity_Use_code__c ava = new AVA_MAPPER__Entity_Use_code__c();
            ava.Name=''+i;
            ava.AVA_MAPPER__Description__c='Description '+i;
            avaList.add(ava);
        }
        if(doInsert){
            insert avaList;
        }   
        return avaList;
    }
    /**
* ***********************************************************
* This method is test data for create Sales User object
* ***********************************************************
*/
    public static List<User> createSalesUser(Integer noOfUser,Boolean doInsert)
        
    {
        ID profileID = [ Select id from Profile where name ='System Administrator'].id;
        String dateString = String.valueof(Datetime.now()).replace(' ','').replace(':','').replace('-','');
        Integer randomInt = Integer.valueOf(math.rint(math.random()*1000000));
        String nickName =  dateString + randomInt+String.valueOf(System.currentTimeMillis());
        String uniqueEmail = nickName +
            '@' + 'kpmg.com';         
        List<User> userList= new List<User>();
        
        for(Integer i=0;i<noOfUser;i++) {
            User userObj = new User( email=i+uniqueEmail, profileid = profileID, UserName=i+uniqueEmail, alias='tuser', CommunityNickName=i+nickName,
                                    TimeZoneSidKey='America/New_York', LocaleSidKey='en_US', EmailEncodingKey='ISO-8859-1',
                                    LanguageLocaleKey='en_US', FirstName = 'User', LastName = 'Test',isActive=true);
            userList.add(userObj);
        }
        
        if(doInsert)
        {
            insert userList ;
        }
        return userList ;          
    }
    
    public static List<Opportunity> createOppty(Integer noOfOpportunities,String accId,Boolean doInsert){
        List<Opportunity> oppList= new List<Opportunity>();
        Id pricebookId = Test.getStandardPricebookId();
        for(Integer i=0;i<noOfOpportunities;i++) {            
            Opportunity opp = new Opportunity();
            opp.Name='Test Opportunity'+i;
            opp.StageName='Propose';
            opp.CloseDate=system.today()+60;    
            opp.AccountId=accId;
            opp.Pricebook2Id = pricebookId;
            oppList.add(opp);
        }
        if(doInsert){
            insert oppList;
        }   
        return oppList;
    }
    
    public static List<SBQQ__Quote__c> createQuote(Integer noOfQuotes,String oppId,Boolean doInsert){
        List<SBQQ__Quote__c> quoteList= new List<SBQQ__Quote__c>();
        for(Integer i=0;i<noOfQuotes;i++) {
            SBQQ__Quote__c qt = new SBQQ__Quote__c();
            //qt.Name='Test Quote'+i;
            qt.Quote_Stage__c = System.Label.Configure_Products;
            qt.OP4I_Status__c = 'Pending';
            qt.SBQQ__StartDate__c = System.Today()+10;
            //qt.SBQQ__Opportunity2__c=oppId;
            //qt.SBQQ__Primary__c = True;
            qt.SBQQ__EndDate__c = System.Today()+375;
            qt.OP4IDealID__c = '1234'+String.ValueOf(i);
            qt.CurrencyIsoCode = 'USD';
            qt.Quote_Stage__c = System.Label.Configure_Products;
            quoteList.add(qt);
        }
        if(doInsert){
            insert quoteList;
        }   
        return quoteList;
    }
    
    public static List<Product2> createProduct(Integer noOfProducts,Boolean doInsert){
        List<Product2> productList= new List<Product2>();
        for(Integer i=0;i<noOfProducts;i++) {
            Product2 pd = new Product2();
            pd.Name='Intapp Risk & Compliance';
            pd.ProductCode='BU-01670-2';
            pd.IsActive=true;
            //pd.Income_Account__c = '0003 Sales : Direct Sales';
            //pd.Deferred_Revenue_Account__c = '2301 Deferred Revenue : Deferred Revenue - Clearing Account';
            //pd.Revenue_Recognition_Rule__c = 'Default One-Time Direct Posting';
            //pd.Rev_Rec_Forecast_Rule__c = 'Default One-Time Direct Posting';
            //pd.Create_Revenue_Plans_On__c = 'Billing';
            //pd.Item_Revenue_Category__c = 'Deal Cloud';
            productList.add(pd);
        }
        if(doInsert){
            insert productList;
        }   
        return productList;
    }
    
    public static List<Product2> createProdList(String nameOfProduct,Integer noOfProducts,Boolean doInsert){
        List<Product2> productList= new List<Product2>();
        for(Integer i=0;i<noOfProducts;i++) {
            Product2 pd = new Product2();
            pd.Name= nameOfProduct + i;
            pd.ProductCode='BU-01670-2';
            pd.IsActive=true;
            //pd.Income_Account__c = '0003 Sales : Direct Sales';
            //pd.Deferred_Revenue_Account__c = '2301 Deferred Revenue : Deferred Revenue - Clearing Account';
            //pd.Revenue_Recognition_Rule__c = 'Default One-Time Direct Posting';
            //pd.Rev_Rec_Forecast_Rule__c = 'Default One-Time Direct Posting';
            //pd.Create_Revenue_Plans_On__c = 'Billing';
            //pd.Item_Revenue_Category__c = 'Deal Cloud';
            pd.Status__c = 'Active';
            pd.Business_Units__c = 'Risk & Compliance';
            pd.Revenue_Type__c = 'Recurring';
            pd.Guided_Selling_Type__c = 'Software';
            pd.Product_Type_Sales__c = 'Software';
            pd.SBQQ__SubscriptionPricing__c = 'Fixed Price';
            pd.SBQQ__SubscriptionTerm__c = 1;
            pd.SBQQ__SubscriptionType__c = 'Renewable';
            pd.SBQQ__BillingFrequency__c = 'Annual';
            pd.SBQQ__ChargeType__c = 'Recurring';
            pd.SBQQ__BillingType__c = 'Advance';
            productList.add(pd);
        }
        if(doInsert){
            insert productList;
        }   
        return productList;
    }
    
   public static List<SBQQ__ProductOption__c> createProdOptionsList(String parentProdId,List<Product2> childProducts, Boolean doInsert){
        List<SBQQ__ProductOption__c> productOptionsList = new List<SBQQ__ProductOption__c>();
        Integer i =0;
        for(Product2 childProduct : childProducts) {
            
            SBQQ__ProductOption__c prodOption = new SBQQ__ProductOption__c();
            prodOption.SBQQ__ConfiguredSKU__c = parentProdId;
            prodOption.SBQQ__OptionalSKU__c = childProduct.Id;
            prodOption.SBQQ__Type__c = 'Related';
            prodOption.SBQQ__Number__c = i++;
            
            productOptionsList.add(prodOption);
        }
        
        if(doInsert)
        {
            insert productOptionsList;
        }
        return productOptionsList;
    }    
    public static PricebookEntry createPricebookEntry(String pId,Boolean doInsert){
        PricebookEntry standardPrice = new PricebookEntry();
        standardPrice.Pricebook2Id = Test.getStandardPricebookId();
        standardPrice.Product2Id = pId;
        standardPrice.UnitPrice = 100;
        standardPrice.IsActive = true;
        standardPrice.CurrencyISOCode = 'USD';
        standardPrice.UseStandardPrice = false;
        if(doInsert){
            insert standardPrice;
        }   
        return standardPrice;
    }
    
    public static List<PricebookEntry> createPricebookEntryList(List<Product2> productList,Boolean doInsert){
        List<PricebookEntry> pricebookEntryList = new List<PricebookEntry>();
        for(Integer i=0;i<productList.size();i++)
        {
            PricebookEntry standardPrice = new PricebookEntry();
            standardPrice.Pricebook2Id = Test.getStandardPricebookId();
            standardPrice.Product2Id = productList[i].Id;
            standardPrice.UnitPrice = 100;
            standardPrice.IsActive = true;
            standardPrice.CurrencyISOCode = 'USD';
            standardPrice.UseStandardPrice = false;
            
            pricebookEntryList.add(standardPrice);
        }
        
        if(doInsert){
            insert pricebookEntryList;
        }   
        return pricebookEntryList;
    }
    public static SBQQ__Dimension__c createPricebookDimension(String pId,Boolean doInsert){
        SBQQ__Dimension__c standardPrice = new SBQQ__Dimension__c();
        standardPrice.Name = 'Annual USD';
        standardPrice.SBQQ__Product__c = pId;
        standardPrice.SBQQ__Type__c = 'Year';
        if(doInsert){
            insert standardPrice;
        }   
        return standardPrice;
    }
    
    public static List<SBQQ__Dimension__c> createPricebookDimensionList(List<Product2> productList,Boolean doInsert){
        List<SBQQ__Dimension__c> dimensionList = new List<SBQQ__Dimension__c>();
        for(Integer i=0;i<productList.size();i++)
        {
            SBQQ__Dimension__c standardPrice = new SBQQ__Dimension__c();
            standardPrice.Name = 'Annual USD';
            standardPrice.SBQQ__Product__c = productList[i].Id;
            standardPrice.SBQQ__Type__c = 'Year';
            
            dimensionList.add(standardPrice);
        }
            if(doInsert){
            insert dimensionList;
        }   
        return dimensionList;
    }
    public static List<SBQQ__QuoteTerm__c> createQuoteTerm(Integer noOfQuoteTerm,Boolean doInsert){
        List<SBQQ__QuoteTerm__c> quoteTermList = new List<SBQQ__QuoteTerm__c>();
        for(Integer i=1;i<noOfQuoteTerm;i++)
        {
            SBQQ__QuoteTerm__c qtTerm = new SBQQ__QuoteTerm__c();
            qtTerm.SBQQ__Body__c='Subsidiary__c';
            qtTerm.SBQQ__PrintOrder__c=i;
            qtTerm.SBQQ__Active__c=true;
            
            quoteTermList.add(qtTerm);
        }
            if(doInsert){
            insert quoteTermList;
        }   
        return quoteTermList;
    }
    public static List<SBQQ__QuoteLine__c> createQuoteLine(Integer noOfQuoteLine,String qtId,String pId,Boolean doInsert){
        List<SBQQ__QuoteLine__c> quoteLineList= new List<SBQQ__QuoteLine__c>();
        for(Integer i=0;i<noOfQuoteLine;i++) {
            SBQQ__QuoteLine__c qtl = new SBQQ__QuoteLine__c();
            qtl.SBQQ__Product__c=pId;
            qtl.SBQQ__Quote__c=qtId;
            qtl.SBQQ__NetPrice__c = 200;
            qtl.SBQQ__CustomerPrice__c = 25;
            qtl.SBQQ__Quantity__c = 1;
            qtl.Print_at_Quote__c = false;
            qtl.CurrencyIsoCode = 'USD';
            qtl.SBQQ__ListPrice__c = 100;
            qtl.Parent_of_Bundle__c = true;
            //qtl.Product_is_Bundle__c=false;
            quoteLineList.add(qtl);
        }
        if(doInsert){
            insert quoteLineList;
        }   
        return quoteLineList;
    }
    
    public static List<SBQQ__QuoteLine__c> createQuoteLineList(Integer noOfQuoteLine,String qtId,List<Product2> prodList,Boolean doInsert){
        List<SBQQ__QuoteLine__c> quoteLineList= new List<SBQQ__QuoteLine__c>();
        for(Integer i=0;i<noOfQuoteLine;i++) {
            SBQQ__QuoteLine__c qtl = new SBQQ__QuoteLine__c();
            qtl.SBQQ__Product__c=prodList[i].Id;
            qtl.SBQQ__Quote__c=qtId;
            qtl.SBQQ__NetPrice__c = 200;
            qtl.SBQQ__CustomerPrice__c = 25;
            qtl.SBQQ__Quantity__c = 1;
            qtl.Print_at_Quote__c = false;
            qtl.CurrencyIsoCode = 'USD';
            qtl.SBQQ__ListPrice__c = 100;
            qtl.Parent_of_Bundle__c = true;
            qtl.SBQQ__SegmentIndex__c = 1;
            //qtl.Product_is_Bundle__c=false;
            quoteLineList.add(qtl);
        }
        if(doInsert){
            insert quoteLineList;
        }   
        return quoteLineList;
    }
    
    public static List<Address__c> createAddress(Integer noOfAddresses,Boolean doInsert,String accId)
    {
        List<Address__c> addrList= new List<Address__c>();
        for(Integer i=0;i<noOfAddresses;i++) {
            Address__c addr = new Address__c();
            addr.Address__City__s='Los Angeles';
            addr.Address__CountryCode__s='US';
            addr.Address__PostalCode__s='90210';
            addr.Address__StateCode__s='CA';
            addr.Address__Street__s='Beverly Hills';
            addr.Status__c='Pending Governance';
            addr.Department__c='Tax';
            addr.Default_Shipping_Address__c=True;
            addr.Default_Billing_Address__c=True;
            addr.Account__c=accId;
            addrList.add(addr);
        }
        if(doInsert){
            insert addrList;
        }   
        return addrList;
    } 
    
    public static List<Address__c> createBillingAddress(Integer noOfAddresses,Boolean doInsert,String accId)
    {
        List<Address__c> addrList= new List<Address__c>();
        for(Integer i=0;i<noOfAddresses;i++) {
            Address__c addr = new Address__c();
            addr.Address__City__s='Los Angeles';
            addr.Address__CountryCode__s='US';
            addr.Address__PostalCode__s='90210';
            addr.Address__StateCode__s='CA';
            addr.Address__Street__s='Beverly Hills';
            addr.Status__c='Pending Governance';
            addr.Department__c='Tax';
            addr.Default_Billing_Address__c=True;
            addr.Account__c=accId;
            addrList.add(addr);
        }
        if(doInsert){
            insert addrList;
        }   
        return addrList;
    }
    public static List<Address__c> createShippingAddress(Integer noOfAddresses,Boolean doInsert,String accId)
    {
        List<Address__c> addrList= new List<Address__c>();
        for(Integer i=0;i<noOfAddresses;i++) {
            Address__c addr = new Address__c();
            addr.Address__City__s='Los Angeles';
            addr.Address__CountryCode__s='US';
            addr.Address__PostalCode__s='90210';
            addr.Address__StateCode__s='CA';
            addr.Address__Street__s='Beverly Hills';
            addr.Status__c='Pending Governance';
            addr.Department__c='Tax';
            addr.Default_Shipping_Address__c=True;
            addr.Account__c=accId;
            addrList.add(addr);
        }
        if(doInsert){
            insert addrList;
        }   
        return addrList;
    } 
    public static List<Contract> createContract(Integer noOfContract,String accId,Boolean doInsert){
        List<Contract> conList= new List<Contract>();
        for(Integer i=0;i<noOfContract;i++) {
            Contract con = new Contract();
            con.Name='Test Contract'+i;
            con.AccountId=accId;
            con.Status='Draft quote by salesperson';
            con.OSA_Type__c='Master Contract';
            conList.add(con);
        }
        if(doInsert){
            insert conList;
        }   
        return conList;
    }
    public static List<ContentDocumentLink> createContentDocLink(Integer noOfDocs, String qId, String cdId, Boolean doInsert)
    {
        List<ContentDocumentLink> docList= new List<ContentDocumentLink>();
        for(Integer i=0;i<noOfDocs;i++) {
        ContentDocumentLink cdl=new ContentDocumentLink();
        cdl.LinkedEntityId=qId;
        cdl.contentdocumentid=cdId;
        cdl.ShareType = 'I';
        cdl.Visibility = 'AllUsers'; 
        docList.add(cdl);
        }
        if(doInsert){
            insert docList;
        }   
        return docList;
    }
    
    public static List<SBQQ__LookupData__c> createLookupDataList(String parentProdId,List<Product2> childProducts,List<PricebookEntry> priceBookEntryList,
                                                                 List<SBQQ__Dimension__c> priceBookDimensionList, Boolean doInsert){
        List<SBQQ__LookupData__c> lookupDataList = new List<SBQQ__LookupData__c>();
        Integer randomNumber = 999999999;
        for(Integer i =0;i<childProducts.size();i++)
         {
            SBQQ__LookupData__c lookupDataRecord = new SBQQ__LookupData__c();
            lookupDataRecord.SBQQ__Product__c = parentProdId;
            lookupDataRecord.Child_Product__c = childProducts[i].Id;
            lookupDataRecord.PriceBookEntry_Id__c = priceBookEntryList[i].Id;
            lookupDataRecord.Dimension_Id__c = priceBookDimensionList[i].Id;
            lookupDataRecord.SBQQ__Value__c = String.valueOf(randomNumber + i);
            lookupDataRecord.CurrencyIsoCode = 'USD';
            lookupDataRecord.Product_Allocation__c = 2;
            lookupDataList.add(lookupDataRecord);
        }
        
        if(doInsert)
        {
            insert lookupDataList;
        }
        return lookupDataList;
    }   
    
     public static SBQQ__LookupData__c createLookupData(Id parentProdId,String childProdId,String  priceBookEntryId,
                                                                 String priceBookDimension, Boolean doInsert){
        
            SBQQ__LookupData__c lookupDataRecord = new SBQQ__LookupData__c();
            lookupDataRecord.SBQQ__Product__c = parentProdId;
            lookupDataRecord.Child_Product__c = childProdId;
            lookupDataRecord.PriceBookEntry_Id__c = priceBookEntryId;
            lookupDataRecord.Dimension_Id__c = priceBookDimension;
            lookupDataRecord.SBQQ__Value__c =  String.valueOf(900000);
            lookupDataRecord.CurrencyIsoCode = 'USD';
            lookupDataRecord.Product_Allocation__c = 2;
            
        
        if(doInsert)
        {
            insert lookupDataRecord;
        }
        return lookupDataRecord;
    }   
}