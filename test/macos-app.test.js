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

test('macOS overview supports compact account cards and traffic-light quota safety', () => {
  const content = readFileSync(new URL('../macos/Sources/alPoolApp/ContentView.swift', import.meta.url), 'utf8');
  assert.match(content, /@AppStorage\("overviewAccountDensity"\)/);
  assert.match(content, /Picker\("Account detail"/);
  assert.match(content, /\.pickerStyle\(\.segmented\)\s*\.labelsHidden\(\)/);
  assert.match(content, /Text\("Compact"\)/);
  assert.match(content, /Text\("Detailed"\)/);
  assert.match(content, /if density == \.detailed/);
  assert.equal(content.includes('Label("Serving \\(account.inFlight)"'), true);
  assert.match(content, /hidesRoutineStatus && status == "Active"/);
  assert.match(content, /if usage >= 0\.85 \{ return \.red \}/);
  assert.match(content, /if usage >= 0\.60 \{ return \.orange \}/);
  assert.match(content, /return \.green/);
});

test('macOS updates page shows installed upstream version and sync failures', () => {
  const content = readFileSync(new URL('../macos/Sources/alPoolApp/ContentView.swift', import.meta.url), 'utf8');
  assert.match(content, /Section\("MaxPool upstream"\)/);
  assert.match(content, /LabeledContent\("Installed"/);
  assert.match(content, /case "failed": "Update failed"/);
  assert.match(content, /snapshot\.upstreamSync\?\.error/);
});

test('macOS app restores the live TUI activity feed', () => {
  const content = readFileSync(new URL('../macos/Sources/alPoolApp/ContentView.swift', import.meta.url), 'utf8');
  assert.match(content, /case activity = "Activity"/);
  assert.match(content, /private struct ActivityView/);
  assert.match(content, /ForEach\(active\)/);
  assert.match(content, /ForEach\(recent\)/);
  assert.match(content, /Request bodies and credentials are never shown/);
});

test('macOS app exposes tank capacity and per-account usage caps', () => {
  const content = readFileSync(new URL('../macos/Sources/alPoolApp/ContentView.swift', import.meta.url), 'utf8');
  const models = readFileSync(new URL('../macos/Sources/alPoolCore/Models.swift', import.meta.url), 'utf8');
  assert.match(content, /case capacity = "Capacity"/);
  assert.match(content, /private struct CapacityView/);
  assert.match(content, /Latest measured/);
  assert.match(content, /Measured average/);
  assert.match(content, /private struct UsageCapEditor/);
  assert.match(content, /type: "set-account-cap"/);
  assert.match(models, /public let capacity: AccountCapacityInfo\?/);
  assert.match(models, /public var capUtilization: Double\?/);
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
  assert.match(source, /CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE/);
  assert.match(source, /application_default_credentials\.json/);
  assert.match(source, /\[\[ -r "\$GCLOUD_CREDENTIAL_FILE" \]\]/);
  assert.match(source, /SuccessfulExit/);
});

test('generated app output and Swift build products stay out of git', () => {
  const ignore = readFileSync(new URL('../.gitignore', import.meta.url), 'utf8');
  assert.match(ignore, /^dist\/$/m);
  assert.match(ignore, /^macos\/\.build\/$/m);
});

test('packaged app declares the principal macOS application class', () => {
  const info = readFileSync(new URL('../macos/Resources/Info.plist', import.meta.url), 'utf8');
  assert.match(info, /<key>NSPrincipalClass<\/key>\s*<string>NSApplication<\/string>/);
});
