// Maestro JavaScript file — place next to your .yaml flow
// Called via:  - runScript: fingerprint-bridge-trigger.js
// Requires:   fingerprint-bridge.js server running on port 4567

var response = http.post('http://localhost:4567/fingerprint', {});
output.result = response.body;
