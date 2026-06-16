// Fragile, hand-written mapping — breaks silently if the source system
// renames or restructures fields (the real-world failure mode this demo targets).

function formatDate(d) {
  if (!d || typeof d !== "string" || d.length !== 8) {
    return undefined;
  }
  return d.substring(0, 4) + "-" + d.substring(4, 6) + "-" + d.substring(6, 8);
}

var body = context.getVariable("request.content") || "{}";
var source = {};
try {
  source = JSON.parse(body);
} catch (e) {
  source = {};
}

var transformed = {
  accountNumber: source.acct_no,
  balance: {
    amount: source.bal,
    currency: source.ccy
  },
  transactionDate: formatDate(source.txn_dt)
};

context.setVariable("mapping.source.payload", body);
context.setVariable("mapping.static.result", JSON.stringify(transformed));
