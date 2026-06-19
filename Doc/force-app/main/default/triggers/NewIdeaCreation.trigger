trigger NewIdeaCreation on Idea(after insert)
{

    IdeaTriggerHandler handler = new IdeaTriggerHandler();
    handler.afterInsert(trigger.new);

}