#!/usr/bin/env node
import {
  getUpstreamSyncStatusPath,
  readUpstreamSyncStatus,
  writeUpstreamSyncStatus,
} from '../src/upstream-sync-status.js';

const path = getUpstreamSyncStatusPath();
const previous = readUpstreamSyncStatus({ path });
const now = new Date().toISOString();
const state = process.env.ALPOOL_STATUS_STATE;
const phase = process.env.ALPOOL_STATUS_PHASE || null;

const failureLabels = {
  initialize: 'Could not initialize the upstream update check.',
  fetch: 'Could not fetch the MaxPool upstream update.',
  merge: 'The MaxPool upstream update could not be merged automatically.',
  install: 'The merged upstream update could not install its development dependencies.',
  test: 'The merged upstream update failed its test suite.',
  lint: 'The merged upstream update failed lint validation.',
  push: 'The validated upstream update could not be pushed to the alPool fork.',
};

function environmentValue(name, fallback = null) {
  return process.env[name] || fallback;
}

await writeUpstreamSyncStatus({
  state,
  phase,
  checkedAt: now,
  lastSuccessAt: state === 'up-to-date' ? now : previous?.lastSuccessAt,
  installedVersion: environmentValue('ALPOOL_STATUS_INSTALLED_VERSION', previous?.installedVersion),
  installedRevision: environmentValue('ALPOOL_STATUS_INSTALLED_REVISION', previous?.installedRevision),
  availableVersion: environmentValue('ALPOOL_STATUS_AVAILABLE_VERSION', previous?.availableVersion),
  availableRevision: environmentValue('ALPOOL_STATUS_AVAILABLE_REVISION', previous?.availableRevision),
  error: state === 'failed'
    ? (failureLabels[phase] || 'The MaxPool upstream update failed.')
    : null,
}, { path });
