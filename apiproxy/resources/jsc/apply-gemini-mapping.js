try {
  var statusCode = parseInt(context.getVariable("geminiRemapResponse.status.code") || "0", 10);
  if (statusCode === 200) {
    var responseBody = context.getVariable("geminiRemapResponse.content");
    var response = JSON.parse(responseBody);
    var text = response.candidates[0].content.parts[0].text;
    var result = JSON.parse(text);

    context.setVariable("mapping.method", "gemini_self_healed");
    context.setVariable("mapping.confidence", (parseFloat(result.confidence) || 0).toFixed(2));
    context.setVariable("mapping.notes", result.notes || "no explanation returned");
    context.setVariable("final.payload", JSON.stringify(result.transformed));
  } else {
    context.setVariable("mapping.method", "static_unvalidated_fallback");
    context.setVariable("mapping.alert", "Gemini remap unavailable (HTTP " + statusCode + ") — static mapping is incomplete, manual review required");
    context.setVariable("final.payload", context.getVariable("mapping.static.result"));
  }
} catch (e) {
  context.setVariable("mapping.method", "static_unvalidated_fallback");
  context.setVariable("mapping.alert", "Gemini remap failed to parse (" + e.toString() + ") — static mapping is incomplete, manual review required");
  context.setVariable("final.payload", context.getVariable("mapping.static.result"));
}
