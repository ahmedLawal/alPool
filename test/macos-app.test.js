import { test } from 'node:test';
import assert from 'node:assert/strict';
import { accessSync, constants, existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const root = new URL('..', import.meta.url);

test('native macOS client is a SwiftUI IO layer over the control API', () => {
  const packageFile = new URL('../macos/Package.swift', import.meta.url);
  const app = readFileSync(new URL('../macos/Sources/alPoolApp/alPoolApp.swift', import.meta.url), 'utf8');
  const client = readFileSync(new URL('../macos/Sources/alPoolCore/BackendAPI.swift', import.meta.url), 'utf8');
  assert.equal(existsSync(packageFile), true);
  assert.match(app, /import SwiftUI/);
  assert.match(client, /maxpool\/control/);
  assert.doesNotMatch(client, /refreshToken|accessToken|secretName/);
});

test('macOS overview lists enabled accounts only', () => {
  const content = readFileSync(new URL('../macos/Sources/alPoolApp/ContentView.swift', import.meta.url), 'utf8');
  assert.match(content, /private var enabledAccounts:[\s\S]*snapshot\.accounts\.filter\(\\\.enabled\)/);
  assert.match(content, /ForEach\(enabledAccounts\)/);
});

test('backend LaunchAgent installer is guarded and valid', () => {
  const script = new URL('../scripts/install-backend-agent.sh', import.meta.url);
  accessSync(script, constants.X_OK);
  const syntax = spawnSync('/bin/bash', ['-n', script.pathname], { cwd: root, encoding: 'utf8' });
  assert.equal(syntax.status, 0, syntax.stderr);
  const source = readFileSync(script, 'utf8');
  assert.match(source, /No process was changed/);
  assert.match(source, /MODE" != "--replace"/);
  assert.match(source, /MAXPOOL_FORCE_SUPERVISOR/);
  assert.match(source, /SuccessfulExit/);
});

test('generated app output and Swift build products stay out of git', () => {
  const ignore = readFileSync(new URL('../.gitignore', import.meta.url), 'utf8');
  assert.match(ignore, /^dist\/$/m);
  assert.match(ignore, /^macos\/\.build\/$/m);
});
