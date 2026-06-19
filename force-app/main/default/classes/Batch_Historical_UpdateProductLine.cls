public class Batch_Historical_UpdateProductLine implements Database.Batchable<SObject>,Database.Stateful {
    public String query;
    public String sObjectType;
    public String oldFieldName;
    public String newFieldName;
    public Map<String, Id> map_pl_plid = new Map<String, Id>();
    public Map<String, String> map_productline_lookup = new Map<String,String>();
    public Integer batch_number = 0; 
    public String listWithProblem = '';
    public Set<Integer> batchToSkip = new Set<Integer>(); 
        
    public Batch_Historical_UpdateProductLine(String query, String sObjectType, String oldFieldName, String newFieldName, Map<String, String> map_productline_lookup, Set<Integer> bToSkip) {
        batch_number = 0;
        this.query = query;
        this.sObjectType = sObjectType;
        this.oldFieldName = oldFIeldName;
        this.newFieldName = newFieldName;
        this.map_productline_lookup = map_productline_lookup;
        this.batchToSkip = bToSkip;
        
        for(Product_Line__c pl: [Select Id, Name 
                                 from Product_Line__c 
                                 where Active__c = true]){
            map_pl_plid.put(pl.Name, pl.Id);                                 
        }
    }
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        String listWithProblem_temp = '';
        List<sObject> listToUpdate = new List<sObject>();
        batch_number ++;
        
        for(sObject sobj: scope){
            String oldValue = (String) sobj.get(oldFieldName);
            
            if(oldValue== null || !map_productline_lookup.containsKey(oldValue)){
                oldValue = 'Other';
            }
            
            String newValue_name = map_productline_lookup.get(oldValue);
            
            if(!map_pl_plid.containsKey(newValue_name))
                continue;
                
            String newValue_id = map_pl_plid.get(newValue_name);
            sobj.put(newFieldName, newValue_id );
            listToUpdate.add(sobj);
            listWithProblem += '\r\n<br/>' + (String) sobj.get('id') + ' - ' + (String) sobj.get('name') + ' - ' + (String) sobj.get('Product_Line__c') + ' - ' + newValue_name + '(' + newValue_id + ')';
            //listWithProblem_temp+= '\r\n<br/>' + (String) sobj.get('id') + ' - ' + (String) sobj.get('name') + ' - ' + (String) sobj.get('Product_Line__c') + ' - ' + newValue_name + '(' + newValue_id + ')'; 
        }
        
        /*
        if(listToUpdate.size() > 0) update listToUpdate;
        if(batch_number == 118 || batch_number == 119)
            listWithProblem += listWithProblem_temp;
        */
        if(batchToSkip != null && batchToSkip.contains(batch_number)){
        	Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setSubject('Batch # ' + batch_number);
            mail.setHtmlBody(listWithProblem);
            mail.setToAddresses(new List<String>{'venkat.sriram@intapp.com'});
            List<Messaging.SingleEmailMessage> Mails = new List<Messaging.SingleEmailMessage>();
            Mails.add(mail);
            Messaging.sendEmail(Mails);   
        }
        
        if(batchToSkip == null || !batchToSkip.contains(batch_number))
        	list<Database.SaveResult> results = Database.update(listToUpdate, false);    
        
    }
    
    public void finish(Database.BatchableContext context) {
            /*
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setSubject('Batch # ' + batch_number);
            mail.setHtmlBody(listWithProblem);
            mail.setToAddresses(new List<String>{'venkat.sriram@intapp.com'});
            List<Messaging.SingleEmailMessage> Mails = new List<Messaging.SingleEmailMessage>();
            Mails.add(mail);
            Messaging.sendEmail(Mails);
            */
    }
}