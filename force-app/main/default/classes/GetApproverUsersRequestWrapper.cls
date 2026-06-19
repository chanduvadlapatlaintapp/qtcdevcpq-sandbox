public class GetApproverUsersRequestWrapper {
    @AuraEnabled
    @InvocableVariable(label='Sales Segment' description='Sales Segment' )
	public String SalesSegment;
	
    @AuraEnabled
    @InvocableVariable(label='Deal Acv' description='Deal Acv' )
	public Double DealAcv;
}