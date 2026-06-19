/**
 * @description REST endpoint for searching Salesforce accounts by name.
 *              Used by the Copilot Studio Teams bot to resolve imprecise account
 *              name input before triggering a portfolio analysis run.
 *
 *              GET /services/apexrest/v1/portfolioAnalysis/search?accountName=Acme
 *
 *              Returns a JSON array of matching accounts:
 *              [{ "id": "001xxx", "name": "Acme Corp" }, ...]
 *
 * @author      Vignesh Prabhudoss
 * @date        2026-04-24
 * @jira        BIZ-82161
 */
@RestResource(urlMapping='/portfolioAnalysis/search')
global with sharing class PortfolioAnalysisSearchRESTService {

    /***********************************************************************************************
     *
     * Inner Classes / Wrappers
     *
     ***********************************************************************************************/

    /**
     * @description Lightweight account wrapper returned to the Teams bot.
     *              Avoids exposing full Account SObject fields over REST.
     */
    global class AccountResult {
        global String id;
        global String name;

        global AccountResult(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    /**
     * @description Standard REST response envelope.
     */
    global class SearchResponse {
        global Boolean success;
        global String errorMessage;
        global List<AccountResult> accounts;

        global SearchResponse() {
            this.success = false;
            this.accounts = new List<AccountResult>();
        }
    }

    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Searches for Client accounts matching the given name fragment.
     *              Delegates to PortfolioAnalysisController.searchAccounts.
     *
     * @return JSON-serialised SearchResponse via RestContext.response.
     */
    @HttpGet
    global static void searchAccounts() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        SearchResponse response = new SearchResponse();

        try {
            String accountName = req.params.get('accountName');

            if (String.isBlank(accountName)) {
                res.statusCode = 400;
                response.errorMessage = 'accountName parameter is required.';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            if (accountName.length() < 2) {
                res.statusCode = 400;
                response.errorMessage = 'accountName must be at least 2 characters.';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            List<Account> accounts = PortfolioAnalysisController.searchAccounts(accountName);

            for (Account acc : accounts) {
                response.accounts.add(new AccountResult(acc.Id, acc.Name));
            }

            response.success = true;
            res.statusCode = 200;

            Nebula.Logger.info('PortfolioAnalysisSearchRESTService: returned ' + response.accounts.size() + ' accounts for "' + accountName + '"')
                .addTag('PortfolioAnalysis')
                .addTag('TeamsBot');
            Nebula.Logger.saveLog();

        } catch (Exception e) {
            res.statusCode = 500;
            response.errorMessage = 'Account search failed: ' + e.getMessage();

            Nebula.Logger.error('PortfolioAnalysisSearchRESTService: search failed', e)
                .addTag('PortfolioAnalysis')
                .addTag('TeamsBot');
            Nebula.Logger.saveLog();
        }

        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }
}