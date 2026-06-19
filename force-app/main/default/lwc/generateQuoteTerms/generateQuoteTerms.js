import { LightningElement,api,wire } from 'lwc';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from 'lightning/actions';
import generateQuoteTerms from '@salesforce/apex/QuoteTermValidator.generateQuoteTerms';

export default class GenerateQuoteTerms extends LightningElement {
    @api recordId;

    connectedCallback(){
        this.getQuoteTerms();
    }

    renderedCallback(){
        this.getQuoteTerms();
    }
    getQuoteTerms(){
        if(this.recordId){
        generateQuoteTerms({quoteId: this.recordId})
        .then(data => {
            if(data){
                const evt = new ShowToastEvent({
                    message: data,
                    variant: 'success'
                  });
                  this.dispatchEvent(evt);
                  this.dispatchEvent(new CloseActionScreenEvent());
            }
        })
        .catch(error => {
            console.log(error);
            this.dispatchEvent(new CloseActionScreenEvent());
        })
    }
    }
}