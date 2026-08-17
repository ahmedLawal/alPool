import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = new URL('..', import.meta.url);

function run(command, args, cwd, env = process.env) {
  const result = spawnSync(command, args, { cwd, env, encoding: 'utf8' });
  assert.equal(result.status, 0, `${command} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result;
}

test('upstream synchronization is local, transactional, and validates before push', () => {
  assert.equal(existsSync(new URL('../.github/workflows/sync-upstream.yml', import.meta.url)), false);
  const script = readFileSync(new URL('../scripts/sync-upstream.sh', import.meta.url), 'utf8');
  assert.match(script, /worktree add --detach/);
  assert.match(script, /npm test/);
  assert.match(script, /npm run lint/);
  assert.ok(script.indexOf('npm run lint') < script.indexOf('push origin'), 'validation must happen before push');
  assert.match(script, /push origin "HEAD:\$BRANCH"/);
});

test('local sync scripts have valid Bash syntax', () => {
  for (const path of ['scripts/sync-upstream.sh', 'scripts/install-local-sync.sh']) {
    const result = spawnSync('/bin/bash', ['-n', path], { cwd: root, encoding: 'utf8' });
    assert.equal(result.status, 0, `${path}: ${result.stderr}`);
  }
});

test('LaunchAgent runs at login and every six hours', () => {
  const result = spawnSync('/bin/bash', ['scripts/install-local-sync.sh', '--print'], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /<key>RunAtLoad<\/key>\s*<true\/>/);
  assert.match(result.stdout, /<key>StartInterval<\/key>\s*<integer>21600<\/integer>/);
  assert.match(result.stdout, /scripts\/sync-upstream\.sh/);
});

test('local sync validates a divergent merge before pushing personal main', async () => {
  const temp = await mkdtemp(join(tmpdir(), 'alpool-local-sync-test-'));
  try {
    const origin = join(temp, 'origin.git');
    const upstream = join(temp, 'upstream.git');
    const seed = join(temp, 'seed');
    const upstreamWork = join(temp, 'upstream-work');
    const checkout = join(temp, 'checkout');
    const fakeBin = join(temp, 'bin');
    const fakeLog = join(temp, 'npm.log');
    const syncTmp = join(temp, 'tmp');

    run('git', ['init', '--bare', origin], temp);
    run('git', ['init', '--bare', upstream], temp);
    run('git', ['init', '-b', 'main', seed], temp);
    run('git', ['config', 'user.name', 'Test'], seed);
    run('git', ['config', 'user.email', 'test@example.com'], seed);
    await writeFile(join(seed, 'base.txt'), 'base\n');
    run('git', ['add', 'base.txt'], seed);
    run('git', ['commit', '-m', 'base'], seed);
    run('git', ['remote', 'add', 'origin', origin], seed);
    run('git', ['remote', 'add', 'upstream', upstream], seed);
    run('git', ['push', 'origin', 'main'], seed);
    run('git', ['push', 'upstream', 'main'], seed);

    await writeFile(join(seed, 'personal.txt'), 'personal\n');
    run('git', ['add', 'personal.txt'], seed);
    run('git', ['commit', '-m', 'personal'], seed);
    run('git', ['push', 'origin', 'main'], seed);

    run('git', ['clone', '--branch', 'main', upstream, upstreamWork], temp);
    run('git', ['config', 'user.name', 'Test'], upstreamWork);
    run('git', ['config', 'user.email', 'test@example.com'], upstreamWork);
    await writeFile(join(upstreamWork, 'upstream.txt'), 'upstream\n');
    run('git', ['add', 'upstream.txt'], upstreamWork);
    run('git', ['commit', '-m', 'upstream'], upstreamWork);
    run('git', ['push', 'origin', 'main'], upstreamWork);

    run('git', ['clone', '--branch', 'main', origin, checkout], temp);
    run('git', ['remote', 'add', 'upstream', upstream], checkout);
    await mkdir(fakeBin);
    await mkdir(syncTmp);
    const fakeNpm = join(fakeBin, 'npm');
    await writeFile(fakeNpm, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$ALPOOL_FAKE_NPM_LOG"\n');
    await chmod(fakeNpm, 0o755);

    const env = {
      ...process.env,
      PATH: `${fakeBin}:${process.env.PATH}`,
      TMPDIR: syncTmp,
      ALPOOL_REPO_ROOT: checkout,
      ALPOOL_FAKE_NPM_LOG: fakeLog,
    };
    const script = new URL('../scripts/sync-upstream.sh', import.meta.url).pathname;
    const dryRun = run('/bin/bash', [script], checkout, { ...env, ALPOOL_SYNC_DRY_RUN: '1' });
    assert.match(dryRun.stdout, /Dry run complete/);
    const beforePush = spawnSync('git', ['show', 'origin/main:upstream.txt'], { cwd: checkout });
    assert.notEqual(beforePush.status, 0, 'dry run must not push');
    assert.deepEqual((await readFile(fakeLog, 'utf8')).trim().split('\n'), [
      'install --ignore-scripts --no-audit --no-fund',
      'test',
      'run lint',
    ]);

    const realRun = run('/bin/bash', [script], checkout, env);
    assert.match(realRun.stdout, /Upstream sync complete/);
    run('git', ['fetch', 'origin', 'main'], checkout);
    assert.equal(run('git', ['show', 'origin/main:personal.txt'], checkout).stdout, 'personal\n');
    assert.equal(run('git', ['show', 'origin/main:upstream.txt'], checkout).stdout, 'upstream\n');
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
