import dotenv from 'dotenv';
import path from 'node:path';
import { cleanupPrefix, cleanupRun, dryRunPrefix } from './salesforce-cli';

dotenv.config({ path: path.resolve(__dirname, '..', '..', '.env') });

async function main(): Promise<void> {
  const [, , subcommand, arg] = process.argv;
  switch (subcommand) {
    case 'dryrun': {
      const prefix = arg ?? '[E2E] ';
      const res = await dryRunPrefix(prefix);
      process.stdout.write(res.stdout);
      if (!res.success) {
        process.stderr.write(res.stderr);
        process.exit(1);
      }
      return;
    }
    case 'cleanupRun': {
      if (!arg) throw new Error('Usage: cleanup-cli.ts cleanupRun <runId>');
      const res = await cleanupRun(arg);
      process.stdout.write(res.stdout);
      if (!res.success) {
        process.stderr.write(res.stderr);
        process.exit(1);
      }
      return;
    }
    case 'cleanupPrefix': {
      const prefix = arg ?? '[E2E] ';
      const res = await cleanupPrefix(prefix);
      process.stdout.write(res.stdout);
      if (!res.success) {
        process.stderr.write(res.stderr);
        process.exit(1);
      }
      return;
    }
    default:
      console.error('Usage: tsx playwright/helpers/cleanup-cli.ts <dryrun|cleanupRun|cleanupPrefix> [arg]');
      process.exit(2);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
