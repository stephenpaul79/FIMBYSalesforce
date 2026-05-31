import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const execFileAsync = promisify(execFile);

const SCRIPTS_DIR = path.resolve(__dirname, '..', '..', 'scripts');

export interface ApexResult {
  stdout: string;
  stderr: string;
  success: boolean;
}

function getOrgAlias(): string {
  return process.env.SF_ORG_ALIAS ?? 'fimby-prod';
}

/** Render a `{KEY}` template into a temp .apex file and return the absolute path. */
function renderTemplate(templateName: string, replacements: Record<string, string>): string {
  const templatePath = path.join(SCRIPTS_DIR, templateName);
  if (!fs.existsSync(templatePath)) {
    throw new Error(`Apex template not found: ${templatePath}`);
  }
  let body = fs.readFileSync(templatePath, 'utf8');
  for (const [key, value] of Object.entries(replacements)) {
    const safe = value.replace(/'/g, "\\'");
    body = body.split(`{${key}}`).join(safe);
  }
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fimby-apex-'));
  const file = path.join(tmpDir, templateName.replace('.template', ''));
  fs.writeFileSync(file, body, 'utf8');
  return file;
}

async function runApexFile(apexFile: string): Promise<ApexResult> {
  const alias = getOrgAlias();
  try {
    const { stdout, stderr } = await execFileAsync(
      'sf',
      ['apex', 'run', '--target-org', alias, '--file', apexFile],
      { maxBuffer: 10 * 1024 * 1024, shell: true },
    );
    return { stdout, stderr, success: true };
  } catch (err) {
    const e = err as { stdout?: string; stderr?: string; message?: string };
    return {
      stdout: e.stdout ?? '',
      stderr: e.stderr ?? e.message ?? 'sf apex run failed',
      success: false,
    };
  } finally {
    try {
      fs.rmSync(path.dirname(apexFile), { recursive: true, force: true });
    } catch {
      /* best-effort */
    }
  }
}

export async function cleanupRun(runId: string): Promise<ApexResult> {
  if (!runId || runId.length < 4) {
    throw new Error(`cleanupRun rejected: runId too short (${JSON.stringify(runId)})`);
  }
  const file = renderTemplate('cleanup-run.apex.template', { RUN_ID: runId });
  return runApexFile(file);
}

export async function cleanupPrefix(prefix: string): Promise<ApexResult> {
  if (!prefix || prefix.trim().length < 5) {
    throw new Error(`cleanupPrefix rejected: prefix too short or blank (${JSON.stringify(prefix)})`);
  }
  const file = renderTemplate('cleanup-prefix.apex.template', { PREFIX: prefix });
  return runApexFile(file);
}

export async function dryRunPrefix(prefix: string): Promise<ApexResult> {
  if (!prefix || prefix.trim().length < 5) {
    throw new Error(`dryRunPrefix rejected: prefix too short or blank (${JSON.stringify(prefix)})`);
  }
  const file = renderTemplate('dryrun-prefix.apex.template', { PREFIX: prefix });
  return runApexFile(file);
}
