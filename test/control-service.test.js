import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ControlError, ControlService } from '../src/control-service.js';

function fixture() {
  const accounts = [
    { name: 'claude', type: 'oauth', enabled: true, accountUuid: 'u1', capUtilization: null, inFlight: 0 },
    { name: 'glm', type: 'provider', provider: 'zai', enabled: true, capUtilization: null, inFlight: 0 },
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
    getActivity: () => ({
      activeCount: 1, sessionCount: 1,
      active: [{ id: '7', method: 'POST', path: '/v1/messages', account: 'glm' }],
      recent: [{ id: '1', message: 'POST /v1/messages → glm (200, 1.2s)' }],
    }),
  });
  return { service, am, config, saves: () => saves };
}

test('snapshot exposes safe control metadata', () => {
  const { service } = fixture();
  const snapshot = service.snapshot();
  assert.equal(snapshot.control.automaticUpdates, false);
  assert.equal(snapshot.control.capabilities.addAccounts, false);
  assert.equal(snapshot.control.capabilities.setAccountCap, true);
  assert.equal(typeof snapshot.control.backendPid, 'number');
  assert.equal(snapshot.upstreamSync.state, 'failed');
  assert.equal(snapshot.upstreamSync.installedVersion, '1.6.1');
  assert.equal(snapshot.upstreamSync.availableVersion, '1.7.1');
  assert.equal(snapshot.activity.activeCount, 1);
  assert.equal(snapshot.activity.recent.length, 1);
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

test('account cap command persists configured accounts and updates runtime state', async () => {
  const { service, am, config } = fixture();
  await service.execute({ type: 'set-account-cap', payload: { name: 'claude', capUtilization: 0.5 } });
  assert.equal(config.accounts[0].capUtilization, 0.5);
  assert.equal(am.accounts[0].capUtilization, 0.5);

  await service.execute({ type: 'set-account-cap', payload: { name: 'claude', capUtilization: null } });
  assert.equal('capUtilization' in config.accounts[0], false);
  assert.equal(am.accounts[0].capUtilization, null);

  await assert.rejects(
    service.execute({ type: 'set-account-cap', payload: { name: 'claude', capUtilization: 1 } }),
    error => error instanceof ControlError && error.code === 'invalid_command',
  );
});

test('native snapshot exposes effective cloud capacity and caller analytics without link credentials', () => {
  const { service, am } = fixture();
  am.accounts.push({ name: 'GLM cloud', index: 2, remote: { key: 'private-link-key' } });
  am.getStatus = () => ({ accounts: [{ name: 'GLM cloud', remote: true }], pools: [{ name: 'Team', ok: true }] });
  am.monthlyPriceFor = () => 15;
  am.capacityTank = () => ({ avg: 8_000_000, last: 7_000_000, n: 3 });
  am.poolLinks = [{ name: 'Team', key: 'private-link-key', status: { callerWindows: { Alex: { d7: { req: 12, tok: 2400 } } } } }];
  const s = service.snapshot();
  assert.equal(s.accounts[0].monthlyPriceUSD, 15);
  assert.equal(s.accounts[0].capacity.weekly.current, 8_000_000);
  assert.equal(s.pools[0].callerWindows.Alex.d7.req, 12);
  assert.ok(!JSON.stringify(s).includes('private-link-key'));
});

test('native live-route command validates mode and reports gate failures', async () => {
  const { service } = fixture();
  let mode;
  service.getClientRouting = () => ({ mode: 'pool', gateAvailable: true });
  service.setClientRoute = async value => { mode = value; };
  assert.equal(service.snapshot().control.capabilities.setClientRoute, true);
  await service.execute({ type: 'set-client-route', payload: { mode: 'pool' } });
  assert.equal(mode, 'pool');
  await assert.rejects(service.execute({ type: 'set-client-route', payload: { mode: 'other' } }), /Choose pool or direct/);
  service.setClientRoute = async () => { throw new Error('Gate unavailable'); };
  await assert.rejects(service.execute({ type: 'set-client-route', payload: { mode: 'direct' } }), error => error.status === 503);
});

test('native controls cannot mutate a cloud mirror or its guarded local copy', async () => {
  const { service, am } = fixture();
  am.accounts[0].remote = { linkName: 'Team' };
  await assert.rejects(service.execute({ type: 'set-account-enabled', payload: { name: 'claude', enabled: false } }), error => error.code === 'cloud_managed');
  delete am.accounts[0].remote;
  am.accounts[0].poolBenchedBy = 'cloud Claude';
  await assert.rejects(service.execute({ type: 'delete-account', payload: { name: 'claude' } }), error => error.code === 'cloud_managed');
  assert.equal(am.accounts[0].enabled, true);
});
