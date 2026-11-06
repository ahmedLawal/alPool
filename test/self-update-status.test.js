import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  normalizeSelfUpdateStatus,
  readSelfUpdateStatus,
  writeSelfUpdateStatus,
  recordSelfUpdateStart,
  recordSelfUpdateOutcome,
} from '../src/self-update-status.js';

function tempPath(t) {
  const dir = mkdtempSync(join(tmpdir(), 'self-update-status-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return join(dir, 'self-update.json');
}
const NOW = () => '2026-11-06T10:00:00.000Z';
const INFO = { current: '1.24.66', latest: 'main@4802ac6', currentRevision: 'a', latestRevision: 'b' };

test('normalizeSelfUpdateStatus whitelists states and caps text', () => {
  assert.equal(normalizeSelfUpdateStatus(null), null);
  assert.equal(normalizeSelfUpdateStatus({ state: 'weird' }), null);
  const ok = normalizeSelfUpdateStatus({ state: 'failed', phase: 'install', error: 'x'.repeat(400) });
  assert.equal(ok.state, 'failed');
  assert.equal(ok.error.length, 300);
  assert.equal(normalizeSelfUpdateStatus({ state: 'up-to-date', error: 'boom' }).error, null);
});

test('write + read round-trip through a temp path', async t => {
  const path = tempPath(t);
  await writeSelfUpdateStatus({ state: 'update-available', checkedAt: NOW() }, { path });
  const read = readSelfUpdateStatus({ path });
  assert.equal(read.state, 'update-available');
  assert.equal(read.checkedAt, NOW());
});

test('recordSelfUpdateOutcome: check failure, install failure, recovery, update landing', async t => {
  const path = tempPath(t);

  const failedCheck = await recordSelfUpdateOutcome({ hasUpdate: false, checkFailed: true }, INFO, null, { path, now: NOW });
  assert.equal(failedCheck.state, 'failed');
  assert.equal(failedCheck.phase, 'check');
  assert.match(failedCheck.error, /Could not reach/);

  const failedInstall = await recordSelfUpdateOutcome(
    { hasUpdate: true, error: 'linked checkout has uncommitted changes', phase: 'install' }, INFO, null, { path, now: NOW });
  assert.equal(failedInstall.state, 'failed');
  assert.equal(failedInstall.error, 'linked checkout has uncommitted changes');

  const recovered = await recordSelfUpdateOutcome({ hasUpdate: false }, INFO, null, { path, now: NOW });
  assert.equal(recovered.state, 'up-to-date');
  assert.equal(recovered.error, null);
  assert.equal(recovered.lastError, 'linked checkout has uncommitted changes', 'past failure stays answerable');
  assert.equal(recovered.lastFailedAt, NOW());
  assert.equal(recovered.updatedAt, null, 'an up-to-date check must not fake an update landing');

  const landed = await recordSelfUpdateOutcome(
    { hasUpdate: true, updated: true, installedVersion: 'cccccccccccccccccccccccccccccccccccccccc' }, INFO, null, { path, now: NOW });
  assert.equal(landed.state, 'update-available');
  assert.equal(landed.updatedAt, NOW());
  assert.equal(landed.toRevision, 'cccccccccccccccccccccccccccccccccccccccc');
});

test('recordSelfUpdateOutcome: crash and disabled paths', async t => {
  const path = tempPath(t);
  const crashed = await recordSelfUpdateOutcome(null, INFO, new Error('boom'), { path, now: NOW });
  assert.equal(crashed.state, 'failed');
  assert.match(crashed.error, /Update check crashed: boom/);

  const untouched = await recordSelfUpdateOutcome(null, INFO, null, { path, now: NOW });
  assert.equal(untouched.state, 'failed', 'a gated/disabled check leaves the previous state');
  assert.equal(readSelfUpdateStatus({ path }).checkedAt, NOW());
});

test('recordSelfUpdateStart shows checking and preserves sticky fields', async t => {
  const path = tempPath(t);
  await writeSelfUpdateStatus({ state: 'up-to-date', updatedAt: '2026-11-01T00:00:00.000Z', toRevision: 'ccccccc' }, { path });
  const started = await recordSelfUpdateStart({ path, now: NOW });
  assert.equal(started.state, 'checking');
  assert.equal(started.checkedAt, NOW());
  assert.equal(started.updatedAt, '2026-11-01T00:00:00.000Z');
  assert.equal(started.toRevision, 'ccccccc');
});
