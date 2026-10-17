#!/usr/bin/env node
/**
 * Antigravity Stop Lifecycle Hook
 * Verifies that specs pass validate-specs.sh before completing the agent run.
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

let inputData = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', chunk => { inputData += chunk; });
process.stdin.on('end', () => {
  try {
    const rootDir = path.resolve(__dirname, '..', '..');
    const specIndex = path.join(rootDir, 'specs', 'SPEC-INDEX.md');

    // Only validate if specs have been initialized
    if (!fs.existsSync(specIndex)) {
      process.stdout.write(JSON.stringify({ decision: 'allow' }));
      return;
    }

    // Locate git bash or bash on Windows/Unix
    let bashExe = 'bash';
    const gitBashPaths = [
      'C:\\Program Files\\Git\\bin\\bash.exe',
      'C:\\Program Files\\Git\\usr\\bin\\bash.exe'
    ];
    for (const p of gitBashPaths) {
      if (fs.existsSync(p)) {
        bashExe = p;
        break;
      }
    }

    try {
      execFileSync(bashExe, ['.ai/scripts/validate-specs.sh'], {
        cwd: rootDir,
        stdio: 'pipe',
        encoding: 'utf8'
      });
      process.stdout.write(JSON.stringify({ decision: 'allow' }));
    } catch (err) {
      const output = (err.stdout || '') + '\n' + (err.stderr || '');
      process.stdout.write(JSON.stringify({
        decision: 'continue',
        reason: `[policy.md Spec rules] .ai/scripts/validate-specs.sh failed:\n${output.trim()}`
      }));
    }
  } catch (err) {
    process.stdout.write(JSON.stringify({ decision: 'allow' }));
  }
});
