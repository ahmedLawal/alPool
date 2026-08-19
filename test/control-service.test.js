import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ControlError, ControlService } from '../src/control-service.js';

function fixture() {
  const accounts = [
    { name: 'claude', type: 'oauth', enabled: true, accountUuid: 'u1', inFlight: 0 },
    { name: 'glm', type: 'provider', provider: 'zai', enabled: true, inFlight: 0 },
  ];
  const am = {
    accounts,
    routingMode: 'automatic',
    preferredAccountName: null,
    scheduler: { routingMode: 'balance' },
    getStatus: () => ({ accounts: accounts.map(a => ({ ...a })), routing: { mode: am.routingMode } }),
    setProviderRoutingMode(mode) { this.scheduler.routingMode = mode; return true; },
    setRoutingMode(mode, name) { this.routingMode = mode; this.preferredAccountName = name || null; return true; },
    setAccountEnabled(index, enabled) { this.accounts[index].enabled = enabled; return true; },
    removeAccount(index) { this.accounts.splice(index, 1); return true; },
  };
  const config = {
    accounts: [{ name: 'claude', type: 'oauth', accountUuid: 'u1', enabled: true }],
    providers: [{ name: 'glm', provider: 'zai', enabled: true }],
    routing: { mode: 'automatic', preferredAccount: null },
    scheduler: { routingMode: 'balance', crossProviderFallbackPolicy: 'always' },
    updateCheck: true,
    autoUpdate: false,
    autoApply: false,
  };
  let saves = 0;
  const service = new ControlService({
    accountManager: am,
    config,
    persistConfig: async () => { saves++; },
    syncAccounts: async () => 2,
    getUpstreamSyncStatus: () => ({
      state: 'failed', phase: 'merge', checkedAt: '2026-08-19T09:00:00Z',
      lastSuccessAt: '2026-08-19T03:00:00Z', installedVersion: '1.6.1',
      installedRevision: '80d5ed4', availableVersion: '1.7.1',
      availableRevision: 'aac169c', error: 'The update could not be merged.',
    }),
  });
  return { service, am, config, saves: () => saves };
}

test('snapshot exposes safe control metadata', () => {
  const { service } = fixture();
  const snapshot = service.snapshot();
  assert.equal(snapshot.control.automaticUpdates, false);
  assert.equal(snapshot.control.capabilities.addAccounts, false);
  assert.equal(typeof snapshot.control.backendPid, 'number');
  assert.equal(snapshot.upstreamSync.state, 'failed');
  assert.equal(snapshot.upstreamSync.installedVersion, '1.6.1');
  assert.equal(snapshot.upstreamSync.availableVersion, '1.7.1');
});

test('routing and account commands update runtime and persistent config', async () => {
  const { service, am, config, saves } = fixture();
  await service.execute({ type: 'set-routing-mode', payload: { mode: 'prefer-zai' } });
  assert.equal(am.scheduler.routingMode, 'prefer-zai');
  assert.equal(config.scheduler.routingMode, 'prefer-zai');
  assert.equal('crossProviderFallbackPolicy' in config.scheduler, false);

  await service.execute({ type: 'set-preferred-account', payload: { name: 'claude' } });
  assert.equal(am.preferredAccountName, 'claude');
  await service.execute({ type: 'set-account-enabled', payload: { name: 'claude', enabled: false } });
  assert.equal(am.accounts[0].enabled, false);
  assert.equal(config.routing.mode, 'automatic');
  assert.equal(saves(), 3);
});

test('rename and delete refuse transient or busy accounts', async () => {
  const { service, am } = fixture();
  await assert.rejects(
    service.execute({ type: 'rename-account', payload: { name: 'missing', newName: 'new' } }),
    error => error instanceof ControlError && error.status === 404,
  );
  am.accounts[0].inFlight = 1;
  await assert.rejects(
    service.execute({ type: 'delete-account', payload: { name: 'claude' } }),
    error => error.code === 'account_busy',
  );
});

test('automatic update command controls the complete update chain', async () => {
  const { service, config } = fixture();
  await service.execute({ type: 'set-automatic-updates', payload: { enabled: true } });
  assert.equal(config.updateCheck, true);
  assert.equal(config.autoUpdate, true);
  assert.equal(config.autoApply, true);
});
