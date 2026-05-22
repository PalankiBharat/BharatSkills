// Fingerprint Bridge Server
// Run this BEFORE executing any Maestro biometric flow:
//   node fingerprint-bridge.js
//
// Requires: emulator running with fingerprint pre-enrolled (Settings > Security > Fingerprint, ID = 1)
// Triggers:  adb -e emu finger touch 1 via HTTP POST /fingerprint
// Works on:  local emulator only — not real devices, not Maestro Cloud

const http = require('http');
const { exec } = require('child_process');

const PORT = 4567;

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'POST' && req.url === '/fingerprint') {
    exec('adb -e emu finger touch 1', (err, stdout, stderr) => {
      const ok = !err;
      res.writeHead(ok ? 200 : 500);
      res.end(JSON.stringify({ ok, stdout: stdout.trim(), stderr: stderr.trim() }));
      console.log(ok ? '✓ Fingerprint triggered' : `✗ ADB error: ${stderr}`);
    });
  } else {
    res.writeHead(404);
    res.end(JSON.stringify({ error: 'Unknown endpoint' }));
  }
});

server.listen(PORT, () => {
  console.log(`Fingerprint bridge ready on http://localhost:${PORT}/fingerprint`);
  console.log('Waiting for Maestro to call /fingerprint ...');
});
