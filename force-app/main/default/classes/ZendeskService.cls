/**
 * @description Service class for Zendesk REST API integration. Handles HTTP callouts
 *              to retrieve ticket/support data for the Customer 360 application.
 *              Uses a Named Credential (Zendesk_API) for authentication.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
public with sharing class ZendeskService {

    /**********************************************************************************************
     *
     * Constants
     *
     ***********************************************************************************************/

    private static final String NAMED_CREDENTIAL = 'callout:Zendesk_API';
    private static final String SEARCH_ENDPOINT = '/search.json';
    private static final String USERS_ENDPOINT = '/users/show_many.json';

    /**********************************************************************************************
     *
     * Wrapper Classes
     *
     ***********************************************************************************************/

    /** Wrapper for a single Zendesk ticket returned to the LWC */
    public class ZendeskTicket {
        @AuraEnabled public String id;
        @AuraEnabled public String ticketNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String assignee;
        @AuraEnabled public String createdAt;
        @AuraEnabled public String updatedAt;
        @AuraEnabled public String resolvedAt;
        @AuraEnabled public String ticketUrl;
        @AuraEnabled public String type;
    }

    /** Deserialization class for the Zendesk search API response */
    public class ZendeskSearchResponse {
        public List<ZendeskTicketResponse> results;
        public Integer count;
    }

    /** Deserialization class for an individual ticket from the Zendesk API */
    public class ZendeskTicketResponse {
        public Long id;
        public String subject;
        public String status;
        public String priority;
        public String type;
        public String created_at;
        public String updated_at;
        public Long requester_id;
        public Long assignee_id;
    }

    /** Deserialization class for the Zendesk users batch API response */
    public class ZendeskUsersResponse {
        public List<ZendeskUser> users;
    }

    /** Deserialization class for an individual user from the Zendesk API */
    public class ZendeskUser {
        public Long id;
        public String name;
    }

    /**********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Searches Zendesk for tickets associated with a given organization name.
     *              Uses the Zendesk Search API to find tickets by organization.
     * @param organizationName The Account/organization name to search for in Zendesk.
     * @return List<ZendeskTicket> List of normalized ticket wrappers.
     */
    public static List<ZendeskTicket> getTicketsByOrganization(String organizationName) {
        if (String.isBlank(organizationName)) {
            return new List<ZendeskTicket>();
        }

        String query = 'type:ticket organization:"' +
            String.escapeSingleQuotes(organizationName) + '"';
        String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + SEARCH_ENDPOINT + '?query=' + encodedQuery + '&sort_by=updated_at&sort_order=desc');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(15000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            Nebula.Logger.error('Zendesk API error: ' + res.getStatusCode() + ' - ' + res.getBody())
                .addTag('ZendeskService')
                .addTag('API_Error');
            Nebula.Logger.saveLog();

            AuraHandledException e = new AuraHandledException('Failed to retrieve Zendesk tickets. Status: ' + res.getStatusCode());
            e.setMessage('Failed to retrieve Zendesk tickets. Status: ' + res.getStatusCode());
            throw e;
        }

        ZendeskSearchResponse searchResponse = (ZendeskSearchResponse) JSON.deserialize(
            res.getBody(), ZendeskSearchResponse.class
        );

        return mapToTicketWrappers(searchResponse.results);
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Maps raw Zendesk API response objects to normalized ZendeskTicket wrappers.
     *              Performs a batch user lookup for assignee names.
     * @param results List of raw ticket response objects from the API.
     * @return List<ZendeskTicket> Normalized ticket wrappers for LWC consumption.
     */
    private static List<ZendeskTicket> mapToTicketWrappers(List<ZendeskTicketResponse> results) {
        List<ZendeskTicket> tickets = new List<ZendeskTicket>();
        if (results == null || results.isEmpty()) {
            return tickets;
        }

        // Collect unique assignee IDs for batch lookup
        Set<Long> assigneeIds = new Set<Long>();
        for (ZendeskTicketResponse raw : results) {
            if (raw.assignee_id != null) {
                assigneeIds.add(raw.assignee_id);
            }
        }

        Map<Long, String> userNames = resolveUserNames(assigneeIds);

        for (ZendeskTicketResponse raw : results) {
            ZendeskTicket ticket = new ZendeskTicket();
            ticket.id = String.valueOf(raw.id);
            ticket.ticketNumber = 'ZD-' + raw.id;
            ticket.subject = raw.subject;
            ticket.status = mapStatus(raw.status);
            ticket.priority = mapPriority(raw.priority);
            ticket.assignee = raw.assignee_id != null ? userNames.get(raw.assignee_id) : null;
            ticket.createdAt = raw.created_at;
            ticket.updatedAt = raw.updated_at;
            ticket.resolvedAt = (raw.status == 'solved' || raw.status == 'closed') ? raw.updated_at : null;
            ticket.ticketUrl = 'https://intapp1750201095.zendesk.com/agent/tickets/' + raw.id;
            ticket.type = raw.type;
            tickets.add(ticket);
        }
        return tickets;
    }

    /**
     * @description Batch-resolves Zendesk user IDs to display names using the show_many endpoint.
     * @param userIds Set of Zendesk user IDs to resolve.
     * @return Map<Long, String> Map of user ID to display name.
     */
    private static Map<Long, String> resolveUserNames(Set<Long> userIds) {
        Map<Long, String> nameMap = new Map<Long, String>();
        if (userIds == null || userIds.isEmpty()) {
            return nameMap;
        }

        List<String> idStrings = new List<String>();
        for (Long uid : userIds) {
            idStrings.add(String.valueOf(uid));
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + USERS_ENDPOINT + '?ids=' + String.join(idStrings, ','));
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                ZendeskUsersResponse usersResponse = (ZendeskUsersResponse) JSON.deserialize(
                    res.getBody(), ZendeskUsersResponse.class
                );
                if (usersResponse.users != null) {
                    for (ZendeskUser u : usersResponse.users) {
                        nameMap.put(u.id, u.name);
                    }
                }
            } else {
                Nebula.Logger.warn('Zendesk Users API returned status ' + res.getStatusCode())
                    .addTag('ZendeskService')
                    .addTag('Users_Lookup');
                Nebula.Logger.saveLog();
            }
        } catch (Exception e) {
            Nebula.Logger.warn('Failed to resolve Zendesk user names: ' + e.getMessage())
                .addTag('ZendeskService')
                .addTag('Users_Lookup');
            Nebula.Logger.saveLog();
        }

        return nameMap;
    }

    /**
     * @description Maps Zendesk priority value to Title Case display label.
     * @param zendeskPriority Raw priority string from Zendesk (urgent, high, normal, low).
     * @return String Normalized priority label for LWC display.
     */
    private static String mapPriority(String zendeskPriority) {
        if (String.isBlank(zendeskPriority)) {
            return 'Medium';
        }
        switch on zendeskPriority.toLowerCase() {
            when 'urgent' { return 'Critical'; }
            when 'high' { return 'High'; }
            when 'normal' { return 'Medium'; }
            when 'low' { return 'Low'; }
            when else { return 'Medium'; }
        }
    }

    /**
     * @description Maps Zendesk status value to Title Case display label.
     * @param zendeskStatus Raw status string from Zendesk (new, open, pending, hold, solved, closed).
     * @return String Normalized status label for LWC display.
     */
    private static String mapStatus(String zendeskStatus) {
        if (String.isBlank(zendeskStatus)) {
            return 'Open';
        }
        switch on zendeskStatus.toLowerCase() {
            when 'new', 'open' { return 'Open'; }
            when 'pending', 'hold' { return 'Pending'; }
            when 'solved' { return 'Solved'; }
            when 'closed' { return 'Closed'; }
            when else { return 'Open'; }
        }
    }
}