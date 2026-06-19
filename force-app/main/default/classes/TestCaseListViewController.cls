@isTest
private class TestCaseListViewController {
	
	@isTest static void test_method_one() {
		new CaseListViewController().listName = 'Test';
	}
    
    //Added By Pooja Hemrajani - 07/02/2025
    @isTest static void test_with_existing_list_view() {
        // Insert a Case record to ensure the controller has something to query
        insert new Case(Subject = 'Test Subject');

        // Build the controller to get existing list view labels
        String qry = 'SELECT CaseNumber FROM Case LIMIT 1';
        ApexPages.StandardSetController ssc = 
            new ApexPages.StandardSetController(Database.getQueryLocator(qry));
        List<SelectOption> allViews = ssc.getListViewOptions();

        // Pick the first available view label
        String existingLabel = allViews.isEmpty() ? null : allViews[0].getLabel();

        if (existingLabel != null) {
            CaseListViewController controller = new CaseListViewController();
            controller.listName = existingLabel;

            System.assertNotEquals(null, controller.listId, 'listId should be set');
            System.assertEquals(15, controller.listId.length(), 'listId should be 15 characters');
        } else {
            System.debug('⚠️ No list views available in the test context.');
        }
    }
	
}