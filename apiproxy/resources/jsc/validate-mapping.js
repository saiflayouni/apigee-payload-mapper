var result = {};
try {
  result = JSON.parse(context.getVariable("mapping.static.result") || "{}");
} catch (e) {
  result = {};
}

var missing = [];

if (typeof result.accountNumber !== "string" || result.accountNumber.length === 0) {
  missing.push("accountNumber");
}
if (!result.balance || typeof result.balance.amount !== "number" || isNaN(result.balance.amount)) {
  missing.push("balance.amount");
}
if (!result.balance || typeof result.balance.currency !== "string" || result.balance.currency.length !== 3) {
  missing.push("balance.currency");
}
if (typeof result.transactionDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(result.transactionDate)) {
  missing.push("transactionDate");
}

if (missing.length === 0) {
  context.setVariable("mapping.valid", "true");
  context.setVariable("mapping.method", "static");
  context.setVariable("final.payload", JSON.stringify(result));
} else {
  context.setVariable("mapping.valid", "false");
  context.setVariable("mapping.missing_fields", missing.join(", "));
}
