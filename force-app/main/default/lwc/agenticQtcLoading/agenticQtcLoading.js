import { LightningElement, api } from 'lwc';

export default class AgenticQtcLoading extends LightningElement {
    @api message = 'Loading';
    @api progressValue = null;
    @api progressMessage = '';

    get isProgressMode() {
        return this.progressValue !== null && this.progressValue !== undefined;
    }

    get progressBarStyle() {
        return 'width: ' + (this.progressValue || 0) + '%';
    }
}