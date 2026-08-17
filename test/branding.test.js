import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

test('personal fork exposes only the alpool executable', () => {
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(pkg.name, 'alpool');
  assert.deepEqual(pkg.bin, { alpool: 'src/index.js' });
});

test('CLI help is branded alPool and uses the alpool command', () => {
  const result = spawnSync(process.execPath, ['src/index.js', 'help'], {
    cwd: new URL('..', import.meta.url),
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^alPool - Multi-account Claude proxy/m);
  assert.match(result.stdout, /^Usage: alpool \[command\] \[options\]/m);
  assert.doesNotMatch(result.stdout, /^Usage: maxpool/m);
});
