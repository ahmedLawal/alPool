#!/usr/bin/env node
import http from 'node:http';

const port = Number(process.env.ALPOOL_MOCK_PORT) || 45678;
const apiKey = process.env.ALPOOL_MOCK_API_KEY || 'alpool-mock';
let routingMode = 'balance';
let automaticUpdates = true;

const accounts = [
  account('claude@example.com', 'oauth', null, 0.23, 0.61, 'active'),
  account('glm personal', 'provider', 'zai', 0.47, 0.72, 'active'),
  account('kimi fallback', 'provider', 'kimi', null, null, 'active'),
];

function account(name, type, provider, session, weekly, status) {
  return {
    name, type, provider, enabled: true, capUtilization: null,
    capacity: {
      session: { current: 1_250_000, latest: 1_180_000, average: 1_210_000, samples: 4, usage: session, source: 'live', lowerBound: false, fresh: true, derived: false },
      weekly: provider === 'kimi'
        ? { current: 40_656_000, latest: null, average: null, samples: 4, usage: null, source: 'derived', lowerBound: false, fresh: null, derived: true }
        : { current: 8_400_000, latest: 8_100_000, average: 8_250_000, samples: 3, usage: weekly, source: 'live', lowerBound: false, fresh: true, derived: false },
    },
    runtime: type === 'provider', status,
    refreshDead: false, inFlight: name.startsWith('glm') ? 1 : 0,
    completedRequests: 42, failedRequests: 1, lastStatus: 200, lastResponseMs: 890,
    lastError: null, cooldownUntil: null, rateLimitedUntil: null,
    quota: {
      unified5h: type === 'oauth' ? session : null,
      unified5hReset: Date.now() + 2 * 60 * 60 * 1000,
      unified7d: type === 'oauth' ? weekly : null,
      unified7dReset: Date.now() + 3 * 24 * 60 * 60 * 1000,
      providerSes: type === 'provider' ? session : null,
      providerSesReset: Date.now() + 90 * 60 * 1000,
      providerWk: type === 'provider' ? weekly : null,
      providerWkReset: Date.now() + 4 * 24 * 60 * 60 * 1000,
      weeklyAbsent: provider === 'kimi',
    },
    weekly: { state: 'normal', rawState: 'normal', effectiveUsage: weekly, paceState: 'normal' },
    usage: { totalInputTokens: 123456, totalOutputTokens: 23456, totalRequests: 42 },
  };
}

function snapshot() {
  return {
    version: { current: '1.5.86', latest: null, hasUpdate: false, source: 'git' },
    upstreamSync: {
      state: 'failed', phase: 'merge', checkedAt: new Date().toISOString(),
      lastSuccessAt: null, installedVersion: '1.6.1', installedRevision: '80d5ed4',
      availableVersion: '1.7.1', availableRevision: 'aac169c',
      error: 'The MaxPool upstream update could not be merged automatically.',
    },
    activity: {
      activeCount: 1, sessionCount: 1,
      active: [{
        id: 'live-1', startedAt: new Date(Date.now() - 4_200).toISOString(), elapsedMs: 4_200,
        method: 'POST', path: '/v1/messages?beta=true', account: 'glm personal',
      }],
      recent: [
        { id: 'event-2', timestamp: new Date().toISOString(), kind: 'request', level: 'info', message: 'POST /v1/messages?beta=true → claude@example.com (200, 2.8s)', method: 'POST', path: '/v1/messages?beta=true', account: 'claude@example.com', status: 200, durationMs: 2_800 },
        { id: 'event-1', timestamp: new Date(Date.now() - 5_000).toISOString(), kind: 'message', level: 'error', message: 'No route for request — returning 429 (cause: rate_limited, recovers-soon: true)', method: null, path: null, account: null, status: null, durationMs: null },
      ],
    },
    currentAccount: 'glm personal',
    routing: { mode: 'automatic', preferredAccount: null, providerMode: routingMode, crossProviderFallbackPolicy: 'always' },
    accounts,
    scheduler: { mode: 'adaptive-least-loaded', globalInFlight: 1, admissionPaused: false },
    upstreamThrottle: { active: false, until: null, reason: null, queued: 0 },
    sessions: { stickyBindings: 0, thinkingProtected: 2, providerPinned: 1, largeContextPinned: 0 },
    control: {
      generatedAt: new Date().toISOString(), backendPid: process.pid, automaticUpdates,
      capabilities: {
        setRoutingMode: true, preferAccount: true, manageAccounts: true, setAccountCap: true, addAccounts: false,
        syncAccounts: true, manageUpdates: true, restart: true, stop: true,
      },
    },
  };
}

const server = http.createServer(async (req, res) => {
  if (req.headers['x-api-key'] !== apiKey) return json(res, 401, { ok: false, error: { code: 'authentication_error', message: 'Invalid key' } });
  if (req.url !== '/maxpool/control') return json(res, 404, { ok: false });
  if (req.method === 'GET') return json(res, 200, snapshot());
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const command = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (command.type === 'set-routing-mode') routingMode = command.payload.mode;
  if (command.type === 'set-automatic-updates') automaticUpdates = command.payload.enabled;
  if (command.type === 'set-account-enabled') {
    const target = accounts.find(item => item.name === command.payload.name);
    if (target) target.enabled = command.payload.enabled;
  }
  if (command.type === 'set-account-cap') {
    const target = accounts.find(item => item.name === command.payload.name);
    if (target) target.capUtilization = command.payload.capUtilization ?? null;
  }
  return json(res, 200, { ok: true, message: `Mock accepted ${command.type}` });
});

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

server.listen(port, '127.0.0.1', () => {
  console.log(`Mock alPool control API: http://127.0.0.1:${port}`);
});
