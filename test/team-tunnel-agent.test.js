import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, chmod, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('team tunnel agent is a valid persistent user service and never embeds WireGuard keys', { skip: process.platform !== 'darwin' }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'alpool-tunnel-test-'));
  try {
    const bin = join(dir, 'wireproxy'); const config = join(dir, 'tunnel.conf');
    await writeFile(bin, '#!/bin/sh\nexit 0\n'); await chmod(bin, 0o755);
    await writeFile(config, '[Interface]\nPrivateKey = test-private-value\n');
    const r = spawnSync('bash', ['scripts/install-team-tunnel-agent.sh', '--print'], { encoding: 'utf8', env: { ...process.env, WIREPROXY_BIN: bin, ALPOOL_TUNNEL_CONFIG: config } });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /com\.ahmedlawal\.alpool\.tunnel/);
    assert.match(r.stdout, /RunAtLoad/); assert.match(r.stdout, /KeepAlive/);
    assert.ok(r.stdout.includes(config));
    assert.ok(!r.stdout.includes('test-private-value'));
    const lint = spawnSync('plutil', ['-lint', '-'], { input: r.stdout, encoding: 'utf8' });
    assert.equal(lint.status, 0, lint.stdout + lint.stderr);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
