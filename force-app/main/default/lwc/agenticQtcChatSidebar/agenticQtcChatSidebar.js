import { LightningElement, api, track } from 'lwc';
import sendMessage from '@salesforce/apex/AgenticQTC_AiChatController.sendMessage';
import continueConversation from '@salesforce/apex/AgenticQTC_AiChatController.continueConversation';

const MAX_CONTINUATION_ROUNDS = 10;

const TOOL_LABELS = {
    'search_accounts': 'Searched accounts',
    'search_contracts_by_number': 'Searched contracts',
    'get_contracts': 'Retrieved contracts',
    'get_contract_detail': 'Got contract details',
    'create_amendment': 'Created amendment',
    'get_quote_lines': 'Loaded quote lines',
    'update_quantity': 'Updated quantity',
    'update_discount': 'Applied discount',
    'add_product': 'Added product',
    'search_products': 'Searched products',
    'calculate_prices': 'Calculated prices',
    'check_approval': 'Checked approval',
    'generate_osa_document': 'Generated OSA document'
};

/**
 * Professional AI chat sidebar for the Agentic QTC flow.
 * Uses a client-side continuation loop to handle the Salesforce
 * callout-after-DML restriction across multi-round tool calls.
 */
export default class AgenticQtcChatSidebar extends LightningElement {
    @api accountId;
    @api accountName;
    @api contractId;
    @api quoteId;
    @api currentPage;

    @track messages = [];
    @track inputText = '';
    @track isThinking = false;
    @track thinkingStatus = '';
    _messageId = 0;
    // BUG FIX #8: Track scroll timeouts so they can be cleared on component destroy.
    _scrollTimeouts = [];

    get hasMessages() { return this.messages.length > 0; }
    get isSendDisabled() { return !this.inputText.trim() || this.isThinking; }

    handleInput(event) {
        this.inputText = event.target.value;
        this.autoResizeTextarea(event.target);
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    handleQuickAction(event) {
        this.inputText = event.currentTarget.dataset.action;
        this.handleSend();
    }

    /**
     * Sends the user message and handles multi-round continuation.
     * Each Apex call does one callout + one batch of tool execution.
     * If continuationNeeded, we loop client-side to avoid callout-after-DML.
     */
    async handleSend() {
        if (!this.inputText.trim() || this.isThinking) return;

        const userText = this.inputText.trim();
        this.inputText = '';
        this.resetTextareaHeight();

        this.addMessage('user', userText);
        this.isThinking = true;
        this.thinkingStatus = 'Thinking...';
        this.scrollToBottom();

        try {
            const contextJson = JSON.stringify({
                accountId: this.accountId || '',
                accountName: this.accountName || '',
                contractId: this.contractId || '',
                quoteId: this.quoteId || '',
                currentPage: this.currentPage || 'accountSearch'
            });

            let result = await sendMessage({ userMessage: userText, contextJson });
            // BUG FIX #4: Explicit null guard on result before accessing properties.
            // sendMessage can theoretically return undefined on certain platform edge cases.
            if (!result) {
                throw new Error('No response received from the AI service. Please try again.');
            }
            let allToolCalls = this.extractToolCalls(result);
            let round = 0;

            while (result.continuationNeeded && round < MAX_CONTINUATION_ROUNDS) {
                round++;
                this.thinkingStatus = this.buildThinkingStatus(allToolCalls);
                this.scrollToBottom();

                result = await continueConversation({
                    messagesJson: result.pendingMessagesJson,
                    contextJson,
                    priorToolCallsJson: result.pendingToolCallsJson
                });
                allToolCalls = this.extractToolCalls(result);
            }

            const toolChips = allToolCalls.map(tc => ({
                name: tc.name,
                label: TOOL_LABELS[tc.name] || tc.name,
                icon: tc.success ? 'utility:success' : 'utility:error',
                success: tc.success
            }));

            this.addMessage('ai', result.message, toolChips);
            this.processUiActions(result.uiActions || []);
        } catch (error) {
            const errMsg = error?.body?.message || error?.message || 'Something went wrong. Please try again.';
            console.error('Chat error:', error);
            this.addMessage('ai', 'Sorry, I encountered an error: ' + errMsg);
        } finally {
            this.isThinking = false;
            this.thinkingStatus = '';
            this.scrollToBottom();
        }
    }

    extractToolCalls(result) {
        return (result.toolCalls || []);
    }

    buildThinkingStatus(toolCalls) {
        if (!toolCalls.length) return 'Thinking...';
        const last = toolCalls[toolCalls.length - 1];
        const label = TOOL_LABELS[last.name] || last.name;
        return label + '... working';
    }

    addMessage(role, text, toolCalls) {
        this._messageId++;
        const isUser = role === 'user';
        const formattedText = isUser ? text : this.formatMarkdown(text);
        this.messages = [...this.messages, {
            id: 'msg-' + this._messageId,
            isUser,
            text,
            formattedText,
            containerClass: 'message-row ' + (isUser ? 'user-row' : 'ai-row'),
            bubbleClass: 'bubble ' + (isUser ? 'user-bubble' : 'ai-bubble'),
            hasToolCalls: toolCalls && toolCalls.length > 0,
            toolCalls: toolCalls || []
        }];
    }

    formatMarkdown(text) {
        if (!text) return '';
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.*?)\*/g, '<em>$1</em>')
            .replace(/`(.*?)`/g, '<code>$1</code>')
            .replace(/\n/g, '<br/>');
    }

    processUiActions(actions) {
        if (!actions || !actions.length) return;
        for (const action of actions) {
            if (!action) continue;
            switch (action.action) {
                case 'selectAccount':
                    this.dispatchEvent(new CustomEvent('navigateaccount', {
                        detail: { accountId: action.accountId, accountName: action.accountName }
                    }));
                    break;
                case 'selectContract':
                    this.dispatchEvent(new CustomEvent('navigatecontract', {
                        detail: { contractId: action.contractId, contractNumber: action.contractNumber }
                    }));
                    break;
                case 'refreshLines':
                    this.dispatchEvent(new CustomEvent('refreshlines'));
                    break;
                default:
                    break;
            }
        }
    }

    // BUG FIX #8: Clear pending scroll timeouts when component is destroyed to prevent
    // callbacks firing on a unmounted component and causing memory leaks or errors.
    disconnectedCallback() {
        this._scrollTimeouts.forEach(t => clearTimeout(t));
        this._scrollTimeouts = [];
    }

    handleClearChat() {
        this.messages = [];
    }

    autoResizeTextarea(el) {
        if (!el) return;
        el.style.height = 'auto';
        el.style.height = Math.min(el.scrollHeight, 120) + 'px';
    }

    resetTextareaHeight() {
        const el = this.refs.chatInput;
        if (el) {
            el.style.height = 'auto';
        }
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        const t = setTimeout(() => {
            const container = this.refs.chatMessages;
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 100);
        // BUG FIX #8: Track timeout ID so disconnectedCallback can cancel it.
        this._scrollTimeouts.push(t);
    }
}