var method = context.getVariable("mapping.method") || "unknown";
var finalPayload = {};
try {
  finalPayload = JSON.parse(context.getVariable("final.payload") || "{}");
} catch (e) {
  finalPayload = {};
}

var audit = {
  mapping_method: method,
  source_payload: JSON.parse(context.getVariable("mapping.source.payload") || "{}")
};

if (method === "gemini_self_healed") {
  audit.confidence = parseFloat(context.getVariable("mapping.confidence") || "0");
  audit.notes = context.getVariable("mapping.notes") || "";
  audit.static_mapping_missing_fields = (context.getVariable("mapping.missing_fields") || "").split(", ").filter(function(s) { return s.length > 0; });
} else if (method === "static_unvalidated_fallback") {
  audit.alert = context.getVariable("mapping.alert") || "";
  audit.static_mapping_missing_fields = (context.getVariable("mapping.missing_fields") || "").split(", ").filter(function(s) { return s.length > 0; });
}

var responseBody = {
  mapping_method: method,
  transformed_payload: finalPayload,
  audit: audit
};

context.setVariable("mapper.final_response", JSON.stringify(responseBody));
