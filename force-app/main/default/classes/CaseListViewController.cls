public with sharing class CaseListViewController {
    
  public String listName {
    get;
    set {
        listName = value;
        String qry = 'SELECT CaseNumber FROM Case LIMIT 1';
        ApexPages.StandardSetController ssc = 
            new ApexPages.StandardSetController(Database.getQueryLocator(qry));
        List<SelectOption> allViews = ssc.getListViewOptions();
        for (SelectOption so : allViews) {
          if (so.getLabel() == listName) {
            // for some reason, won't work with 18 digit ID
            listId = so.getValue().substring(0,15);
            break;
          }
        }             
    }      
  }
  public String listId {get;set;}
    
}