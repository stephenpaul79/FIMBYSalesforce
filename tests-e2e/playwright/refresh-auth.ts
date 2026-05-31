import { loadPersonas, loginPersona } from './global-setup';

async function main(): Promise<void> {
  const personas = loadPersonas();
  for (const persona of personas) {
    await loginPersona(persona, { forceRefresh: true });
  }
  console.log('[auth] all personas refreshed');
}

main().catch((err) => {
  console.error('[auth] refresh failed:', err);
  process.exit(1);
});
