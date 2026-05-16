/**
@description This is a one-time batch to snapshot all the payments when the Workato Invoice Project goes live *
@author venkat.sriram@intapp.com
@instructions To run this, go to Execute Anonymous and type - 
String query = 'SELECT Id, Amount_Credited__c, NS_Dollar_Amount_Paid__c, CurrencyIsoCode FROM Invoice__c';
SnapshotHistoricalPaymentData batch = new SnapshotHistoricalPaymentData(query);
Database.executeBatch(batch);
*/
global class SnapshotHistoricalPaymentData implements Database.Batchable<SObject> {
	global String query;
	global Boolean isDelete;
	global Set<Id> invoiceIds;
	global Boolean isReRun;
	global Boolean isUpdate;

	global SnapshotHistoricalPaymentData(String query, Boolean isUpdate, Boolean isDelete, Set<ID> invoiceIds, Boolean isReRun) {
		this.query = query;
		this.isDelete = isDelete;
		this.invoiceIds = invoiceIds;
		this.isReRun = isReRun;
		this.isUpdate = isUpdate;
	}
	
	/**
	 * @description gets invoked when the batch job starts
	 * @param context contains the job ID
	 * @returns the record set as a QueryLocator object that will be batched for execution
	 */ 
	global Database.QueryLocator start(Database.BatchableContext context) {
		if(isReRun) query += ' where Id in : invoiceIds';
		return Database.getQueryLocator(query);
	}

	/**
	 * @description gets invoked when the batch job executes and operates on one batch of records. Contains or calls the main execution logic for the batch job.
	 * @param context contains the job ID
	 * @param scope contains the batch of records to process.
	 */ 
   	global void execute(Database.BatchableContext context, List<SObject> scope) {
		List<NS_Payment__c> HistoricalData = new List<NS_Payment__c>();
		List<Integration_Error__c> ErrorsList = new List<Integration_Error__c>();
		if(isDelete){
			Delete (List<NS_Payment__c>) scope;
		}
		else if(isUpdate){
			List<NS_Payment__c> paymentsToUpdate = new List<NS_Payment__c>();

			for(Invoice__c i : (List<Invoice__c>) scope){
				for(NS_Payment__c payment: i.NS_Payments__r){
					if(payment.Transaction_Date__c == null){
						payment.Transaction_Date__c = i.Date_Paid__c;
						paymentsToUpdate.add(payment);
					}
				}
			}
			
			Database.SaveResult[] SRList = Database.update(paymentsToUpdate, false);
			for(Integer i=0;i<SRList.size();i++){
				if(!SRList[i].isSuccess()){
					for(Database.Error err : SRList[i].getErrors()) {
						Integration_Error__c er = new Integration_Error__c();
						er.Name = 'Payment: ' + HistoricalData[i].Id;
						er.Details__c = 'Error generating Payment Snapshot for '+ HistoricalData[i] + ' : '  + err.getStatusCode() + ' ' + err.getMessage()+ ' ' + err.getFields();
						ErrorsList.add(er);	
					}
				}
			}
		}
		else{
			for(Invoice__c i : (List<Invoice__c>) scope){
				//Payment Record for Credit
				NS_Payment__c creditRec = new NS_Payment__c();
				creditRec.Invoice__c = i.Id;
				creditRec.Type__c = 'Credit';
				creditRec.Amount__c = i.Amount_Credited__c == null ? 0 : i.Amount_Credited__c;
				creditRec.Payment_notes__c = 'Credit - as of ' + Date.today(); 
				creditRec.CurrencyIsoCode = i.CurrencyIsoCode;

 				//Payment Record for Customer Payment
				NS_Payment__c paymentRec = new NS_Payment__c();
				paymentRec.Invoice__c = i.Id;
				paymentRec.Type__c = 'Payment';
				paymentRec.Amount__c = i.NS_Dollar_Amount_Paid__c == null? 0 : i.NS_Dollar_Amount_Paid__c;
				paymentRec.Payment_notes__c = 'Payment - as of ' + Date.today(); 
				paymentRec.CurrencyIsoCode = i.CurrencyIsoCode;

				HistoricalData.add(creditRec);
				HistoricalData.add(paymentRec);
			}

			Database.SaveResult[] SRList = Database.insert(HistoricalData, false);
			

			for(Integer i=0;i<SRList.size();i++){
				if(!SRList[i].isSuccess()){
					for(Database.Error err : SRList[i].getErrors()) {
						Integration_Error__c er = new Integration_Error__c();
						er.Name = HistoricalData[i].Invoice__c;
						er.Details__c = 'Error generating Payment Snapshot for '+ HistoricalData[i] + ' : '  + err.getStatusCode() + ' ' + err.getMessage()+ ' ' + err.getFields();
						ErrorsList.add(er);	
					}
				}
			}	
		}

		if(ErrorsList.size() > 0) insert ErrorsList;
	}
	
	/**
	 * @description gets invoked when the batch job finishes. Place any clean up code in this method.
	 * @param context contains the job ID
	 */ 
	global void finish(Database.BatchableContext context) {
		
	}
}