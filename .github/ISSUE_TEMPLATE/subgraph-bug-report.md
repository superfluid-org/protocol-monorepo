---
name: Subgraph Bug report
about: Create a bug report to help us improve the subgraph
title: "[SUBGRAPH BUG]"
labels: 'Type: Bug'
assignees: 0xdavinchee

---

**Describe the bug:**
A clear and concise description of what the bug is. What is the data you are having issues with?

**Subgraph endpoint:** [e.g. https://thegraph.com/hosted-service/subgraph/superfluid-finance/protocol-v1-polygon-mainnet]

**Query:**
e.g.
```
query MyQuery {
  streams(first: 10) {
    currentFlowRate
    createdAtTimestamp
    streamedUntilUpdatedAt
  }
}
```

**Expected data:**
Paste a link (e.g. etherscan) to the event that illustrates that the subgraph data is incorrect or paste the expected data (within reason).

**Actual data:**
A clear and concise description of what is incorrect with the data or paste the returned data (within reason).

**Screenshots:**
If applicable, attach screenshots.

**Additional context:**
Add any other context or relevant information about the problem here. This includes pasting any relevant error messages, data (within reason) and snippets.
