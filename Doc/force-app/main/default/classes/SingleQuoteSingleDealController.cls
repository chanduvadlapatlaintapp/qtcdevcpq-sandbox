/**
 * @description
 * Controller for Single Quote Single Deal flow triggered from OP4I.
 * Orchestrates request handling and delegates business logic
 * to SingleQuoteDealFactoryHelper.
 */
public without sharing class SingleQuoteSingleDealController {

    @TestVisible
    public static String mockResponse;
    
    /**
     * @description
     * RemoteAction entry point invoked from OP4I (VF / external integration).
     * Delegates processing to checkAndCreateQuote().
     */
    @RemoteAction
    public static String checkAndCreateQuoteAction(
        String dealId,
        String accId,
        String dealType,
        String dealStage,
        String currencyIso,
        String osaNumber,
        String segmentNumber,
        String amendmentStartDateStr,
        String expectedSignatureDate,
        String dealOwnerId
    ) {
        return checkAndCreateQuote(
            dealId,
            accId,
            dealType,
            dealStage,
            currencyIso,
            osaNumber,
            segmentNumber,
            amendmentStartDateStr,
            expectedSignatureDate,
            dealOwnerId
        );
    }

     /**
     * @description
     * Called from LWC to update the Contract start date, by parsing the op4i manage quote url
     */
    @AuraEnabled
    public static void updateAmendmentStartDate(String osaNumber, String amendmentDate) {
        if (String.isBlank(osaNumber)) {
            return;
        }
        
        Contract con = SingleQuoteDealFactorySupport.getActiveContract(osaNumber);
        if (con == null) {
            return;
        }
        
        if (String.isNotBlank(amendmentDate)) {
            Date amendDate = DateUtils.stringToDate(amendmentDate);
            con.SBQQ__AmendmentStartDate__c =
                amendDate != null ? Date.parse(amendDate.format()) : null;
            update con;
        }
    }
    
    /**
     * @description
     * Entry point called from LWC.
     * Determines whether to create a new quote,
     * update an existing quote, or recreate quote/opportunity
     * based on amendment or OSA change.
     */
    @AuraEnabled
    public static String checkAndCreateQuote(
        String dealId,
        String accId,
        String dealType,
        String dealStage,
        String currencyIso,
        String osaNumber,
        String segmentNumber,
        String amendmentStartDateStr,
        String expectedSignatureDate,
        String dealOwnerId
    ) {
        try {
            QuoteWrapper qw = new QuoteWrapper(
                dealId,
                accId,
                dealType,
                dealStage,
                currencyIso,
                osaNumber,
                segmentNumber,
                amendmentStartDateStr,
                expectedSignatureDate,
                dealOwnerId
            );

            Nebula.Logger.debug(
                'QuoteWrapper INIT | ' +
                'dealId=' + qw.dealId +
                ' | accId=' + qw.accId +
                ' | dealType=' + qw.dealType +
                ' | dealStage=' + qw.dealStage +
                ' | currencyIso=' + qw.currencyIso +
                ' | osaNumber=' + qw.osaNumber +
                ' | segmentNumber=' + qw.segmentNumber +
                ' | saleSegment=' + qw.saleSegment +
                ' | amendmentStartDate=' + qw.amendmentStartDate +
                ' | expectedSignatureDate=' + qw.expectedSignatureDate +
                ' | isAmendment=' + qw.isAmendment +
                ' | accountCurrency=' + qw.account.CurrencyIsoCode +
                ' | activeContractOSA=' + qw.activeContract.OSA_Number__c +
                ' | quotesCount=' + qw.quotes.size()
            );
			Nebula.Logger.saveLog();
            return SingleQuoteDealFactoryHelper.process(
                qw,
                mockResponse
            );

        } catch (Exception e) {
            return 'Error;' + e.getMessage();
        }
    }

    /***********************************************************************************************
    *
    * Wrapper Classes
    *
    ***********************************************************************************************/
    /**
     * @description wrapper class for quote and opp fields
     */
    public class QuoteWrapper {
        public String dealId;
        public String accId;
        public String dealType;
        public String dealStage;
        public String currencyIso;
        public String osaNumber;
        public String segmentNumber;
        public Date amendmentStartDate;
        public Account account;
        public Contract activeContract;
        public List<SBQQ__Quote__c> quotes;
        public String saleSegment;
        public Boolean isAmendment;
        public SBQQ__Quote__c oldQuote;
        public List<Opportunity> resultOppUpd;
        public List<SBQQ__Quote__c> resultQuoteUpd;
        public Date expectedSignatureDate;
        public String dealOwnerId;

        /**
         * @description Parameterized constructor for the wrapper
         */
        public QuoteWrapper(
            String dealId,
            String accId,
            String dealType,
            String dealStage,
            String currencyIso,
            String osaNumber,
            String segmentNumber,
            String amendmentStartDateStr,
            String expectedSignatureDate,
            String dealOwnerId
        ) {
            this.dealId = dealId;
            this.accId = accId;
            this.dealType = dealType;
            this.dealStage = dealStage;
            this.currencyIso = currencyIso;
            this.osaNumber = osaNumber;
            this.segmentNumber = segmentNumber;

            if (String.isNotBlank(amendmentStartDateStr)) {
                Date amendDate = DateUtils.stringToDate(amendmentStartDateStr);
                this.amendmentStartDate =
                    amendDate != null ? Date.parse(amendDate.format()) : null;
            }

            if (String.isNotBlank(expectedSignatureDate)) {
                Date expectedDate = DateUtils.stringToDate(expectedSignatureDate);
                this.expectedSignatureDate =
                    expectedDate != null ? Date.parse(expectedDate.format()) : null;
            }

            if (String.isNotBlank(dealOwnerId)) {
                this.dealOwnerId =
                    SingleQuoteDealFactorySupport.getDealOwner(dealOwnerId);
            }

            this.isAmendment =
                SingleQuoteDealFactorySupport.shouldCreateAmendment(
                    osaNumber,
                    dealType
                );

            this.account =
                SingleQuoteDealFactorySupport.getAccount(accId);

            this.activeContract =
                SingleQuoteDealFactorySupport.getActiveContract(osaNumber);

            this.quotes =
                SingleQuoteDealFactorySupport.getPrimaryQuotes(dealId);

            this.saleSegment =
                SingleQuoteDealFactorySupport.getSalesSegment(segmentNumber);

            this.currencyIso =
                String.isNotBlank(currencyIso)
                    ? currencyIso
                    : (this.account != null
                        ? this.account.CurrencyIsoCode
                        : 'USD');

            this.oldQuote = new SBQQ__Quote__c();
            this.resultOppUpd = new List<Opportunity>();
            this.resultQuoteUpd = new List<SBQQ__Quote__c>();
        }
    }
}