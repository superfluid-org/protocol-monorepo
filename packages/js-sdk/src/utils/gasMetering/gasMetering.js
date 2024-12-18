const {GasMeterJSONReporter, GasMeterHTMLReporter} = require("./gasReporter");

class Formatter {
    constructor(web3) {
        this.web3 = web3;
        this.BN = this.web3.utils.BN;
    }

    formatBigNumber(key, value) {
        switch (key) {
            case "cost":
            case "totalCost":
            case "avgCost":
                value = `${this.web3.utils.fromWei(value)} ETH`;
                break;
            case "totalTx":
            case "gas":
            case "totalGas":
            case "minGas":
            case "maxGas":
            case "avgGas":
                value = value.toString(10);
                break;
            case "gasPrice":
                value = `${this.web3.utils.fromWei(value, "gwei")} GWEI`;
                break;
        }
        return value;
    }

    formatObject(x) {
        const result = {};
        Object.keys(x).forEach((key) => {
            var value = x[key];
            if (this.BN.isBN(value)) {
                value = this.formatBigNumber(key, value);
            }
            result[key] = value;
        });
        return result;
    }
}

module.exports = class GasMeter {
    constructor(web3, outputFormat, gasPrice) {
        this.web3 = web3;
        this.BN = this.web3.utils.BN;
        switch (outputFormat) {
            case "JSON":
                this.reporter = new GasMeterJSONReporter({});
                break;
            case "HTML":
                this.reporter = new GasMeterHTMLReporter({});
                break;
            case "TENDERLY":
                // TODO
                break;
            default:
                throw new Error(`Unsupported report type ${outputFormat}`);
        }
        this.gasPrice = new this.BN(gasPrice);
        this.records = [];
        this.aggregates = {};
        this.formatter = new Formatter(this.web3);
    }

    _format() {
        const formattedAggregates = {};
        Object.keys(this.aggregates).forEach((actionName) => {
            const bucket = this.aggregates[actionName];
            formattedAggregates[actionName] = {};
            Object.keys(bucket).forEach((key) => {
                formattedAggregates[actionName][key] =
                    this.formatter.formatBigNumber(
                        key,
                        bucket[key],
                        this.fiatCurr
                    );
            });
        });
        const formattedRecords = this.records.map((x) => {
            return this.formatter.formatObject(x, this.fiatCurr);
        });
        return {
            aggregates: {...formattedAggregates},
            executedTxs: [...formattedRecords],
        };
    }

    pushTx(tx, actionName) {
        const gas = new this.BN(tx.receipt.gasUsed);
        const cost = gas.mul(this.gasPrice);
        this.records.push({
            action: actionName,
            txHash: tx.tx,
            gas: gas,
            gasPrice: this.gasPrice,
            cost: cost,
        });
        if (!(actionName in this.aggregates)) {
            this.aggregates[actionName] = {
                action: actionName,
                avgGas: new this.BN("0"),
                avgCost: new this.BN("0"),
                minGas: new this.BN("10000000000000000000000"),
                maxGas: new this.BN("0"),
                totalTx: new this.BN("0"),
                totalGas: new this.BN("0"),
                totalCost: new this.BN("0"),
            };
        }
        const bucket = this.aggregates[actionName];
        bucket.totalTx = bucket.totalTx.add(new this.BN("1"));
        bucket.totalGas = bucket.totalGas.add(gas);
        bucket.totalCost = bucket.totalCost.add(cost);
        bucket.avgCost = bucket.totalCost.div(bucket.totalTx);
        bucket.avgGas = bucket.totalGas.div(bucket.totalTx);
        bucket.minGas = this.BN.min(bucket.minGas, gas);
        bucket.maxGas = this.BN.max(bucket.maxGas, gas);
    }

    generateReport(name) {
        this.reporter.fileName = name;
        const formattedReport = this._format();
        this.reporter.generateReport(formattedReport);
    }
};
