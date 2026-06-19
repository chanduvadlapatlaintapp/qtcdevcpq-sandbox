/********************************************************************************     
 *  Name             :  IdeaTriggerHandlerTest
 *  Author           :  Anisha
 *  Description      :  Test class for IdeaHandlerTrigger. 
 ********************************************************************************/
@isTest
class IdeaTriggerHandlerTest
{
	//Test method to verify single Idea posted by the User
	@isTest static void testNotifyNewIdea() {
		Idea idea1 = (Idea) SmartFactory.createSObject('Idea');
		Idea idea2 = (Idea) SmartFactory.createSObject('Idea');

		Account acc1 = new Account();
		acc1 = IntappTestObjectFactory.createAccount(false);

		acc1.Name = 'Integration';
		insert acc1;

		Contact con1 = (Contact) SmartFactory.createSObject('Contact');

		con1.AccountId = acc1.Id;
		insert con1;

		User usr1 = (User) SmartFactory.createSObject('User');
		insert usr1;

		idea1.CommunityId = [Select Id from Community LIMIT 1].Id;
		idea1.Categories = 'Integration';

		System.runAs(usr1)
		{
			insert idea1;
			System.debug('Success');
		}
	}

	//Test method to verify multiple Ideas posted by the User in different Categories
	@isTest static void testNotifyNewMultipleIdeas() {

		User usr2 = (User) SmartFactory.createSObject('User');
		insert usr2;

		List<Idea> list_ideaCategories = new List<Idea> ();

		Idea ideaIntappFlow = (Idea) SmartFactory.createSObject('Idea');
		ideaIntappFlow.CommunityId = [Select Id from Community LIMIT 1].Id;
		ideaIntappFlow.Categories = 'Intapp Flow';
		list_ideaCategories.add(ideaIntappFlow);

		Idea ideaIntappTime = (Idea) SmartFactory.createSObject('Idea');
		ideaIntappTime.CommunityId = [Select Id from Community LIMIT 1].Id;
		ideaIntappTime.Categories = 'Intapp Time';
		list_ideaCategories.add(ideaIntappTime);

		Idea ideaIntappTimeCloud = (Idea) SmartFactory.createSObject('Idea');
		ideaIntappTimeCloud.CommunityId = [Select Id from Community LIMIT 1].Id;
		ideaIntappTimeCloud.Categories = 'Intapp Time Cloud';
		list_ideaCategories.add(ideaIntappTimeCloud);

		Idea ideaIntegration = (Idea) SmartFactory.createSObject('Idea');
		ideaIntegration.CommunityId = [Select Id from Community LIMIT 1].Id;
		ideaIntegration.Categories = 'Integration';
		list_ideaCategories.add(ideaIntegration);

		System.runAs(usr2)
		{

			insert list_ideaCategories;
		}

	}
	
	//Test method to verify a different combination of multiple Ideas posted by the User in different Categories
	@isTest static void testNotifyNewMultipleIdeasTwo() {

		User usr3 = (User) SmartFactory.createSObject('User');
		insert usr3;
		
		List<Idea> list_ideaCategories = new List<Idea> ();

		Idea ideaIntappOpenIntake = (Idea) SmartFactory.createSObject('Idea');
		ideaIntappOpenIntake.CommunityId = [Select Id from Community LIMIT 1].Id;
		ideaIntappOpenIntake.Categories = 'Intapp Open Intake';
		list_ideaCategories.add(ideaIntappOpenIntake);

		Idea ideaIntappWalls = (Idea) SmartFactory.createSObject('Idea');
		ideaIntappWalls.CommunityId = [Select Id from Community LIMIT 1].Id;
		ideaIntappWalls.Categories = 'Intapp Walls';
		list_ideaCategories.add(ideaIntappWalls);

		System.runAs(usr3)
		{

			insert list_ideaCategories;
		}
	}

}