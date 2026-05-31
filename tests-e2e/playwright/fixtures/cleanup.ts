import { test as base } from './anchored-data';
import { cleanupRun } from '../helpers/salesforce-cli';

/**
 * Per-test cleanup. After each test that used `e2eRun`, ask
 * FimbyTestDataCleanup.cleanupRun(runId) to remove anything anchored to that run.
 *
 * Cleanup failures are logged but do not fail the test, because the prefix-level
 * sweep at the end of the run will catch residue.
 */
export const test = base;

test.afterEach(async ({ e2eRun }, testInfo) => {
  if (!e2eRun?.runId) return;
  try {
    const res = await cleanupRun(e2eRun.runId);
    if (!res.success) {
      console.warn(`[cleanup] runId=${e2eRun.runId} failed: ${res.stderr.split('\n')[0]}`);
      testInfo.annotations.push({ type: 'cleanup-warn', description: res.stderr.slice(0, 500) });
    }
  } catch (err) {
    console.warn(`[cleanup] runId=${e2eRun.runId} threw: ${(err as Error).message}`);
    testInfo.annotations.push({ type: 'cleanup-warn', description: (err as Error).message });
  }
});

export { expect } from '@playwright/test';
