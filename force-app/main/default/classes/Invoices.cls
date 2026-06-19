/**
 * See https://github.com/financialforcedev/fflib-apex-common for more info
 *
 * Install library via 
 *   https://githubsfdeploy.herokuapp.com/app/githubdeploy/financialforcedev/fflib-apex-common
 */

/**
 * Encapsulates all behaviour logic relating to the Account object
 * 
 * For more guidelines and details see 
 *   https://developer.salesforce.com/page/Apex_Enterprise_Patterns_-_Domain_Layer
 *
 * 6/15/2016: AW - First Release
 **/
public class Invoices extends fflib_SObjectDomain
{
	public Invoices(List<Invoice__c> records)
	{
		super(records);
		Configuration.disableTriggerCRUDSecurity();
	}

	public override void onAfterInsert()
	{
		CreatePCLinkForInvoice(false, null);
        CreateTermsForInvoices();
	}
    
	public override void OnBeforeUpdate(Map<Id,SObject> existingRecords){
		//UpdateInvoiceStatus();
	}

    public override void OnAfterUpdate(Map<Id,SObject> existingRecords){
		CreatePCLinkForInvoice(true, existingRecords);	
    }
    
	//@purpose: Update Invoice STatus based on Outstanding balance field (on update)
	//@report issues to: business_applications@intapp.com
	//@developed by: venkat.sriram@intapp.com
	
	public void UpdateInvoiceStatus(){
		for(Invoice__c i: (List<Invoice__c>) Records){
				System.debug('cp 1');
				Decimal invoiced, paid, credited, out_bln = 0;
				if(i.Amount_Invoiced__c != null) invoiced = i.Amount_Invoiced__c;
				if(i.Amt_Paid__c != null) paid = i.Amt_Paid__c;
				if(i.amt_credited__c != null) credited = i.amt_credited__c;

				out_bln = invoiced - (paid + credited);
				System.debug(' status before ' + i.Status__c);
				if(out_bln < 1){
					if(credited == invoiced) i.Status__c = 'Credited in Full';
					else if(credited > 0) i.status__c = 'Paid but Partially Credited';
					else if(credited == 0) i.status__c = 'Paid In Full';
				}
				else if(out_bln > 1 && out_bln < invoiced){
					if(credited > 0) i.status__c = 'Partially Credited';
					else i.status__c = 'Partially Paid';
				}
				System.debug(' status after ' + i.Status__c);
		}
	}

    //@purpose: link Invoice to PC (on create and update)
	//@report issues to: business_applications@intapp.com
	//@developed by: venkat.sriram@intapp.com
	//@parameters: isUpdate = true when its an update, existingRecords = trigger.oldMap - available only during update
    public void CreatePCLinkForInvoice(Boolean isUpdate, Map<Id,SObject> existingRecords){
    	//Set a save point here - roll back database changes to this point if there is a failure
        Savepoint sp = Database.setSavepoint();
        
        Map<Id, List<Invoice__c>> 					 map_ContractId_InvoiceList = new Map<Id, List<Invoice__c>>();
        
        List<Invoice_Subscription_Link__c> list_InvoicePCLink_toCreate = new List<Invoice_Subscription_Link__c>();
        List<Invoice_Subscription_Link__c> list_InvoicePCLink_toDelete = new List<Invoice_Subscription_Link__c>();
        
        for(Invoice__c i: [Select Id, Related_OSA__c,
                           		  (Select Id from Invoice_Subscription_Links__r)
                             FROM Invoice__c
                            WHERE Id in: Records]){
                                
        	if(isUpdate){
				//Get the Invoice data before update
            	Invoice__c oldInvoice  = (Invoice__c) existingrecords.get(i.Id);
            	
                //If its an update and there is no change to OSA linked to Invoice, no need to do anything in this method - move to next Invoice in the loop
                if(i.Related_OSA__c == oldInvoice.Related_OSA__c) 
                    continue; 
                
                //If there is a change to OSA, to delete old Invoice - PC links - We will relink Invoice with PCs related to the new OSA
            	if(i.Invoice_Subscription_Links__r != null && i.Invoice_Subscription_Links__r.size() > 0)
                	list_InvoicePCLink_toDelete.addAll(i.Invoice_Subscription_Links__r);
            }
            
            if(!map_ContractId_InvoiceList.containsKey(i.Related_OSA__c))
            	map_ContractId_InvoiceList.put(i.Related_OSA__c, new List<Invoice__c> {i});
			else
                map_ContractId_InvoiceList.get(i.Related_OSA__c).add(i);
        }
        
        //Delete Old Invoice - PC Link (if OSA is changed on the Invoice)
        try{
            if(list_InvoicePCLink_toDelete.size() > 0) delete list_InvoicePCLink_toDelete;
        }catch(Exception e){
            database.rollback(sp);
        }
        
        for(Contract c: [SELECT Id, (Select Id, Subscription__c from Subscription_Contract_Links__r)
                           FROM Contract
                          WHERE Id in: map_ContractId_InvoiceList.keySet()]){
        	//If there are no Contract - PC links, move on to the next one
			if(c.Subscription_Contract_Links__r == null || c.Subscription_Contract_Links__r.size() == 0){
				continue;
			}
			
			for(Invoice__c i: map_ContractId_InvoiceList.get(c.Id)){
				for(Subscription_Contract_Link__c sc: c.Subscription_Contract_Links__r){
					list_InvoicePCLink_toCreate.add(new Invoice_Subscription_Link__c (Invoice__c = i.Id, Subscription__c = sc.Subscription__c));
				}
			}
		}
        
        //Create New Invoice - PC Link
        try{
            if(list_InvoicePCLink_toCreate.size() > 0) insert list_InvoicePCLink_toCreate;
        }catch(Exception e){
            database.rollback(sp);
        }
    }
    
	public void CreateTermsForInvoices()
	{
		List<Term__c> termsToInsert = new List<Term__c> ();

		for (Invoice__c i : (List<Invoice__c>) Records) {
			//Look for existing Term
			List<Term__c> terms = [SELECT Id FROM Term__c WHERE OSA_Number__c = :i.OSA_Number__c AND Product_Customer_Number__r.Account__c = :i.Account__c];
			if (terms.size() == 0)
			{
				List<Subscription_Contract_Link__c> subcontractlinks = [SELECT Subscription__c FROM Subscription_Contract_Link__c WHERE Contract__c = :i.Related_OSA__c];
				for (Subscription_Contract_Link__c scl : subcontractlinks)
				{
					//Create new Term
					Term__c term = new Term__c();
					term.Product_Customer_Number__c = scl.Subscription__c;
					term.OSA_Number__c = i.OSA_Number__c;
					term.Start_Date__c = i.NS_Rev_Rec_Start_Date__c;
					term.Term_End_Date__c = i.Latest_NS_Rev_Rec_Date__c;
					term.Status__c = 'Active';
					termsToInsert.add(term);
				}
			}

			if (termsToInsert.size() > 0)
			{
				insert termsToInsert;
			}
		}
	}

	public class Constructor implements fflib_SObjectDomain.IConstructable
	{
		public fflib_SObjectDomain construct(List<SObject> sObjectList)
		{
			return new Invoices(sObjectList);
		}
	}
}