/**
 * Runs @smoke with plain, readable output to last-smoke.log (no ANSI, no
 * PowerShell "NativeCommandError" wrapping stderr). For interactive runs use
 * npm run test:smoke or test:smoke:ui.
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const logPath = path.join(root, 'last-smoke.log');

/** Strip most ANSI/OSC sequences Playwright and Node print on Windows. */
function stripAnsi(buf) {
  return buf
    .toString('utf8')
    .replace(/\u001B\[[\d;?]*[A-Za-z]/g, '')
    .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n');
}

const start = new Date();
const header = `=== fimby smoke @smoke — ${start.toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC')} ===\n\n`;
fs.writeFileSync(logPath, header, 'utf8');

const args = ['playwright', 'test', '--grep', '@smoke', '--reporter', 'list'];
const baseOpts = (process.env.NODE_OPTIONS || '').trim();
const child = spawn('npx', args, {
  cwd: root,
  env: {
    ...process.env,
    CI: '1',
    NO_COLOR: '1',
    FORCE_COLOR: '0',
    NODE_OPTIONS: baseOpts ? `${baseOpts} --no-warnings` : '--no-warnings',
  },
  shell: true,
});

const append = (data) => fs.appendFileSync(logPath, stripAnsi(data), 'utf8');
child.stdout.on('data', append);
child.stderr.on('data', append);

child.on('close', (code) => {
  const line = `\n=== finished exit_code=${code ?? 'unknown'} ===\n`;
  fs.appendFileSync(logPath, line, 'utf8');
  process.exit(code === null ? 1 : code);
});

child.on('error', (err) => {
  fs.appendFileSync(logPath, `\n[spawn error] ${err.message}\n`, 'utf8');
  process.exit(1);
});
