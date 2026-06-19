/**
* @description       : Test class for GreenBoxController
* @author            : Keerthan N
* Jira story : BIZ-47960
**/
@isTest
public class GreenBoxControllerTest {

    @istest
    private static void getCustomMetadataTest(){
        List<Approval_Level_Matrix__mdt> mtdt = GreenBoxController.getCustomMetadata();
         Assert.isTrue(mtdt.size() > 0, 'Metadata Found');
        
    }
}