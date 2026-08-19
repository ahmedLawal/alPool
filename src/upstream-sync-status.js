import { readFileSync } from 'node:fs';
import { mkdir, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

const STATES = new Set(['checking', 'update-available', 'up-to-date', 'failed']);
const MAX_TEXT_LENGTH = 500;

export function getUpstreamSyncStatusPath(env = process.env) {
  if (env.ALPOOL_UPSTREAM_SYNC_STATUS) return env.ALPOOL_UPSTREAM_SYNC_STATUS;
  const stateRoot = env.XDG_STATE_HOME || join(homedir(), '.local', 'state');
  return join(stateRoot, 'alpool', 'upstream-sync.json');
}

function optionalText(value, maxLength = MAX_TEXT_LENGTH) {
  if (value == null || value === '') return null;
  return String(value).slice(0, maxLength);
}

export function normalizeUpstreamSyncStatus(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const state = STATES.has(value.state) ? value.state : null;
  if (!state) return null;
  return {
    state,
    phase: optionalText(value.phase, 40),
    checkedAt: optionalText(value.checkedAt, 80),
    lastSuccessAt: optionalText(value.lastSuccessAt, 80),
    installedVersion: optionalText(value.installedVersion, 80),
    installedRevision: optionalText(value.installedRevision, 80),
    availableVersion: optionalText(value.availableVersion, 80),
    availableRevision: optionalText(value.availableRevision, 80),
    error: state === 'failed' ? optionalText(value.error) : null,
  };
}

export function readUpstreamSyncStatus({ path = getUpstreamSyncStatusPath() } = {}) {
  try {
    return normalizeUpstreamSyncStatus(JSON.parse(readFileSync(path, 'utf8')));
  } catch {
    return null;
  }
}

export async function writeUpstreamSyncStatus(status, { path = getUpstreamSyncStatusPath() } = {}) {
  const normalized = normalizeUpstreamSyncStatus(status);
  if (!normalized) throw new Error('Invalid upstream sync status.');
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(normalized, null, 2)}\n`, { mode: 0o600 });
  await rename(temporaryPath, path);
  return normalized;
}
