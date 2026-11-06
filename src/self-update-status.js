import { readFileSync } from 'node:fs';
import { mkdir, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

// Mirror of upstream-sync-status.js for the OTHER update track: the backend's own
// 30-minute self-updater (git fast-forward from origin). Until 2026-11-06 its
// failures lived only in the event log, so the native Updates tab could not show
// "did the last check fail, why, and when did an update last land".
const STATES = new Set(['checking', 'update-available', 'up-to-date', 'failed']);
const MAX_TEXT_LENGTH = 300;

export function getSelfUpdateStatusPath(env = process.env) {
  if (env.ALPOOL_SELF_UPDATE_STATUS) return env.ALPOOL_SELF_UPDATE_STATUS;
  const stateRoot = env.XDG_STATE_HOME || join(homedir(), '.local', 'state');
  return join(stateRoot, 'alpool', 'self-update.json');
}

function optionalText(value, maxLength = MAX_TEXT_LENGTH) {
  if (value == null || value === '') return null;
  return String(value).slice(0, maxLength);
}

export function normalizeSelfUpdateStatus(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const state = STATES.has(value.state) ? value.state : null;
  if (!state) return null;
  return {
    state,
    phase: optionalText(value.phase, 40),
    checkedAt: optionalText(value.checkedAt, 80),
    updatedAt: optionalText(value.updatedAt, 80),
    runningVersion: optionalText(value.runningVersion, 80),
    latestRevision: optionalText(value.latestRevision, 80),
    toRevision: optionalText(value.toRevision, 80),
    error: state === 'failed' ? optionalText(value.error) : null,
    // Sticky across later successes, so a past failure stays answerable in the UI.
    lastFailedAt: optionalText(value.lastFailedAt, 80),
    lastError: optionalText(value.lastError),
  };
}

export function readSelfUpdateStatus({ path = getSelfUpdateStatusPath() } = {}) {
  try {
    return normalizeSelfUpdateStatus(JSON.parse(readFileSync(path, 'utf8')));
  } catch {
    return null;
  }
}

export async function writeSelfUpdateStatus(status, { path = getSelfUpdateStatusPath() } = {}) {
  const normalized = normalizeSelfUpdateStatus(status);
  if (!normalized) throw new Error('Invalid self-update status.');
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(normalized, null, 2)}\n`, { mode: 0o600 });
  await rename(temporaryPath, path);
  return normalized;
}

/** A check is starting — show "checking" while keeping everything sticky. Best-effort. */
export async function recordSelfUpdateStart({ path = getSelfUpdateStatusPath(), now = () => new Date().toISOString() } = {}) {
  try {
    const previous = readSelfUpdateStatus({ path }) || {};
    return await writeSelfUpdateStatus({ ...previous, state: 'checking', phase: 'check', checkedAt: now() }, { path });
  } catch {
    return null;
  }
}

/**
 * Record the outcome of one maybeCheckForUpdate run for the Updates tab.
 * `info` is that run's onVersionInfo payload (running version + revisions);
 * `thrownError` is set when the check itself crashed. A null `result` without a
 * thrownError (checks disabled / gated off) leaves the previous state untouched.
 */
export async function recordSelfUpdateOutcome(result, info, thrownError, { path = getSelfUpdateStatusPath(), now = () => new Date().toISOString() } = {}) {
  try {
    const previous = readSelfUpdateStatus({ path }) || {};
    const ts = now();
    const base = {
      ...previous,
      checkedAt: ts,
      runningVersion: optionalText(info?.current ?? previous.runningVersion, 80) || null,
      latestRevision: optionalText(info?.latest ?? previous.latestRevision, 80) || null,
    };
    const fail = async message => writeSelfUpdateStatus({
      ...base, state: 'failed', phase: 'check', error: message,
      lastFailedAt: ts, lastError: message,
    }, { path });
    if (thrownError) {
      return await fail(`Update check crashed: ${String(thrownError.message || thrownError).slice(0, 200)}`);
    }
    if (!result) return previous;
    if (result.checkFailed) {
      return await fail('Could not reach the update source — the check failed before comparing revisions.');
    }
    if (result.error) {
      return await writeSelfUpdateStatus({
        ...base, state: 'failed', phase: optionalText(result.phase, 40) || 'install',
        error: result.error, lastFailedAt: ts, lastError: result.error,
      }, { path });
    }
    if (result.hasUpdate) {
      return await writeSelfUpdateStatus({
        ...base, state: 'update-available', phase: null, error: null,
        ...(result.updated ? { updatedAt: ts, toRevision: optionalText(result.installedVersion, 80) } : {}),
      }, { path });
    }
    return await writeSelfUpdateStatus({ ...base, state: 'up-to-date', phase: null, error: null }, { path });
  } catch {
    return null; // status recording is best-effort; never break the update flow
  }
}
