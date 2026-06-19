/********************************************************************************     
 *  Name             :  SubscriptionHelper
 *  Author           :  Intapp
 *  Description      :  Merge Subscriptions
 *
 *  Change history   :
 *  Date            Author                      Description
 *  05/05/15        Alan Westley                Initial release 


  Status
  XX Opportunities
  XX CR Engagements
  XX Item Master Subscription Links
  XX Opportunity Product
  XX Survey Requests
  XX Projects
  XX Surveys
  XX Subscription Contacts
  XX Subscription Contract Links
  XX Tasks
  XX Events
  Activity History
  Chatter Feed
  Invoices (go to terms)

  SELECT ID, (SELECT Id FROM ActivityHistories) from Subscription__c WHERE Id = 'a1A50000000a5SCEAY'
 ********************************************************************************/
global class SubscriptionHelper {
    public static String mergeSubscriptionsForAccount(String accountNumber)
    {
        Account account = [Select Id from Account where IntApp_Account_Number__c = :accountNumber LIMIT 1];
        return mergeSubscriptionsForAccount(account.Id);
    }

    public static String mergeSubscriptionsForAccount(Id accountID)
    {
        //Set up objects that will be updated
        List<Opportunity> oppsToUpdate = new List<Opportunity> ();
        List<Task> tasksToUpdate = new List<Task> ();
        List<Event> eventsToUpdate = new List<Event> ();
        List<CR_Engagement__c> crsToUpdate = new List<CR_Engagement__c> ();
        List<Item_Master_Subscription_Link__c> imslToUpdate = new List<Item_Master_Subscription_Link__c> ();
        List<OpportunityLineItem> oliToUpdate = new List<OpportunityLineItem> ();
        List<Survey_Request__c> requestsToUpdate = new List<Survey_Request__c> ();
        //List<Survey__c> surveysToUpdate = new List<Survey__c> ();
        List<Subscription_Contact__c> contactsToUpdate = new List<Subscription_Contact__c> ();
        List<Subscription_Contact__c> contactsToDelete = new List<Subscription_Contact__c> ();
        List<Subscription_Contract_Link__c> sclToUpdate = new List<Subscription_Contract_Link__c> ();

        //Get primary subscriptions
        List<Subscription__c> primarySubscriptions = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c
                                                      FROM Subscription__c WHERE Account__c = :accountID AND Primary_Subscription__c = true];
        system.debug(primarySubscriptions.size() + ' primary subscriptions found');


        //Loop over and get non-primary subscriptions for product line
        for (Subscription__c primarysub : primarySubscriptions)
        {
            List<Subscription__c> nonprimarySubscriptions = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c
                                                             FROM Subscription__c WHERE Account__c = :accountID AND Primary_Subscription__c = false
                                                             AND Product_Line__c = :primarysub.Product_Line__c];
            system.debug(nonprimarySubscriptions.size() + ' non-primary subscriptions found for ' + primarysub.Product_Line__c);

            string nonsublist = '';

            for (Subscription__c nonprimarySub : nonprimarySubscriptions)
            {
                system.debug('Attempting to merge subscription ' + nonprimarySub.Name + ' to ' + primarysub.Name);
                nonsublist += nonprimarySub.Name + ';';
                //Update Opportunities
                List<Opportunity> opps = [SELECT Id, Subscription__c FROM Opportunity WHERE Subscription__c = :nonprimarySub.Id];
                for (Opportunity opp : opps)
                {
                    opp.Subscription__c = primarysub.Id;
                }
                oppsToUpdate.addAll(opps);
                system.debug(opps.size() + ' ' + primarysub.Product_Line__c + ' opportunities updated');

                //Update Tasks
                List<Task> tasks = [SELECT Id, WhatId from Task WHERE WhatId = :nonprimarySub.Id];
                for (Task item : tasks)
                {
                    item.WhatId = primarysub.Id;
                }
                tasksToUpdate.addAll(tasks);
                system.debug(tasks.size() + ' ' + primarysub.Product_Line__c + ' Tasks updated');

                //Update Events
                List<Event> events = [SELECT Id, WhatId from Event WHERE WhatId = :nonprimarySub.Id];
                for (Event item : events)
                {
                    item.WhatId = primarysub.Id;
                }
                eventsToUpdate.addAll(events);
                system.debug(events.size() + ' ' + primarysub.Product_Line__c + ' Events updated');

                //Update CR Engagements
                List<CR_Engagement__c> engagements = [SELECT Id, Subscription__c from CR_Engagement__c WHERE Subscription__c = :nonprimarySub.Id];
                for (CR_Engagement__c item : engagements)
                {
                    item.Subscription__c = primarysub.Id;
                }
                crsToUpdate.addAll(engagements);
                system.debug(engagements.size() + ' ' + primarysub.Product_Line__c + ' CR engagements updated');

                //Update Item Master Subscription Links
                List<Item_Master_Subscription_Link__c> sublinks = [SELECT Id, Subscription__c from Item_Master_Subscription_Link__c WHERE Subscription__c = :nonprimarySub.Id];
                for (Item_Master_Subscription_Link__c item : sublinks)
                {
                    item.Subscription__c = primarysub.Id;
                }
                imslToUpdate.addAll(sublinks);
                system.debug(sublinks.size() + ' ' + primarysub.Product_Line__c + ' Item Master Subscription Links updated');

                //Update Opportunity Line Items
                List<OpportunityLineItem> olitems = [SELECT Id, Subscription__c from OpportunityLineItem WHERE Subscription__c = :nonprimarySub.Id];
                for (OpportunityLineItem item : olitems)
                {
                    item.Subscription__c = primarysub.Id;
                }
                oliToUpdate.addAll(olitems);
                system.debug(olitems.size() + ' ' + primarysub.Product_Line__c + ' Item Master Subscription Links updated');

                //Update Survey Requests
                List<Survey_Request__c> surreqs = [SELECT Id, Subscription__c from Survey_Request__c WHERE Subscription__c = :nonprimarySub.Id];
                for (Survey_Request__c item : surreqs)
                {
                    item.Subscription__c = primarysub.Id;
                }
                requestsToUpdate.addAll(surreqs);
                system.debug(surreqs.size() + ' ' + primarysub.Product_Line__c + ' Survey Requests updated');

                ////Update Surveys
                //List<Survey__c> surveys = [SELECT Id, Subscription__c from Survey__c WHERE Subscription__c = :nonprimarySub.Id];
                //for (Survey__c item : surveys)
                //{
                    //item.Subscription__c = primarysub.Id;
                //}
                //surveysToUpdate.addAll(surveys);
                //system.debug(surveys.size() + ' ' + primarysub.Product_Line__c + ' Surveys updated');

                //Update Subscription Contract Links
                List<Subscription_Contract_Link__c> fromContractLinks = [SELECT Id, Contract__c, Subscription__c, CurrencyISOCode FROM Subscription_Contract_Link__c WHERE Subscription__c = :nonprimarySub.Id];
                for (Subscription_Contract_Link__c item : fromContractLinks)
                {
                    item.Subscription__c = primarysub.Id;
                }
                sclToUpdate.addAll(fromContractLinks);
                system.debug(fromContractLinks.size() + ' ' + primarysub.Product_Line__c + ' Subscription Contract Links updated');

                //Update Subscription Contacts
                Integer contactsupdated = 0;
                Integer contactsnotupdated = 0;
                List<Subscription_Contact__c> deleteContacts = new List<Subscription_Contact__c> ();
                List<Subscription_Contact__c> fromContacts = [SELECT Id, Contact__c, Subscription__c, Role__c FROM Subscription_Contact__c WHERE Subscription__c = :nonprimarySub.Id];
                List<Subscription_Contact__c> toContacts = [SELECT Id, Contact__c, Role__c FROM Subscription_Contact__c WHERE Subscription__c = :primarysub.Id];
                Map<string, Subscription_Contact__c> existingContacts = new Map<string, Subscription_Contact__c> ();
                for (Subscription_Contact__c contact : toContacts)
                {
                    existingContacts.put(contact.Contact__c + '|' + contact.Role__c, contact);
                }
                for (Subscription_Contact__c contact : fromContacts)
                {
                    if (!existingContacts.containsKey(contact.Contact__c + '|' + contact.Role__c))
                    {
                        contactsupdated += 1;
                        contact.Subscription__c = primarysub.Id;
                    }
                    else
                    {
                        contactsnotupdated += 1;
                        deleteContacts.add(contact);
                    }
                }
                contactsToUpdate.addAll(fromContacts);
                contactsToDelete.addAll(contactsToDelete);
                String results;
                system.debug(contactsupdated + ' ' + primarysub.Product_Line__c + ' Contacts updated');
                if (contactsnotupdated > 0) { system.debug(contactsnotupdated + ' ' + primarysub.Product_Line__c + ' Contacts NOT updated (already existing)'); }
            }

            primarysub.Old_Subscription_Numbers__c = nonsublist;
            update primarysub;
        }


        //Make changes
        update oppsToUpdate;
        update tasksToUpdate;
        update eventsToUpdate;
        update crsToUpdate;
        update imslToUpdate;
        update oliToUpdate;
        update requestsToUpdate;
        //update surveysToUpdate;
        update contactsToUpdate;
        delete contactsToDelete;
        update sclToUpdate;
        system.debug('Changes saved');

        return 'Migration completed for account ' + accountID;
    }

    public static void mergeSubscriptionsForPrimarySubscription(Id primarySubId)
    {
        //Set up objects that will be updated
        List<Opportunity> oppsToUpdate = new List<Opportunity> ();
        List<Task> tasksToUpdate = new List<Task> ();
        List<Event> eventsToUpdate = new List<Event> ();
        List<CR_Engagement__c> crsToUpdate = new List<CR_Engagement__c> ();
        List<Item_Master_Subscription_Link__c> imslToUpdate = new List<Item_Master_Subscription_Link__c> ();
        List<OpportunityLineItem> oliToUpdate = new List<OpportunityLineItem> ();
        List<Survey_Request__c> requestsToUpdate = new List<Survey_Request__c> ();
        //List<Survey__c> surveysToUpdate = new List<Survey__c> ();
        List<Subscription_Contact__c> contactsToUpdate = new List<Subscription_Contact__c> ();
        List<Subscription_Contact__c> contactsToDelete = new List<Subscription_Contact__c> ();
        List<Subscription_Contract_Link__c> sclToUpdate = new List<Subscription_Contract_Link__c> ();

        //Get primary subscriptions
        List<Subscription__c> primarySubscriptions = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c
                                                      FROM Subscription__c WHERE Id = :primarySubId AND Primary_Subscription__c = true];
        system.debug(primarySubscriptions.size() + ' primary subscriptions found');


        //Loop over and get non-primary subscriptions for product line
        for (Subscription__c primarysub : primarySubscriptions)
        {
            List<Subscription__c> nonprimarySubscriptions = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c
                                                             FROM Subscription__c WHERE Account__c = :primarysub.Account__c AND Primary_Subscription__c = false
                                                             AND Product_Line__c = :primarysub.Product_Line__c];
            system.debug(nonprimarySubscriptions.size() + ' non-primary subscriptions found for ' + primarysub.Product_Line__c);

            string nonsublist = '';

            for (Subscription__c nonprimarySub : nonprimarySubscriptions)
            {
                system.debug('Attempting to merge subscription ' + nonprimarySub.Name + ' to ' + primarysub.Name);
                nonsublist += nonprimarySub.Name + ';';
                //Update Opportunities
                List<Opportunity> opps = [SELECT Id, Subscription__c FROM Opportunity WHERE Subscription__c = :nonprimarySub.Id];
                for (Opportunity opp : opps)
                {
                    opp.Subscription__c = primarysub.Id;
                }
                oppsToUpdate.addAll(opps);
                system.debug(opps.size() + ' ' + primarysub.Product_Line__c + ' opportunities updated');

                //Update Tasks
                List<Task> tasks = [SELECT Id, WhatId from Task WHERE WhatId = :nonprimarySub.Id];
                for (Task item : tasks)
                {
                    item.WhatId = primarysub.Id;
                }
                tasksToUpdate.addAll(tasks);
                system.debug(tasks.size() + ' ' + primarysub.Product_Line__c + ' Tasks updated');

                //Update Events
                List<Event> events = [SELECT Id, WhatId from Event WHERE WhatId = :nonprimarySub.Id];
                for (Event item : events)
                {
                    item.WhatId = primarysub.Id;
                }
                eventsToUpdate.addAll(events);
                system.debug(events.size() + ' ' + primarysub.Product_Line__c + ' Events updated');

                //Update CR Engagements
                List<CR_Engagement__c> engagements = [SELECT Id, Subscription__c from CR_Engagement__c WHERE Subscription__c = :nonprimarySub.Id];
                for (CR_Engagement__c item : engagements)
                {
                    item.Subscription__c = primarysub.Id;
                }
                crsToUpdate.addAll(engagements);
                system.debug(engagements.size() + ' ' + primarysub.Product_Line__c + ' CR engagements updated');

                //Update Item Master Subscription Links
                List<Item_Master_Subscription_Link__c> sublinks = [SELECT Id, Subscription__c from Item_Master_Subscription_Link__c WHERE Subscription__c = :nonprimarySub.Id];
                for (Item_Master_Subscription_Link__c item : sublinks)
                {
                    item.Subscription__c = primarysub.Id;
                }
                imslToUpdate.addAll(sublinks);
                system.debug(sublinks.size() + ' ' + primarysub.Product_Line__c + ' Item Master Subscription Links updated');

                //Update Opportunity Line Items
                List<OpportunityLineItem> olitems = [SELECT Id, Subscription__c from OpportunityLineItem WHERE Subscription__c = :nonprimarySub.Id];
                for (OpportunityLineItem item : olitems)
                {
                    item.Subscription__c = primarysub.Id;
                }
                oliToUpdate.addAll(olitems);
                system.debug(olitems.size() + ' ' + primarysub.Product_Line__c + ' Item Master Subscription Links updated');

                //Update Survey Requests
                List<Survey_Request__c> surreqs = [SELECT Id, Subscription__c from Survey_Request__c WHERE Subscription__c = :nonprimarySub.Id];
                for (Survey_Request__c item : surreqs)
                {
                    item.Subscription__c = primarysub.Id;
                }
                requestsToUpdate.addAll(surreqs);
                system.debug(surreqs.size() + ' ' + primarysub.Product_Line__c + ' Survey Requests updated');

                ////Update Surveys
                //List<Survey__c> surveys = [SELECT Id, Subscription__c from Survey__c WHERE Subscription__c = :nonprimarySub.Id];
                //for (Survey__c item : surveys)
                //{
                    //item.Subscription__c = primarysub.Id;
                //}
                //surveysToUpdate.addAll(surveys);
                //system.debug(surveys.size() + ' ' + primarysub.Product_Line__c + ' Surveys updated');

                //Update Subscription Contract Links
                List<Subscription_Contract_Link__c> fromContractLinks = [SELECT Id, Contract__c, Subscription__c, CurrencyISOCode FROM Subscription_Contract_Link__c WHERE Subscription__c = :nonprimarySub.Id];
                for (Subscription_Contract_Link__c item : fromContractLinks)
                {
                    item.Subscription__c = primarysub.Id;
                }
                sclToUpdate.addAll(fromContractLinks);
                system.debug(fromContractLinks.size() + ' ' + primarysub.Product_Line__c + ' Subscription Contract Links updated');

                //Update Subscription Contacts
                Integer contactsupdated = 0;
                Integer contactsnotupdated = 0;
                List<Subscription_Contact__c> deleteContacts = new List<Subscription_Contact__c> ();
                List<Subscription_Contact__c> fromContacts = [SELECT Id, Contact__c, Subscription__c, Role__c FROM Subscription_Contact__c WHERE Subscription__c = :nonprimarySub.Id];
                List<Subscription_Contact__c> toContacts = [SELECT Id, Contact__c, Role__c FROM Subscription_Contact__c WHERE Subscription__c = :primarysub.Id];
                Map<string, Subscription_Contact__c> existingContacts = new Map<string, Subscription_Contact__c> ();
                for (Subscription_Contact__c contact : toContacts)
                {
                    existingContacts.put(contact.Contact__c + '|' + contact.Role__c, contact);
                }
                for (Subscription_Contact__c contact : fromContacts)
                {
                    if (!existingContacts.containsKey(contact.Contact__c + '|' + contact.Role__c))
                    {
                        contactsupdated += 1;
                        contact.Subscription__c = primarysub.Id;
                    }
                    else
                    {
                        contactsnotupdated += 1;
                        deleteContacts.add(contact);
                    }
                }
                contactsToUpdate.addAll(fromContacts);
                contactsToDelete.addAll(contactsToDelete);
                String results;
                system.debug(contactsupdated + ' ' + primarysub.Product_Line__c + ' Contacts updated');
                if (contactsnotupdated > 0) { system.debug(contactsnotupdated + ' ' + primarysub.Product_Line__c + ' Contacts NOT updated (already existing)'); }
            }

            primarysub.Old_Subscription_Numbers__c = nonsublist;
            update primarysub;
        }


        //Make changes
        update oppsToUpdate;
        update tasksToUpdate;
        update eventsToUpdate;
        update crsToUpdate;
        update imslToUpdate;
        update oliToUpdate;
        update requestsToUpdate;
        //update surveysToUpdate;
        update contactsToUpdate;
        delete contactsToDelete;
        update sclToUpdate;
        system.debug('Changes saved');

        //return 'Migration completed for account ' + accountID;
    }

    //webservice static String MergeSubscriptionsToTerms(Id primarySubID)
    //{
    //String results = null;

    ////Get primary subscription and verify information
    //Subscription__c primarySubscription = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c from Subscription__c WHERE Id = :primarySubID LIMIT 1];
    //if (primarySubscription == null)
    //{
    //results = 'Unable to find Subscription. Please check ID and try again';
    //return results;
    //}
    //if (primarySubscription.Primary_Subscription__c == false)
    //{
    //results = 'This subscription is not the primary subscription for this product line';
    //return results;
    //}

    ////Find non-primary subscriptions for primary subscription (same account, same product line)
    //List<Subscription__c> subscriptions = [SELECT ID, Name, Account__c, Product_Line__c from Subscription__c
    //WHERE Account__c = :primarySubscription.Account__c
    //AND Product_Line__c = :primarySubscription.Product_Line__c
    //AND Primary_Subscription__c = false];
    //if (subscriptions.size() == 0)
    //{
    //results = 'There are no non-primary subscriptions for this subscription. Nothing processed';
    //return results;
    //}

    ////Loop over subscriptions and move to terms
    //for (Subscription__c subscription : subscriptions)
    //{
    //results += MoveOpportunities(subscription, primarySubscription);
    ////results += MoveActivityHistory(subscription, primarySubscription);
    //results += MoveTasks(subscription, primarySubscription);
    //results += MoveEvents(subscription, primarySubscription);
    //results += MoveCREngagements(subscription, primarySubscription);
    //results += MoveItemMasterSubscriptionLinks(subscription, primarySubscription);
    //results += MoveOpportunityProducts(subscription, primarySubscription);
    //results += MoveSurveyRequests(subscription, primarySubscription);
    //results += MoveProjects(subscription, primarySubscription);
    //results += MoveSurveys(subscription, primarySubscription);
    //results += MoveSubscriptionContacts(subscription, primarySubscription);
    //results += MoveSubscriptionContractLinks(subscription, primarySubscription);
    ////results += MoveChatterFeeds(subscription, primarySubscription);
    ////results += MoveInvoices(subscription, primarySubscription);
    //}

    //return results;
    //}

    public static String createTermsForInvoices(string primarySubId)
    {
        Subscription__c sub = [SELECT Id, Account__c, Product_Line__c FROM Subscription__c WHERE Id = :primarySubId LIMIT 1];
        return createTermsForInvoices(sub);
    }

    public static String createTermsForInvoices(Subscription__c primarySub)
    {
        //Get List of existing terms and map by OSA Number
        List<Term__c> terms = [SELECT Id, OSA_Number__c FROM Term__c WHERE Product_Customer_Number__c = :primarySub.Id];
        Map<String, Term__c> termMap = new Map<String, Term__c> ();
        for (Term__c term : terms)
        {
            termMap.put(term.OSA_Number__c, term);
        }
        system.debug(termMap.size() + ' terms existing');

        //*************
        //Get Invoices
        //*************

        //Get Invoices #1 - Search for Invoice Subscription Links for product line for this account
        List<Invoice_Subscription_Link__c> invoicesubscriptionlinks = [select Invoice__r.Id, Subscription__r.Name
                                                                       //, Invoice__r.Name, Invoice__r.Related_OSA__c, Invoice__r.OSA_Number__c, Invoice__r.NS_Rev_Rec_Start_Date__c, 
                                                                       //Invoice__r.Latest_NS_Rev_Rec_Date__c, Invoice__r.Due_Date__c
                                                                       FROM Invoice_Subscription_Link__c
                                                                       WHERE Subscription__r.Account__c = :primarySub.Account__c
                                                                       AND Subscription__r.Product_Line__c = :primarySub.Product_Line__c
                                                                       //AND Invoice__r.Sales_Order_Type__c = 'New license sale'
                                                                      ];

        system.debug(invoicesubscriptionlinks.size() + ' invoicesubscriptionlinks found');

        //Get Invoices #2 = Get set of unique invoice IDs
        Set<Id> islIDs = new Set<Id> ();
        for (Invoice_Subscription_Link__c isl : invoicesubscriptionlinks)
        {
            islIDs.add(isl.Invoice__r.Id);
        }

        //Get Invoices #3 - Get all Invoices for this product line
        List<Invoice__c> productInvoices = [SELECT Id, Name, Related_OSA__c, OSA_Number__c, NS_Rev_Rec_Start_Date__c,
                                            Latest_NS_Rev_Rec_Date__c, Due_Date__c FROM Invoice__c WHERE Id IN :islIDs];

        system.debug(productInvoices.size() + ' total invoices found for product line');

        //Generate map of invoices to contracts (OSAs)
        Map<Id, List<Invoice__c>> icMap = new Map<Id, List<Invoice__c>> ();
        for (Invoice__c invoice : productInvoices)
        {
            if (icMap.containsKey(invoice.Related_OSA__c))
            {
                List<Invoice__c> invoicesexistingList = icMap.get(invoice.Related_OSA__c);
                invoicesexistingList.add(invoice);
            }
            else
            {
                List<Invoice__c> newinvoicesMapList = new List<Invoice__c> ();
                newinvoicesMapList.add(invoice);
                icMap.put(invoice.Related_OSA__c, newinvoicesMapList);
            }
        }

        //Create terms for each OSA and add invoices
        List<Term_Invoice_Link__c> tILs = new List<Term_Invoice_Link__c> ();
        List<Term__c> newTerms = new List<Term__c> ();
        for (Id oSAId : icMap.keySet())
        {
            List<Invoice__c> invoices = icMap.get(oSAId);
            Term__c term = null;
            if (termMap.containsKey(invoices[0].OSA_Number__c))
            {
                //Get existing Term
                term = termMap.get(invoices[0].OSA_Number__c);
            }
            else
            {
                //Create new Term
                term = new Term__c();
                term.Product_Customer_Number__c = primarySub.Id;
                term.OSA_Number__c = invoices[0].OSA_Number__c;
                term.Start_Date__c = invoices[0].NS_Rev_Rec_Start_Date__c;
                term.Term_End_Date__c = invoices[0].Latest_NS_Rev_Rec_Date__c;
                term.Status__c = 'Active';
                insert term;
            }

            for (Invoice__c invoice : invoices)
            {
                Term_Invoice_Link__c newTIL = new Term_Invoice_Link__c();
                newTIL.Invoice__c = invoice.Id;
                newTIL.Term__c = term.Id;
                tILs.add(newTIL);
            }
        }

        insert tILs;

        return tILs.size() + ' Terms created or updated';
    }

    //public static String MoveOpportunities(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<Opportunity> opps = [SELECT Id, Subscription__c FROM Opportunity WHERE Subscription__c = :fromSubscription.Id];
    //for (Opportunity opp : opps)
    //{
    //opp.Subscription__c = toSubscription.Id;
    //}
    //update opps;
    //return opps.size() + ' opportunities updated\n';
    //}

    ////public static String MoveActivityHistory(Subscription__c fromSubscription, Subscription__c toSubscription)
    ////{
    ////List<Task> activitiesToInsert = new List<Task> ();
    ////List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :fromSubscription.Id ALL ROWS];
    ////for (Task task : tasks)
    ////{
    ////Task newtask = task.clone(false, true, true, true);
    ////newtask.WhatId = toSubscription.Id;
    ////activitiesToInsert.add(newtask);
    ////}
    ////insert activitiesToInsert;
    ////return activitiesToInsert.size() + ' tasks updated\n';
    ////}

    //public static String MoveTasks(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<Task> tasks = [SELECT Id, WhatId from Task WHERE WhatId = :fromSubscription.Id];
    //for (Task item : tasks)
    //{
    //item.WhatId = toSubscription.Id;
    //}
    //update tasks;
    //return tasks.size() + ' Tasks updated\n';
    //}

    //public static String MoveEvents(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<Event> tasks = [SELECT Id, WhatId from Event WHERE WhatId = :fromSubscription.Id];
    //for (Event item : tasks)
    //{
    //item.WhatId = toSubscription.Id;
    //}
    //update tasks;
    //return tasks.size() + ' Events updated\n';
    //}

    //public static String MoveCREngagements(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<CR_Engagement__c> engagements = [SELECT Id, Subscription__c from CR_Engagement__c WHERE Subscription__c = :fromSubscription.Id];
    //for (CR_Engagement__c item : engagements)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update engagements;
    //return engagements.size() + ' CR engagements updated\n';
    //}

    //public static String MoveItemMasterSubscriptionLinks(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //// Item Master Subscription Link // 
    //List<Item_Master_Subscription_Link__c> sublinks = [SELECT Id, Subscription__c from Item_Master_Subscription_Link__c WHERE Subscription__c = :fromSubscription.Id];
    //for (Item_Master_Subscription_Link__c item : sublinks)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update sublinks;
    //return sublinks.size() + ' Item Master Subscription Links updated\n';
    //}

    //public static String MoveOpportunityProducts(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<OpportunityLineItem> olitems = [SELECT Id, Subscription__c from OpportunityLineItem WHERE Subscription__c = :fromSubscription.Id];
    //for (OpportunityLineItem item : olitems)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update olitems;
    //return olitems.size() + ' Item Master Subscription Links updated\n';
    //}

    //public static String MoveSurveyRequests(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<Survey_Request__c> surreqs = [SELECT Id, Subscription__c from Survey_Request__c WHERE Subscription__c = :fromSubscription.Id];
    //for (Survey_Request__c item : surreqs)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update surreqs;
    //return surreqs.size() + ' Survey Requests updated\n';
    //}

    //public static String MoveProjects(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<pse__Proj__c> projects = [SELECT Id, Subscription__c from pse__Proj__c WHERE Subscription__c = :fromSubscription.Id];
    //for (pse__Proj__c item : projects)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update projects;
    //return projects.size() + ' Projects updated\n';
    //}

    //public static String MoveSurveys(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<Survey__c> surveys = [SELECT Id, Subscription__c from Survey__c WHERE Subscription__c = :fromSubscription.Id];
    //for (Survey__c item : surveys)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update surveys;
    //return surveys.size() + ' Surveys updated\n';
    //}

    //public static String MoveSubscriptionContacts(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //Integer contactsupdated = 0;
    //Integer contactsnotupdated = 0;
    //List<Subscription_Contact__c> contactsToDelete = new List<Subscription_Contact__c> ();
    //List<Subscription_Contact__c> fromContacts = [SELECT Id, Contact__c, Subscription__c, Role__c FROM Subscription_Contact__c WHERE Subscription__c = :fromSubscription.Id];
    //List<Subscription_Contact__c> toContacts = [SELECT Id, Contact__c, Role__c FROM Subscription_Contact__c WHERE Subscription__c = :toSubscription.Id];
    //Map<string, Subscription_Contact__c> existingContacts = new Map<string, Subscription_Contact__c> ();
    //for (Subscription_Contact__c contact : toContacts)
    //{
    //existingContacts.put(contact.Contact__c + '|' + contact.Role__c, contact);
    //}
    //for (Subscription_Contact__c contact : fromContacts)
    //{
    //if (!existingContacts.containsKey(contact.Contact__c + '|' + contact.Role__c))
    //{
    //contactsupdated += 1;
    //contact.Subscription__c = toSubscription.Id;
    //}
    //else
    //{
    //contactsnotupdated += 1;
    //contactsToDelete.add(contact);
    //}
    //}
    //update fromContacts;
    //delete contactsToDelete;
    //String results;
    //results += contactsupdated + ' Contacts updated\n';
    //if (contactsnotupdated > 0) { results += contactsnotupdated + ' Contacts NOT updated (already existing)\n'; }
    //return results;
    //}

    //public static String MoveSubscriptionContractLinks(Subscription__c fromSubscription, Subscription__c toSubscription)
    //{
    //List<Subscription_Contract_Link__c> fromContractLinks = [SELECT Id, Contract__c, Subscription__c, CurrencyISOCode FROM Subscription_Contract_Link__c WHERE Subscription__c = :fromSubscription.Id];
    //for (Subscription_Contract_Link__c item : fromContractLinks)
    //{
    //item.Subscription__c = toSubscription.Id;
    //}
    //update fromContractLinks;
    //return fromContractLinks.size() + ' Subscription Contract Links updated\n';

    //List<Subscription_Contract_Link__c> fromContracts = [SELECT Id, Contract__c, Subscription__c, CurrencyISOCode FROM Subscription_Contract_Link__c WHERE Subscription__c = :fromSubscription.Id];
    //List<Subscription_Contract_Link__c> toContracts = [SELECT Id, Contract__c, Subscription__c, CurrencyISOCode FROM Subscription_Contract_Link__c WHERE Subscription__c = :toSubscription.Id];
    //List<Subscription_Contract_Link__c> newContracts = new List<Subscription_Contract_Link__c> ();
    //Map<Id, Subscription_Contract_Link__c> existingContracts = new Map<Id, Subscription_Contract_Link__c> ();
    //for (Subscription_Contract_Link__c link : toContracts)
    //{
    //existingContracts.put(link.Contract__c, link);
    //}
    //for (Subscription_Contract_Link__c link : fromContracts)
    //{
    //if (!existingContracts.containsKey(link.Contract__c))
    //{
    //Subscription_Contract_Link__c newLink = new Subscription_Contract_Link__c();
    //newLink.Contract__c = link.Contract__c;
    //newlink.Subscription__c = toSubscription.Id;
    //newContracts.add(newlink);
    //}
    ////Delete the old subscription links?
    //}
    //if (newContracts.size() > 0) {
    //insert newContracts;
    //}
    //return newContracts.size() + ' Subscription Contract Links updated\n';
}

