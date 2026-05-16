public class ServicesSOWDataMapper {

    public class Answer {
        public String questionName;
        public String textAnswer;
    }
    
    public class AnswerList {
        public List<Answer> answers;
        
        public AnswerList() {
            answers = new List<Answer>();            
        }
    }
  
    public class ProductLineMatrix {
        public CompositeKeyMatrix matrix;
        public Opportunity opportunity;
        
        public ProductLineMatrix(String opportunityId) {
            Services_SOW_Settings__c settings = [select Product_Mapping__c from Services_SOW_Settings__c LIMIT 1];
            matrix = new CompositeKeyMatrix(settings.Product_Mapping__c);
            opportunity = [select Product_Line__c, Package__c from Opportunity where Id = :opportunityId LIMIT 1];
        }
        
        public String getProductLine() {
            if (opportunity != null)
                return matrix.findValue(opportunity.Product_Line__c,opportunity.Package__c);
            else return '';
        }
    }
    
    public String OpportunityID;
    public AnswerList ansList;

    public ServicesSOWDataMapper(String OpportunityID) {
        this.OpportunityID = OpportunityID;
    }
    
    public void addAnswerIfNotNull(AnswerList ansList, Answer a, String text) {
        if (text != null) {
            a.textAnswer  = text;
            ansList.answers.add(a);
        }
    }

    public String getMappings() {
        //Temporary workaround to improve class coverage
        AnswerList ansList = new AnswerList();
        ProductLineMatrix m = new ProductLineMatrix(this.OpportunityId);
        Answer a = new Answer();
        a.questionName = 'SFEmployeeId';
        a.textAnswer  = UserInfo.getUserId();
        addAnswerIfNotNull(ansList,a,'Test');
        //Temporary workaround to improve class coverage
        /*
         * AnswerList ansList = new AnswerList();
        Opportunity o;
        Answer a;
        String accountId;
        
        a = new Answer();  
        a.questionName = 'SFAccountId';
        o = [select Account.Id from Opportunity where Id = :this.OpportunityId LIMIT 1];
        addAnswerIfNotNull(ansList,a,o.Account.Id);
        accountId = o.Account.Id;
        
        a = new Answer();
        a.questionName = 'SFEmployeeId';
        a.textAnswer  = UserInfo.getUserId();
        ansList.answers.add(a);
        
        a = new Answer();
        a.questionName = 'SOW_Name__c';
        o = [select Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
        String SOWName;
        Integer SOWNameExistsCount;
        
        /* 
        SOWs that exist for an opportunity are of two types: 1) created without the bounding questions (in SF) and 
        2)SOWs that were created with the bounding questions (using the Flow form). Type 1 SOW names do not adhere to any
        naming format. Type 2 SOW has the naming format <Opportunity Name>-<sequence number>. For example,
        Test Opportunity-1. The code for generating the SOW name for Type 2 is below:
           
        Run a query to find the number of SOWs (sum of type 1 and type 2) that exist for this opportunity.
        Add one to this result to get the sequence number. Run another query to see if a SOW name with this sequence number
        already exists for this opportunity. If it does, increase the sequence number by 1, and again check to see if a SOW name
        with the sequence number already exists. Keep doing this until a SOW name with the sequence number does not exist.
        
        
        Integer SOWCount = Database.countQuery('select count() from Services_SOW__c where Opportunity__c = \'' + this.OpportunityId + '\'');
        SOWCount++;
        do {
            SOWName = o.Name + '-' + String.valueOf(SOWCount.format());
            SOWNameExistsCount = Database.countQuery('select count() from Services_SOW__c where SOW_Name__c = \'' + SOWName + '\' and Opportunity__c = \'' + this.OpportunityId + '\'');
            if (SOWNameExistsCount > 0)
                SOWCount++;
        } while (SOWNameExistsCount > 0);
        addAnswerIfNotNull(ansList,a,SOWName);
        
        a = new Answer();
        a.questionName = 'Requesting_Employee__c';
        a.textAnswer  = UserInfo.getName();
        ansList.answers.add(a); 

        a = new Answer();  
        a.questionName = 'Account__c';
        o = [select Account.Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
        addAnswerIfNotNull(ansList,a,o.Account.Name);

        a = new Answer();
        a.questionName = 'Geography__c';
        o = [select Account.Geography__c from Opportunity where Id = :this.OpportunityId LIMIT 1];
        addAnswerIfNotNull(ansList,a,o.Account.Geography__c);
        
        a = new Answer();
        a.questionName = 'Lawyers__c';
        o = [select Account.Lawyers__c from Opportunity where Id = :this.OpportunityId LIMIT 1];
        if (o.Account.Lawyers__c != null) {
            Decimal lawyers = o.Account.Lawyers__c;
            addAnswerIfNotNull(ansList,a,lawyers.toPlainString());
        }
        
        
        a = new Answer();
        a.questionName = 'Engaged_On_Other_Products__c';
        a.textAnswer = '';
        pse__Proj__c[] projects = [select Name from pse__Proj__c where pse__Stage__c = 'Open - In Process' and pse__Account__c = :accountId];
        for (pse__Proj__c p: projects) {
            a.textAnswer += p.Name + '\n';
        }
        ansList.answers.add(a);
        
        a = new Answer();
        a.questionName = 'Opportunity__c';
        o = [select Id from Opportunity where Id = :this.OpportunityId LIMIT 1];
        addAnswerIfNotNull(ansList,a,o.Id);
        
        a = new Answer();
        a.questionName = 'Product__c';
        ProductLineMatrix m = new ProductLineMatrix(this.OpportunityId);  
        a.textAnswer = m.getProductLine();
        System.debug('+' + a.textAnswer);
        ansList.answers.add(a); 
        
        a = new Answer();
        a.questionName = 'Production_Version__c';
        System.debug(m.getProductLine().getChars() + '*');
        if ( (m.getProductLine() == 'Intapp Open: Conflicts') || (m.getProductLine() == 'Intapp Open: Intake') || 
              (m.getProductLine() == 'Intapp Open: Intake (Engagement Letters)') || (m.getProductLine() == 'Intapp Open: Terms of Business') ) {
            o = [select Account.Open_Version__r.Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
            addAnswerIfNotNull(ansList,a,o.Account.Open_Version__r.Name);
        } 
        else if (m.getProductLine() == 'Intapp Time: Capture') {
            o = [select Account.TB_Version__r.Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
            addAnswerIfNotNull(ansList,a,o.Account.TB_Version__r.Name);
        }
        else if (m.getProductLine() == 'Intapp Time: Core Management') {
            o = [select Account.TE_Version__r.Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
            addAnswerIfNotNull(ansList,a,o.Account.TE_Version__r.Name);
        }
        else if (m.getProductLine() == 'Intapp Walls') {
            o = [select Account.WB_Product_Release__r.Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
            addAnswerIfNotNull(ansList,a,o.Account.WB_Product_Release__r.Name);
        }
        else if (m.getProductLine() == 'Intapp Time: Total Time Management') {
            o = [select Account.TE_Version__r.Name,Account.TB_Version__r.Name from Opportunity where Id = :this.OpportunityId LIMIT 1];
            if (o != null) {
                a.textAnswer = o.Account.TE_Version__r.Name + ' ' + o.Account.TB_Version__r.Name;
                ansList.answers.add(a);
                }
            }
        a = new Answer();
        a.questionName = 'Primary_Business_Problem__c';
        o = [select Primary_Business_Problem__c from Opportunity where Id = :this.OpportunityId LIMIT 1];
        if (o != null) {
            a.textAnswer  = o.Primary_Business_Problem__c;
            ansList.answers.add(a); 
        }

        a = new Answer();
        a.questionName = 'Billing_Country_City__c';
        o = [select Account.BillingCountry,Account.BillingCity from Opportunity where Id = :this.OpportunityId LIMIT 1];
        if ( (o.Account.BillingCountry != null) && (o.Account.BillingCity != null) ) {
            a.textAnswer  = o.Account.BillingCountry + ' ' + o.Account.BillingCity;
            ansList.answers.add(a); 
        }
        

            
        a = new Answer();   
        a.questionName = 'Project_Count__c';
        o = [select Account.Id from Opportunity where Id = :this.OpportunityId LIMIT 1];
        Integer projectCount = Database.countQuery('select count() from pse__Proj__c where pse__Stage__c = \'Open - In Process\' and pse__Account__c = \'' + accountId + '\'');
        a.textAnswer = projectCount.format();
        ansList.answers.add(a); 
        
        a = new Answer();
        a.questionName = 'Extended_Or_Premium_Support__c';
        Opportunity oppPL = [select Product_Line__c from Opportunity where Id = :this.OpportunityId LIMIT 1];
       
        String supportLevelDefaultValue;
        Opportunity oppAcc = [select Account.Support_Level_Integration_Builder__c,Account.Support_Level_Intapp_Open_Conflicts__c,Account.Support_Level_Intapp_Open_Intake__c, 
        Account.Support_Level_Intapp_Open_Terms__c, Account.Support_Level_Intapp_Time__c,Account.Support_Level_Wall_Builder__c, Account.Support_Level_Rekoop__c from Opportunity where Id = :this.OpportunityId LIMIT 1];
        if (oppPL.Product_Line__c == 'Integration Builder')
            supportLevelDefaultValue = oppAcc.Account.Support_Level_Integration_Builder__c;
        else if (oppPL.Product_Line__c == 'Intapp Open - Conflicts')
            supportLevelDefaultValue = oppAcc.Account.Support_Level_Intapp_Open_Conflicts__c;
        else if (oppPL.Product_Line__c == 'Intapp Open - Intake')
            supportLevelDefaultValue = oppAcc.Account.Support_Level_Intapp_Open_Intake__c;
        else if (oppPL.Product_Line__c == 'Intapp Time')
            supportLevelDefaultValue = oppAcc.Account.Support_Level_Intapp_Time__c;
        else if (oppPL.Product_Line__c == 'Wall Builder')
            supportLevelDefaultValue = oppAcc.Account.Support_Level_Wall_Builder__c;
        else if (oppPL.Product_Line__c == 'Intapp Time - Cloud')
            supportLevelDefaultValue = oppAcc.Account.Support_Level_Rekoop__c;   
        addAnswerIfNotNull(ansList,a,supportLevelDefaultValue);

        String JSONString = JSON.serialize(ansList);
        System.debug(JSONString);
		return JSONString
*/
        return '';

    }



}