import { test as base } from './personas';
import { randomUUID } from 'node:crypto';

export interface E2ERun {
  /** Unique short id for this single test, used in title prefix and external id. */
  runId: string;
  /** Title prefix to apply to every record this test creates (do not change shape). */
  prefix: string;
  /** Build a unique anchored title: `[E2E] <runId> <label>`. */
  title: (label: string) => string;
  /** Build a unique anchored external id: `e2e-<runId>-<slug>`. */
  externalId: (slug: string) => string;
}

export interface AnchoredDataFixtures {
  e2eRun: E2ERun;
}

function shortId(): string {
  return randomUUID().replace(/-/g, '').slice(0, 8);
}

export const test = base.extend<AnchoredDataFixtures>({
  e2eRun: async ({}, use, testInfo) => {
    const runId = shortId();
    const prefix = `[E2E] ${runId}`;
    const run: E2ERun = {
      runId,
      prefix,
      title: (label) => `${prefix} ${label}`.slice(0, 80),
      externalId: (slug) => `e2e-${runId}-${slug}`.toLowerCase().replace(/[^a-z0-9-]/g, '-'),
    };
    testInfo.annotations.push({ type: 'e2e-run-id', description: runId });
    await use(run);
  },
});

export { expect } from '@playwright/test';
