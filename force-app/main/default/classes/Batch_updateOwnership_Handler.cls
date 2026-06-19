public class Batch_updateOwnership_Handler {
    
    public static String updateDCAccounts (List<Account> accounts){
        List<Account> accToUpdate = new List<Account>();
        
        for(Account b:accounts){
            if(b.DealCloud__c != 'DealCloud' || b.Support_Level_Dealcloud__c != 'Standard'){
                b.DealCloud__c = 'DealCloud';
                b.Support_Level_Dealcloud__c = 'Standard';
                accToUpdate.add(b);
            }
        }
        
        if(accToUpdate.size()> 0)
    		update accToUpdate;
        
        String errors = '';
        
        if(accToUpdate.size() > 0){
            Database.SaveResult[] updateResult = Database.update(accToUpdate, false);
            for (Database.SaveResult r : updateResult){
                if (!r.isSuccess()){
                	for (Database.Error e : r.getErrors()){ 
                		errors += r.getId() + '-' + e.getMessage() + '<b/>';
                    }
                }
            }
    	}
        
        return String.isBlank(errors)? '':errors;
	}	

    public static String updateNonDCAccounts(List<Product_Ownership_detail__c> trigger_new){
        Set<Id> accountId_set = new Set<Id>();
        Map<Id, Account> account_map = new Map<Id, Account>();
        
        //Sample map data - {00130000001RB23 = {'Experience' = 'Experience-Cloud', 'Intake' = 'Intake-On Prem'}}
        Map<Id, Map<String, String>> account_ownership_map = new Map<Id, Map<String, String>>();
        //Sample map data - {00130000001RB23 = {'Experience' = 'Standard', 'Intake' = 'Standard'}}
        Map<Id, Map<String, String>> account_supportLevel_map = new Map<Id, Map<String, String>>();
        
        //Final map that will contain only accounts that need to be updated
        Map<Id, Account> map_accountsToUpdate = new Map<Id, Account>();
        
        //Maps to get API name of the field dynamically
        Map<String, String> ownerShipFieldAPIName_map = new Map<String, String>{
                'CRM' => 'CRM__c',
                'DealCloud' => 'DealCloud__c',   
                'Experience' => 'Experience__c',
                'Flow' => 'Flow__c',
            	'IIS' => 'IIS__c',
                'Intake' => 'Intake_Product__c',
                'Integrate' => 'Integrate__c',
                'L&P' => 'L_P__c',
                'LegalKey' => 'LegalKey__c',
                'Nudges' => 'Nudges__c',
                'Pricing' => 'Pricing__c',
                'Conflicts' => 'Product_Owned_Conflicts__c',
                'Relationships' => 'Relationships__c',
                'Terms' => 'Terms__c',
                'TFG - Other' => 'TFG_Other__c',    
                'Time' => 'Time__c',
                'Walls' => 'Walls__c'
        };
            
        Map<String, String> supportLevelFieldAPIName_map = new Map<String, String>{
                'CRM' => 'Support_Level_CRM__c',
                'DealCloud' => 'Support_Level_DealCloud__c',   
                'Experience' => 'Support_Level_Experience__c',
                'Flow' => 'Support_Level_Flow__c',
            	'IIS' => 'Support_Level_IIS__c',
                'Intake' => 'Support_Level_Intake__c',
                'Integrate' => 'Support_Level_Integrate__c',
                'L&P' => 'Support_Level_L_P__c',
                'Nudges' => 'Support_Level_Nudges__c',
                'Pricing' => 'Support_Level_Pricing__c',
                'Conflicts' => 'Support_Level_Conflicts__c',
                'Relationships' => 'Support_Level_Relationships__c',
                'Terms' => 'Support_Level_Terms__c', 
                'Time' => 'Support_Level_Time__c',
                'Walls' => 'Support_Level_Walls__c'
        };
        
        
        for(Product_Ownership_detail__c pod: trigger_new){
            accountId_set.add(pod.Account_Name__c);
        }
        
        //Get all accounts in a map
        for(Account acc: [Select Id, Type, CRM__c, DealCloud__c, Experience__c, Flow__c, IIS__c, Intake_Product__c, 
                         		 Integrate__c, L_P__c, LegalKey__c, Nudges__c, Pricing__c, Product_Owned_Conflicts__c, Relationships__c, 
                          		 Terms__c, TFG_Other__c, Time__c, Walls__c,
                          		 Support_Level_CRM__c,Support_Level_DealCloud__c,Support_Level_Experience__c,Support_Level_Flow__c,
                          		 Support_Level_IIS__c,Support_Level_Intake__c,Support_Level_Integrate__c,Support_Level_L_P__c,
                          		 Support_Level_Nudges__c,Support_Level_Pricing__c,Support_Level_Conflicts__c,Support_Level_Relationships__c,
                          		 Support_Level_Terms__c,Support_Level_Time__c,Support_Level_Walls__c
                         FROM Account
                         WHERE Id in: accountId_set]){
                             
                             if(!account_map.containsKey(acc.id)){
                                 account_map.put(acc.id, acc);
                             } 
        }
        
        //Construct the map initialized in line 8 and 10 - Get data for all products except CRM - CRM needs License basis data
        for(AggregateResult pod: [Select count(id), 
                                  		 Product_line_link__r.Name pl, 
                                  		 Product_line_link__r.Simple_Product_Line__c spl,
                                  		 Account_Name__c,
                                  		 Support_Level__c
                                  FROM Product_Ownership_detail__c 
                                  WHERE Account_Name__c in : account_map.keySet() 
                                  AND Status__c NOT IN ('Converted', 'Lapsed')
                                  AND Product_line_link__r.Simple_Product_Line__c <> 'CRM'
                                  GROUP BY Product_line_link__r.Name, Product_line_link__r.Simple_Product_Line__c,Account_Name__c, Support_Level__c]){
                                      
                                      if(!account_ownership_map.containsKey((ID)pod.get('Account_Name__c'))){
                                          account_ownership_map.put((ID)pod.get('Account_Name__c'), new Map<String, String>());
                                          account_supportLevel_map.put((ID)pod.get('Account_Name__c'), new Map<String, String>());
                                      }
                                      
                                      //SPL for LegalKey is TFG - Other, the ownership hence goes to TFG - the logic below is to correct that
                                      if(((String)pod.get('pl')).contains('LegalKey')){
                                          account_ownership_map.get((ID)pod.get('Account_Name__c')).put('LegalKey', 'LegalKey - On Prem');
                                      }
                                      else{
                                      	account_ownership_map.get((ID)pod.get('Account_Name__c')).put((String)pod.get('spl'), (String)pod.get('pl'));
                                      }
                                      
                                      String convertedSupportLevel = '';
                                      
                                      if((String)pod.get('Support_Level__c') == null){
                                          convertedSupportLevel = 'Standard';
                                      }
                                      else{
                                          convertedSupportLevel = ((String)pod.get('Support_Level__c')).toLowerCase().contains('premium')?'Premium':'Standard';
                                      }
                                      
                                      account_supportLevel_map.get((ID)pod.get('Account_Name__c')).put((String)pod.get('spl'), convertedSupportLevel);
                                      
                                      //Special case - If Account owns IIS, then Flow - Cloud is automatically owned
                                      if((String)pod.get('spl') == 'IIS' && !(account_ownership_map.get((ID)pod.get('Account_Name__c')).containsKey('Flow'))){
                                          account_ownership_map.get((ID)pod.get('Account_Name__c')).put('Flow', 'Flow - Cloud');
                                          account_supportLevel_map.get((ID)pod.get('Account_Name__c')).put('Flow', convertedSupportLevel);
                                      }
                                      
                                      
                                  }
        
        //Cont. Construct the map initialized in line 8 and 10 - Get data for CRM - CRM needs License basis data
        for(AggregateResult pod: [Select Product_line_link__r.Name, 
                                                     Product_line_link__r.Simple_Product_Line__c spl,
                                                     Account_Name__c,
                                                     Support_Level__c,
                                              		 License_basis_link__r.Name lb 
                                              FROM Product_Ownership_detail__c 
                                              WHERE Account_Name__c in : account_map.keySet() 
                                              AND Status__c NOT IN ('Converted', 'Lapsed')
                                              AND Product_line_link__r.Simple_Product_Line__c = 'CRM'
                                              AND License_basis_link__c != null
                                              GROUP BY Product_line_link__r.Name, Product_line_link__r.Simple_Product_Line__c,Account_Name__c, 
                                              Support_Level__c, License_basis_link__r.Name]){
                                                 
                                                  if(!account_ownership_map.containsKey((ID)pod.get('Account_Name__c'))){
                                                      account_ownership_map.put((ID)pod.get('Account_Name__c'), new Map<String, String>());
                                                      account_supportLevel_map.put((ID)pod.get('Account_Name__c'), new Map<String, String>());
                                                  }
                                                  
                                                  if((String)pod.get('lb') == null) continue;
                                                  
                                                  String convertedCRMMapping = ((String)pod.get('lb')).toLowerCase().contains('oneplace') ? 'OnePlace CRM (Salesforce-Legacy)':'CRM - Cloud';
                                                  account_ownership_map.get((ID)pod.get('Account_Name__c')).put((String)pod.get('spl'), convertedCRMMapping);
                                                  
                                                  String convertedSupportLevel = '';
                                      
                                                  if((String)pod.get('Support_Level__c') == null){
												      convertedSupportLevel = 'Standard';
                                                  }
                                                  else{
                                                      convertedSupportLevel = ((String)pod.get('Support_Level__c')).toLowerCase().contains('premium')?'Premium':'Standard';
                                                  }
                                                  
                                                  account_supportLevel_map.get((ID)pod.get('Account_Name__c')).put((String)pod.get('spl'), convertedSupportLevel);
                                                  
            
        }
            
        for(Id accountId: account_map.keySet()){
            if(!account_ownership_map.containsKey(accountId)){
                //Non - DC Customers with PODs but Lapsed or Converted
            	for(String simpleProductLine: OwnerShipFieldAPIName_map.keySet()){
                	if(account_map.get(accountId).get(OwnerShipFieldAPIName_map.get(simpleProductLine)) != null ||
                       (supportLevelFieldAPIName_map.containsKey(simpleProductLine) && account_map.get(accountId).get(supportLevelFieldAPIName_map.get(simpleProductLine)) != null)){
                    	Account accountToUpdate = new Account();
                        if(map_accountsToUpdate.containsKey(accountId)){
                            accountToUpdate = map_accountsToUpdate.get(accountId);   
                        }
                        else{
                        	accountToUpdate = account_map.get(accountId);
                        }
                        accountToUpdate.put(OwnerShipFieldAPIName_map.get(simpleProductLine),null);
                        if(supportLevelFieldAPIName_map.containsKey(simpleProductLine)) accountToUpdate.put(supportLevelFieldAPIName_map.get(simpleProductLine),null);
                           
                        map_accountsToUpdate.put(accountId, accountToUpdate);
                    }
                }
                continue;
            }
            
            for(String simpleProductLine: OwnerShipFieldAPIName_map.keySet()){
                if(account_ownership_map.get(accountId).containsKey(simpleProductLine)){
                    //System.debug('SPL ' + simpleProductLine + ' check 1');
                    if(account_map.get(accountId).get(OwnerShipFieldAPIName_map.get(simpleProductLine)) != account_ownership_map.get(accountId).get(simpleProductLine)||
                       (supportLevelFieldAPIName_map.containsKey(simpleProductLine) && account_map.get(accountId).get(supportLevelFieldAPIName_map.get(simpleProductLine)) != null)){
                        //System.debug('SPL ' + simpleProductLine + ' check 2');
                    	Account accountToUpdate = new Account();
                        if(map_accountsToUpdate.containsKey(accountId)){
                            accountToUpdate = map_accountsToUpdate.get(accountId);   
                        }
                        else{
                        	accountToUpdate = account_map.get(accountId);
                        }
                        accountToUpdate.put(OwnerShipFieldAPIName_map.get(simpleProductLine),account_ownership_map.get(accountId).get(simpleProductLine));
                        if(supportLevelFieldAPIName_map.containsKey(simpleProductLine)) accountToUpdate.put(supportLevelFieldAPIName_map.get(simpleProductLine),account_supportLevel_map.get(accountId).get(simpleProductLine));
                        map_accountsToUpdate.put(accountId, accountToUpdate);
                    }
                }
                else{
                    
                    if(account_map.get(accountId).get(OwnerShipFieldAPIName_map.get(simpleProductLine)) != null || 
                       (supportLevelFieldAPIName_map.containsKey(simpleProductLine) && account_map.get(accountId).get(supportLevelFieldAPIName_map.get(simpleProductLine)) != null)){
                    	Account accountToUpdate = new Account();
                        if(map_accountsToUpdate.containsKey(accountId)){
                        	accountToUpdate = map_accountsToUpdate.get(accountId);   
                        }
                        else{
                        	accountToUpdate = account_map.get(accountId);
                        }
                        accountToUpdate.put(OwnerShipFieldAPIName_map.get(simpleProductLine),null);
                        if(supportLevelFieldAPIName_map.containsKey(simpleProductLine))accountToUpdate.put(supportLevelFieldAPIName_map.get(simpleProductLine),null);
                        map_accountsToUpdate.put(accountId, accountToUpdate);
                    }
                }
        	} 
        }
        
        String errors = '';
        
        if(map_accountsToUpdate.size() > 0){
            Database.SaveResult[] updateResult = Database.update(map_accountsToUpdate.values(), false);
            for (Database.SaveResult r : updateResult){
                if (!r.isSuccess()){
                	for (Database.Error e : r.getErrors()){ 
                		errors += r.getId() + '-' + e.getMessage() + '<br/>';
                    }
                }
            }
    	}
        
        return String.isBlank(errors)? '':errors;
        
    }
}