@isTest
public class HandleCustomExceptionTest {
    @isTest
    static void testMethod1(){
        try{
            List<Account> acclist=new List<Account>();
           Account a=new Account();
            acclist.add(a);
            Database.SaveResult[] accsvRes = Database.insert(acclist, false);
             //Database.DeleteResult[] accdlRes = Database.delete(acclist, false);
            HandleCustomException.logDatabaseErrors(accsvRes);
           //HandleCustomException.logDatabaseDeleteErrors(accdlRes,'HandleCustomException','logDatabaseDeleteErrors');
       // throw new DMLException('Test');
       List<Account> acclist1=[select Id from Account];
       system.assertEquals(0,accList1.size());    
        }catch(Exception e){
         HandleCustomException.logException(e); 
            
        }
        
        
    }
@isTest
    static void testMethod2(){
        try{
            //List<SBQQ__QuoteLine__c> qtline=new List<SBQQ__QuoteLine__c>();
           // Database.SaveResult[] entitlementListOpp = Database.update(qtline, false);
           Account a=new Account();
            HandleCustomException.getKey('Name,CreatedDate',a);
            List<Account> acclist1=[select Id from Account];
           system.assertEquals(0,accList1.size());
          throw new DMLException('Test');
        }catch(Exception e){
          HandleCustomException.logException(e);
        }
    }
    @isTest
    static void testMethod3(){
        try{
            //List<SBQQ__QuoteLine__c> qtline=new List<SBQQ__QuoteLine__c>();
           // Database.SaveResult[] entitlementListOpp = Database.update(qtline, false);
           List<Account> acclist=new List<Account>();
            Account a=new Account();
            a.Name='Test';
            acclist.add(a);
            insert accList;
           Database.DeleteResult[] accdlRes = Database.delete(acclist, false);
           HandleCustomException.logDatabaseDeleteErrors(accdlRes,'HandleCustomException','logDatabaseDeleteErrors');
          List<Account> acclist1=[select Id from Account];
           system.assertEquals(0,accList1.size());
       }catch(Exception e){
          HandleCustomException.logException(e);
        }
    }
    @isTest
    static void testMethod4(){
        try{
            //List<SBQQ__QuoteLine__c> qtline=new List<SBQQ__QuoteLine__c>();
           // Database.SaveResult[] entitlementListOpp = Database.update(qtline, false);
            Account a1=new Account();
            a1.Name='Test';
          insert a1;
           List<Account> acclist=new List<Account>();
            Account a=new Account();
            //a.Name='Test';
            acclist.add(a);
            Map<String,sObject> accMap=new Map<String,sObject>();
            accMap.put(string.valueof(a1.Id),a1);
           Database.SaveResult[] accdlRes = Database.insert(acclist,false);
           HandleCustomException.logDatabaseErrorsForEntitlements(accdlRes,accMap);
          List<Account> acclist1=[select Id from Account];
           system.assertEquals(1,accList1.size());
       }catch(Exception e){
          HandleCustomException.logException(e);
        }
    }
    
     @isTest
    static void testMethod5(){
        try{
            //List<SBQQ__QuoteLine__c> qtline=new List<SBQQ__QuoteLine__c>();
           // Database.SaveResult[] entitlementListOpp = Database.update(qtline, false);
            Account a1=new Account();
            a1.Name='Test';
          insert a1;
           List<Account> acclist=new List<Account>();
            Account a=new Account();
            //a.Name='Test';
            acclist.add(a);
            Map<String,sObject> accMap=new Map<String,sObject>();
            accMap.put(string.valueof(a1.Id),a1);
           //List<string> fieldList =new List<string>();
            //fieldList.add('Name')
           Database.SaveResult[] accdlRes = Database.insert(acclist,false);
           HandleCustomException.logMigrationDatabaseError(accdlRes,accMap,'Name,createdDate',accList);
            List<Account> acclist1=[select Id from Account];
           system.assertEquals(1,accList1.size());
       }catch(Exception e){
          HandleCustomException.logException(e);
        }
    }
    
}