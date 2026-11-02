import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { ClientRoute } from '../src/client-route.js';

test('live route validates the mode, probes the gate, and leaves the switch intact when unavailable', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'alpool-route-'));
  let available = true;
  const route = new ClientRoute({ path: join(dir, 'route'), probe: async () => available });
  try {
    assert.equal(route.snapshot().mode, 'pool');
    await route.set('direct');
    assert.equal(route.snapshot().mode, 'direct');
    assert.equal(route.snapshot().gateAvailable, true);
    assert.equal(await readFile(route.path, 'utf8'), 'direct\n');
    await assert.rejects(route.set('unknown'), /Choose pool or direct/);
    available = false;
    await assert.rejects(route.set('pool'), /not running/);
    assert.equal(route.snapshot().mode, 'direct');
    assert.equal(route.snapshot().gateAvailable, false);
    available = true;
    await route.set('pool');
    assert.equal(route.snapshot().mode, 'pool');
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('gate probe failures stay unavailable and never create a switch file', async () => {
  const route = new ClientRoute({ probe: async () => { throw new Error('unreachable'); } });
  assert.equal(await route.check(), false);
});
