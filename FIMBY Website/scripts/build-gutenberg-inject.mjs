#!/usr/bin/env node
/**
 * Build a Gutenberg inject payload from a local .html file.
 * Writes to .respira/staging/inject-{pageId}.json (gitignored).
 *
 * Usage:
 *   node scripts/build-gutenberg-inject.mjs --html home.html --page-id 26 --markers trust-feature-block,trust-prose
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const siteRoot = path.resolve(dir, '..');

function parseArgs(argv) {
  const out = { html: null, pageId: null, markers: [], editTarget: 'live' };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--html') out.html = argv[++i];
    else if (argv[i] === '--page-id') out.pageId = Number(argv[++i]);
    else if (argv[i] === '--markers') out.markers = argv[++i].split(',').map((s) => s.trim()).filter(Boolean);
    else if (argv[i] === '--edit-target') out.editTarget = argv[++i];
    else throw new Error(`Unknown arg: ${argv[i]}`);
  }
  if (!out.html || !out.pageId) {
    throw new Error('Required: --html <file> --page-id <number>');
  }
  return out;
}

const args = parseArgs(process.argv);
const htmlPath = path.resolve(siteRoot, args.html);
const html = fs.readFileSync(htmlPath, 'utf8').trim();

// Inject-stub only — not CSS classes like avatar-placeholder
if (/(^|[\n>])\s*PLACEHOLDER\s*($|[\n<])/i.test(html)) {
  console.error('FAIL: source HTML contains inject stub PLACEHOLDER');
  process.exit(1);
}

for (const marker of args.markers) {
  if (!html.includes(marker)) {
    console.error(`FAIL: marker "${marker}" not found in ${args.html}`);
    process.exit(1);
  }
}

const payload = {
  builder: 'gutenberg',
  page_id: args.pageId,
  mode: 'replace',
  confirm_replace: true,
  edit_target: args.editTarget,
  content: [{ type: 'core/html', attrs: [], content: '\n' + html + '\n' }],
};

const stagingDir = path.join(siteRoot, '.respira', 'staging');
fs.mkdirSync(stagingDir, { recursive: true });
const outPath = path.join(stagingDir, `inject-${args.pageId}.json`);
fs.writeFileSync(outPath, JSON.stringify(payload));

console.log(JSON.stringify({
  ok: true,
  html: args.html,
  page_id: args.pageId,
  chars: payload.content[0].content.length,
  markers: args.markers,
  staging: outPath,
}, null, 2));