//public static String MoveChatterFeeds(Subscription__c fromSubscription, Subscription__c toSubscription)
//{
//List<FeedItem> feeds = [SELECT Id, ParentId from FeedItem WHERE ParentId = :fromSubscription.Id];
//for (Feeditem item : feeds)
//{
//item.ParentId = toSubscription.Id;
//}
//update feeds;
//return feeds.size() + ' Chatter Feed Items updated\n';
//}

//public static String MoveInvoices(Subscription__c fromSubscription, Subscription__c toSubscription)
//{
//List<Invoice_Subscription_Link__c> toInvoices = [SELECT Id, Invoice__c, Invoice__r.Name, Subscription__c, CurrencyISOCode FROM Invoice_Subscription_Link__c WHERE Subscription__c = :toSubscription.Id];
//Map<Id, Invoice_Subscription_Link__c> existingInvoices = new Map<Id, Invoice_Subscription_Link__c> ();
//for (Invoice_Subscription_Link__c link : toInvoices)
//{
//existingInvoices.put(link.Invoice__c, link);
//}

//Id termID = null;
////Look for existing terms object
//Term__c existingTerm = [SELECT Id FROM Term__c WHERE Old_Susbcription_Number__c = :fromSubscription.Id LIMIT 1];
//if (existingTerm == null)
//{
////Term__c newTerm = new Term__c();
////newTerm.Old_Subscription_Number__c = fromSubscription.Name;
////newTerm.Product_Customer_Number__c = toSubscription.Id;
////newTerm.Term_End_Date__c = fromSubscription.Term_End_Date__c;
////newTerm.Recurring_Amount__c = fromSubscription.Amount__c;
//////DON'T WORRY ABOUT ONE-TIME AMOUNT OR START DATE FOR NOW
////insert newTerm;
////termId = newTerm.Id;
//}
//else
//{
//termId = existingTerm.Id;
//}

//return '';
//}
//}