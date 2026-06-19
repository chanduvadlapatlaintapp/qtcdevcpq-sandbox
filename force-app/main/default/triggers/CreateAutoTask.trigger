trigger CreateAutoTask on CampaignMember (after insert,after update) {
    CampaignMemberTriggerHandler.run(trigger.new);
}