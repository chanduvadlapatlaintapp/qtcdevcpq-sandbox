Public class GroupLinkCtlr{

    @auraEnabled
    public static CollaborationGroup getGroups(string topicId){

         list<topic> topicList = [select id, name from topic where id=:topicId];
         string topicName = '';
         if (topicList.size()>0)
         	topicName = topicList[0].Name;
             
         list<CollaborationGroup> grplst = [select id,FullPhotoUrl,SmallPhotoUrl ,BannerPhotoUrl , name from CollaborationGroup where name=:topicName];
         if(grplst.size()>0)
            return grplst[0];  
         else
            return null; 
    }
    
}