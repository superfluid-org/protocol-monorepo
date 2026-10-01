const {getErrorResponse} = require("./utils/error");

module.exports = class User {
    /**
     * @dev Create new Superfluid user object
     * @param {Framework} sf Superfluid framework object.
     * @param {string} address The EOA address of the user you want to create.
     * @param {string} token The address of the supertoken you want to interact with.
     */
    constructor({sf, address, token}) {
        this.sf = sf;
        this.address = address;
        this.token = token;
    }

    /**
     * @dev Returns instantiated details regarding the users' cfa and ida data.
     * @returns {object} top-level cfa property contains flows: Flow[] and netFlow: number
     * top-level ida property contains subscriptions: Subscription[]
     */
    async details() {
        try {
            const listFlows = this.sf.cfa.listFlows({
                superToken: this.token,
                account: this.address,
            });
            const getNewFlow = this.sf.cfa
                .getNetFlow({
                    superToken: this.token,
                    account: this.address,
                })
                .then((x) => x.toString());
            const listSubscriptions = this.sf.ida.listSubscriptions({
                superToken: this.token,
                subscriber: this.address,
            });
            const [flows, netFlow, subscriptions] = await Promise.all([
                listFlows,
                getNewFlow,
                listSubscriptions,
            ]);
            return {cfa: {flows, netFlow}, ida: {subscriptions}};
        } catch (e) {
            throw getErrorResponse(e, "user", "details");
        }
    }

    /**
     * @dev Allows you to create, update or delete a flow from the user you initialized.
     * @param {string} recipient the recipient of the flow agreement
     * @param {string} flowRate the agreed upon flowRate
     * @param {object} options options taken by cfa (userData, onTransaction, by (deleteFlow only))
     * @returns {Promise<Transaction | undefined>} web3 transaction object or undefined on error
     * NOTE: !0 in JS evaluates to true as 0 is a falsey value. We also stringify the flowRate,
     * just in case the user somehow is able to input a number (using JS).
     */
    async flow({recipient, flowRate, ...options}) {
        try {
            if (!recipient || flowRate == null || flowRate == undefined)
                throw "You must provide a recipient and flowRate";
            if (typeof flowRate !== "string")
                throw "You must provide flowRate as a string";
            const recipientAddress = recipient.address || recipient;
            if (flowRate === "0")
                return await this.sf.cfa.deleteFlow({
                    superToken: this.token,
                    sender: this.address,
                    receiver: recipientAddress,
                    ...options,
                });

            const existingFlow = await this.sf.cfa.getFlow({
                superToken: this.token,
                sender: this.address,
                receiver: recipientAddress,
            });
            if (existingFlow.flowRate !== "0")
                return await this.sf.cfa.updateFlow({
                    superToken: this.token,
                    sender: this.address,
                    receiver: recipientAddress,
                    flowRate,
                    ...options,
                });
            return await this.sf.cfa.createFlow({
                superToken: this.token,
                sender: this.address,
                receiver: recipientAddress,
                flowRate,
                ...options,
            });
        } catch (e) {
            throw getErrorResponse(e, "user", "flow");
        }
    }

};
