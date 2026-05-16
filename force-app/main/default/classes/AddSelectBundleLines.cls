/**
* @description       : Select Bundle parent record doesn't hold MDQ structure, however we need to show yearly wise data in document. 
					   In order to preserve the integrity of Select Bundle and meet the requirement of Document generation, we created a custom object
					   which would hold summarized yearly data of child record of Select Bundle and would be linked with parent of Select Bundle.

					   Invoked when Quote Pricing Proposal Approval field value is set to Approved.
* @author            : Dhiraj Kumar - KPMG
* @date              : 2023-12-12
* Story              : BIZ-51772
*
**/
public class AddSelectBundleLines {
	
    @AuraEnabled
    public static String createSelectLineandTermQuotesRecords(String quoteId)
    {
        String quoteIdToReturn;
        System.debug('***********AddSelectBundleLines --> addBundleLines METHOD BEGINS');
        try
        {
            Map<Id,List<SBQQ__QuoteLine__c>> mapOfChildBundlesByParentQLId = new Map<Id,List<SBQQ__QuoteLine__c>>();
            List<Select_Bundle_Lines__c> lstOfSelBundleLine = new List<Select_Bundle_Lines__c>();
            List<Select_Bundle_Lines__c> finalLstOfBundleLineToInsert = new List<Select_Bundle_Lines__c>();
            
			String message;
            Map<Id,SBQQ__QuoteLine__c> mapOfSelectBundle = new Map<Id,SBQQ__QuoteLine__c>([Select Id,Name,SBQQ__RequiredBy__c,SBQQ__ProductName__c,SBQQ__CustomerTotal__c, SBQQ__StartDate__c, 
                                                                                            SBQQ__RequiredBy__r.Name,SBQQ__Product__c,SBQQ__EndDate__c, SBQQ__SegmentIndex__c,SBQQ__Quote__c,
                                                                                            SBQQ__PackageProductDescription__c,SBQQ__Quote__r.SegmentIndex_Max__c,SBQQ__Quantity__c, Customer_Sale_Price_Per_Month__c
                                                                                            FROM SBQQ__QuoteLine__c 
                                                                                            WHERE SBQQ__Quote__c =: quoteId AND 
                                                                                            (Is_Select_Bundle__c = true OR (SBQQ__RequiredBy__c != null AND SBQQ__RequiredBy__r.SBQQ__ProductCode__c = 'BU-01408'))
                                                                                            ORDER BY SBQQ__RequiredBy__c ]);
            
            
            if(mapOfSelectBundle != null && !mapOfSelectBundle.isEmpty())
            {
                for(SBQQ__QuoteLine__c quoteline : mapOfSelectBundle.values())
                {
                    if(String.isNOTBLANK(quoteline.SBQQ__RequiredBy__c)){
                        if(!mapOfChildBundlesByParentQLId.containskey(quoteline.SBQQ__RequiredBy__c))
                        {
                            mapOfChildBundlesByParentQLId.put(quoteline.SBQQ__RequiredBy__c,new List<SBQQ__QuoteLine__c>{quoteLine});
                        }
                        else
                        {
                            mapOfChildBundlesByParentQLId.get(quoteline.SBQQ__RequiredBy__c).add(quoteLine);
                        }
                    }  
                }    
            
                // Run aggregate query(yearly basis) and prepare list of Select Bundle records

                for (AggregateResult  ag :[ Select SUM(SBQQ__Quantity__c) qty, SUM(SBQQ__CustomerTotal__c)amt,SUM(Customer_Sale_Price_Per_Month__c)monthlyPrice, Segment_Index_Custom__c Index,
                                            SBQQ__RequiredBy__c parentQLI, SBQQ__StartDate__c StartDate, SBQQ__EndDate__c EndDate
                                            FROM SBQQ__QuoteLine__c 
                                            WHERE SBQQ__RequiredBy__c IN : mapOfChildBundlesByParentQLId.keyset()
                                            GROUP BY Segment_Index_Custom__c,SBQQ__RequiredBy__c,SBQQ__StartDate__c,SBQQ__EndDate__c])
                {
                    Select_Bundle_Lines__c recordToInsert = new Select_Bundle_Lines__c();
                    recordToInsert.Quote_Line__c = String.ValueOf(ag.get('parentQLI'));
                    recordToInsert.Start_Date__c = Date.valueOf(ag.get('StartDate'));
                    recordToInsert.End_Date__c = Date.valueOf(ag.get('EndDate'));
                    System.debug('************* '+  Double.valueOf(ag.get('amt')));
                    recordToInsert.Net_Total__c = Double.valueOf(ag.get('amt'));
                    recordToInsert.Index__c = Double.valueOf((String)ag.get('Index'));
                    recordToInsert.Quantity__c = (Decimal)(ag.get('qty'));
                    recordToInsert.External_Id__c = String.valueOf(ag.get('Index'));
                    //recordToInsert.Customer_Price__c = (recordToInsert.Net_Total__c/12).setScale(2, RoundingMode.CEILING);
                    recordToInsert.Customer_Price__c = Double.valueOf(ag.get('monthlyPrice'));
                    lstOfSelBundleLine.add(recordToInsert); 
                }
                                
                /* QuoteLine Name,Id and Long Text field  cannot be used in aggregate query, iterating over the collection and via map collection
                *  pulling Quote Line Number and concatenatin with version number */
                
                if(lstOfSelBundleLine != null && !lstOfSelBundleLine.isEmpty())
                {
                    for(Select_Bundle_Lines__c sbline : lstOfSelBundleLine)
                    {
                        if(mapOfSelectBundle.containskey(sbline.Quote_Line__c))
                        {
                            sbline.External_Id__c = mapOfSelectBundle.get(sbline.Quote_Line__c).Name + ' - ' + sbline.External_Id__c;
                            sbline.Quote__c = mapOfSelectBundle.get(sbline.Quote_Line__c).SBQQ__Quote__c;
                            sbline.Includes__c =mapOfSelectBundle.get(sbline.Quote_Line__c).SBQQ__PackageProductDescription__c;
                            if(String.isBlank(quoteIdToReturn)){
                                quoteIdToReturn =mapOfSelectBundle.get(sbline.Quote_Line__c).SBQQ__Quote__c;
                            }
                            finalLstOfBundleLineToInsert.add(sbline);
                        }
                    }               
                }
            
                if(finalLstOfBundleLineToInsert != null && !finalLstOfBundleLineToInsert.isEmpty())
                {
                    Schema.SObjectField ftoken = Select_Bundle_Lines__c.Fields.External_Id__c;
                    Database.UpsertResult[] srList = Database.upsert(finalLstOfBundleLineToInsert,ftoken,false);
                    
                    for (Database.UpsertResult sr : srList) {
                        if (sr.isSuccess()) {
                            // Operation was successful
                            Message = 'SUCCESS';
                        }
                        else {
                            // Operation failed, so get all errors                
                            for(Database.Error err : sr.getErrors()) {
                                Message = 'ERROR : ' + err.getMessage();                  
                                
                            }
                        }
                    }
                }
            }
            else
            {
                Message = 'No Records Found!';
            }

            if(quoteId != null){               
                QuoteTermValidator.generateQuoteTerms(quoteId);
                Message += '===Upserted Term Quotes';
            }           

            return Message;
        }     
        catch(Exception ex)
        {
              return 'ERROR : '+ex.getMessage();
        }
	}
    @AuraEnabled(cacheable=true)
    public static String generateCongaURL(String quoteId)
    {
    	try{
            String congaURL;
            String congaPrefix= System.Label.Conga_URL;
            String pricingTempId = System.Label.Pricing_Proposal_Document_Key;
            String osaTempId = System.Label.OSA_Document_Key;
            Map<String,String> mapCongaQuery = new Map<String,String>();
            SBQQ__Quote__c qtr = [Select id,Name,Account_Name__c,SBQQ__Account__r.Account_Short_Name__c,Quote_Stage__c,SBQQ__Type__c,Subsidiary__c,Version__c,SBQQ__ExpirationDate__c,OSA_Number__c,Line_of_Business__c,SBQQ__WatermarkShown__c 
                                  From SBQQ__Quote__c 
                                  Where id=:quoteId];
            quoteId = String.valueOf(quoteId).substring(0, 15);
            Date convertedDate = date.valueOf(qtr.SBQQ__ExpirationDate__c);
			string dtToStr= string.valueOf(convertedDate);
			string dateAsString = dtToStr.replace('-','');
            for(APXTConga4__Conga_Solution_Query__c con:[Select Id, APXTConga4__Alias__c,APXTConga4__Conga_Solution__r.name,APXTConga4__Conga_Query__r.APXTConga4__Key__c
                                                      From APXTConga4__Conga_Solution_Query__c
                                                      Where APXTConga4__Conga_Solution__r.name = 'Pricing Proposal Document']){
                                                         
            	mapCongaQuery.put(con.APXTConga4__Alias__c,con.APXTConga4__Conga_Query__r.APXTConga4__Key__c);                
            }
            congaURL=congaPrefix +quoteId+ '&QueryId=';
            for(String str:mapCongaQuery.keyset()){
                if(str!=null){congaURL+= '['+str+']' + mapCongaQuery.get(str)+ '%3Fpv0%3D'+quoteId+',';
                }
            }
            congaURL = congaURL.removeEnd(',');
            String sAdjustedAccountName = qtr.SBQQ__Account__c != null && String.isNotBlank(qtr.SBQQ__Account__r.Account_Short_Name__c) && qtr.SBQQ__Account__r.Account_Short_Name__c.length() > 36 ? qtr.SBQQ__Account__r.Account_Short_Name__c.substring(0,35) : qtr.SBQQ__Account__r.Account_Short_Name__c;
            System.Debug('congaURLValue '+congaURL);
            if(qtr.Quote_Stage__c=='Pricing Proposal'){
                 if(qtr.SBQQ__Type__c=='Amendment'){
                           	congaURL = congaURL + '&TemplateId='+ pricingTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&OFN='+dateAsString+'_Amendment_'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
                 	}
                     else{
                         congaURL = congaURL + '&TemplateId='+ pricingTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&OFN='+dateAsString+'_Proposal'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
                    }
            }
            else if(qtr.Quote_Stage__c=='Finalize OSA'){
               if(qtr.SBQQ__WatermarkShown__c == true){
					if(qtr.SBQQ__Type__c=='Amendment'){
							congaURL = congaURL + '&TemplateId='+ osaTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&DV0=DRAFT&OFN='+dateAsString+'_Amendment_'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
					} 
					else{
							congaURL = congaURL + '&TemplateId='+ osaTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&DV0=DRAFT&OFN='+dateAsString+'_Bundle'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
					}
				}
				else{
				if(qtr.SBQQ__Type__c=='Amendment'){
							congaURL = congaURL + '&TemplateId='+ osaTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&OFN='+dateAsString+'_Amendment_'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
					} 
					else{
							congaURL = congaURL + '&TemplateId='+ osaTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&OFN='+dateAsString+'_Bundle'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
					}
				}
			}
			else{
                congaURL = congaURL + '&TemplateId='+ osaTempId + '&defaultpdf=1&DS7=1&SC0=1&SC1=Attachments&zipfiles=0&OFN='+dateAsString+'_Bundle'+qtr.OSA_Number__c+'_'+qtr.Line_of_Business__c+'_'+sAdjustedAccountName+'_v'+qtr.Version__c;
            }
            return congaURL;
        }catch(Exception ex)
        {
              return 'ERROR : '+ex.getMessage();
        }   
    } 
}