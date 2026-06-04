import { log } from "./log";

const marks: Record<string, number> = {};

/** Dev-oriented timing marks for auth / deep-link handoff (see existing log() gating). */
export function authTimingMark(label: string, detail?: Record<string, unknown>) {
  const ts = Date.now();
  marks[label] = ts;
  log(`[AUTH_TIMING] ${label}`, { ts, ...detail });
}

export function authTimingDelta(fromLabel: string, toLabel: string) {
  const from = marks[fromLabel];
  const to = marks[toLabel];
  if (from == null || to == null) return;
  log(`[AUTH_TIMING] ${fromLabel}->${toLabel}`, { ms: to - from });
}

export function deeplinkTimingMark(label: string, detail?: Record<string, unknown>) {
  authTimingMark(`deeplink:${label}`, detail);
}
