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
    name, type, provider, enabled: true, runtime: type === 'provider', status,
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
    currentAccount: 'glm personal',
    routing: { mode: 'automatic', preferredAccount: null, providerMode: routingMode, crossProviderFallbackPolicy: 'always' },
    accounts,
    scheduler: { mode: 'adaptive-least-loaded', globalInFlight: 1, admissionPaused: false },
    upstreamThrottle: { active: false, until: null, reason: null, queued: 0 },
    sessions: { stickyBindings: 0, thinkingProtected: 2, providerPinned: 1, largeContextPinned: 0 },
    control: {
      generatedAt: new Date().toISOString(), backendPid: process.pid, automaticUpdates,
      capabilities: {
        setRoutingMode: true, preferAccount: true, manageAccounts: true, addAccounts: false,
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
  return json(res, 200, { ok: true, message: `Mock accepted ${command.type}` });
});

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

server.listen(port, '127.0.0.1', () => {
  console.log(`Mock alPool control API: http://127.0.0.1:${port}`);
});
