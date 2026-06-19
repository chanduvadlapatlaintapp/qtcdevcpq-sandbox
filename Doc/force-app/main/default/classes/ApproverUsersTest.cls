@isTest
public class ApproverUsersTest {
    @isTest
    static void ApproverUsers_Verify(){
        Test.startTest();
        ApproverUsers apUsr = new ApproverUsers();
        apUsr.Segment_Lead = NULL;
        apUsr.Industry_Sales_Lead = NULL;
        apUsr.SVP_Sales = NULL;
        apUsr.Industry_President = NULL;
        apUsr.COO = NULL;
        apUsr.Services_Segment_Lead= NULL;
        apUsr.SVP_Services= NULL;
        Test.stopTest();
	}
}