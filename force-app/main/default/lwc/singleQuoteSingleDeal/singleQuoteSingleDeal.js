/*
@description       : Single Quote Single Deal
@author            : Keerthan N
@last modified on  : 07-24-2023
@User Story : Created as part of BIZ-45097,BIZ-46504
*/
import { LightningElement,wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import checkAndCreateQuote from '@salesforce/apex/SingleQuoteSingleDealController.checkAndCreateQuote';
import updateAmendmentStartDate from '@salesforce/apex/SingleQuoteSingleDealController.updateAmendmentStartDate';
import { NavigationMixin } from 'lightning/navigation';

export default class SingleQuoteSingleDeal extends NavigationMixin(LightningElement) {

accId;
dealId;
dealType;
dealStage;
currencyIso='';
segmentNumber;
osaNumber;
amendmentStartDate;
expectedSignatureDate; 
dealOwnerId='';
message='YOUR DEAL IS BEING GENERATED. PLEASE STAND BY'; 
@wire(CurrentPageReference)
currentPageReference;

connectedCallback() {
    
    if ( this.currentPageReference.state.c__accId ) {
        this.accId = this.currentPageReference.state.c__accId;
    }
    if ( this.currentPageReference.state.c__DealType ) {
        this.dealType = this.currentPageReference.state.c__DealType;
    }
    /* Added as part of BIZ-72874 */
    if ( this.currentPageReference.state.c__DealStage ) {
        this.dealStage = this.currentPageReference.state.c__DealStage;
    }
    if ( this.currentPageReference.state.c__currencyIso ) {
        this.currencyIso = this.currentPageReference.state.c__currencyIso;
    }
    
    if ( this.currentPageReference.state.c__SalesSegment ) {
        this.segmentNumber = this.currentPageReference.state.c__SalesSegment;
    }

    if ( this.currentPageReference.state.c__ExpectedSignatureDate ) {
        this.expectedSignatureDate = ''+ (this.currentPageReference.state.c__ExpectedSignatureDate);
    }
    if ( this.currentPageReference.state.c__DealOwnerId ) {
        this.dealOwnerId = this.currentPageReference.state.c__DealOwnerId;
    }

    /* Added as part of BIZ-55810 */
    if ( this.currentPageReference.state.c__OSA ) {
        this.osaNumber = this.currentPageReference.state.c__OSA;
    }
    /* BIZ-67524 */
    if ( this.currentPageReference.state.c__AmendmentStartDate ) {
        this.amendmentStartDate = this.currentPageReference.state.c__AmendmentStartDate;
    }
    /* BIZ-55810 end */
    if ( this.currentPageReference.state.c__dealId ) {
        this.dealId = this.currentPageReference.state.c__dealId;
        this.checkAndCreateQuoteJs();
    }
}

async checkAndCreateQuoteJs() {
try {
    // Update Amendment Start Date before calling AmenderAPI
    if (this.osaNumber && this.amendmentStartDate) {
        await updateAmendmentStartDate({
            osaNumber: this.osaNumber,
            amendmentDate: this.amendmentStartDate
        });
    }

    const data = await checkAndCreateQuote({
        dealId: this.dealId,
        accId: this.accId,
        dealType: this.dealType,
        dealStage: this.dealStage,
        currencyIso: this.currencyIso,
        osaNumber: this.osaNumber,
        segmentNumber: this.segmentNumber,
        amendmentStartDateStr: this.amendmentStartDate,
        expectedSignatureDate: this.expectedSignatureDate,
        dealOwnerId: this.dealOwnerId
    });

    const result = data.split(';');
    if (result[0] === 'Success') {
        this.navigateToRecordPage(result[1], result[2]);
    } else {
        this.message = result[1];
    }
} catch (e) {
    this.message = e.body ? e.body.message : e.message;
}
}

    navigateToRecordPage(objName, recId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recId,
                objectApiName: objName,
                actionName: 'view'
            }
        });
    }
}