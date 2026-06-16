var sourcePayload = context.getVariable("mapping.source.payload") || "{}";
var missingFields = context.getVariable("mapping.missing_fields") || "unknown";

var targetSchema = JSON.stringify({
  accountNumber: "string",
  balance: { amount: "number", currency: "string (ISO 4217, 3 letters)" },
  transactionDate: "string (YYYY-MM-DD)"
}, null, 2);

var prompt = "You are a payload integration engineer for a banking system.\n" +
  "The static field mapping below failed because the source system changed its payload shape.\n\n" +
  "Source payload (unknown/changed format):\n" + sourcePayload + "\n\n" +
  "Target schema it must be converted into:\n" + targetSchema + "\n\n" +
  "Fields the static mapping could not populate: " + missingFields + "\n\n" +
  "Infer the correct field mapping from field names, value types and value shapes " +
  "(e.g. dates, currency codes, amounts), then produce the fully transformed payload " +
  "matching the target schema exactly.\n\n" +
  "Respond with JSON only, in this exact shape:\n" +
  "{\"transformed\": {\"accountNumber\": <string>, \"balance\": {\"amount\": <number>, \"currency\": <string>}, \"transactionDate\": \"YYYY-MM-DD\"}, " +
  "\"confidence\": <0.0-1.0>, \"notes\": \"<one sentence explaining the field mapping you inferred>\"}";

var requestBody = JSON.stringify({
  contents: [{ parts: [{ text: prompt }] }],
  generationConfig: {
    responseMimeType: "application/json",
    temperature: 0.1,
    maxOutputTokens: 512,
    thinkingConfig: { thinkingBudget: 0 }
  }
});

context.setVariable("gemini.request.body", requestBody);
var apiKey = context.getVariable("propertyset.config.gemini_api_key") || "disabled";
context.setVariable("gemini.api.key", apiKey);
