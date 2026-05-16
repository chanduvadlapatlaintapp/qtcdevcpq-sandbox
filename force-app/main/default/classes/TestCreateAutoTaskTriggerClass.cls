// All test methods in this class can access all data.
@isTest(SeeAllData=true)
public class TestCreateAutoTaskTriggerClass {

    // This test accesses an existing account. 
    // It also creates and accesses a new test account.
    static testmethod void myTestMethod1() {
    CampaignMember c = [Select id from CampaignMember where id ='00v5000000ABU5GAAX'];
    c.status = 'Responded';
    update c;
    }
    }