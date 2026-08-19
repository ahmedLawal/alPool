const DEFAULT_LIMIT = 200;

function cleanText(value, maxLength = 480) {
  return String(value ?? '').replace(/^\[alPool\]\s*/, '').replace(/\s*\n\s*/g, ' ').slice(0, maxLength);
}

function safePath(value) {
  const raw = cleanText(value, 300);
  try {
    const url = new URL(raw, 'http://localhost');
    for (const key of url.searchParams.keys()) {
      if (/(?:token|key|secret|auth|credential)/i.test(key)) url.searchParams.set(key, '[redacted]');
    }
    return `${url.pathname}${url.search}`;
  } catch {
    return raw;
  }
}

export class ActivityFeed {
  constructor({ limit = DEFAULT_LIMIT, now = () => Date.now(), accountType = () => null } = {}) {
    this.limit = Math.max(1, Number(limit) || DEFAULT_LIMIT);
    this.now = now;
    this.accountType = accountType;
    this.active = new Map();
    this.recent = [];
    this.sequence = 0;
  }

  onRequestStart(id, info = {}) {
    const startedAt = this.now();
    this.active.set(id, {
      id: String(id),
      startedAt,
      method: cleanText(info.method, 20),
      path: safePath(info.path),
      account: null,
      sessionKey: info.sessionKey ? String(info.sessionKey) : null,
    });
  }

  onRequestRouted(id, info = {}) {
    const request = this.active.get(id);
    if (request) request.account = cleanText(info.account, 160) || null;
  }

  onRequestEnd(id, info = {}) {
    const request = this.active.get(id);
    this.active.delete(id);
    const endedAt = this.now();
    const durationMs = request ? Math.max(0, endedAt - request.startedAt) : null;
    const duration = durationMs == null ? '?' : (durationMs / 1000).toFixed(1);
    const account = cleanText(info.account || request?.account || '?', 160);
    const method = cleanText(info.method || request?.method, 20);
    const path = safePath(info.path || request?.path);
    const status = Number.isFinite(Number(info.status)) ? Number(info.status) : null;
    const isProvider = this.accountType(account) === 'provider';
    const sessionTag = isProvider && request?.sessionKey
      ? `  [sess ${request.sessionKey.slice(0, 8)}]`
      : '';
    this.addMessage(`${method} ${path} → ${account} (${status ?? '?'}, ${duration}s)${sessionTag}`, {
      kind: 'request',
      level: status != null && status >= 400 ? 'error' : 'info',
      timestampMs: endedAt,
      method,
      path,
      account,
      status,
      durationMs,
    });
  }

  addMessage(message, {
    kind = 'message', level = 'info', timestampMs = this.now(), method = null,
    path = null, account = null, status = null, durationMs = null,
  } = {}) {
    const normalized = cleanText(message);
    if (!normalized) return;
    const latest = this.recent[0];
    if (latest?.message === normalized && Math.abs(timestampMs - latest._timestampMs) < 250) return;
    this.recent.unshift({
      id: `${timestampMs}-${++this.sequence}`,
      timestamp: new Date(timestampMs).toISOString(),
      kind,
      level: level === 'error' ? 'error' : 'info',
      message: normalized,
      method,
      path,
      account,
      status,
      durationMs,
      _timestampMs: timestampMs,
    });
    if (this.recent.length > this.limit) this.recent.length = this.limit;
  }

  snapshot() {
    const now = this.now();
    const active = [...this.active.values()].reverse().map(request => ({
      id: request.id,
      startedAt: new Date(request.startedAt).toISOString(),
      elapsedMs: Math.max(0, now - request.startedAt),
      method: request.method,
      path: request.path,
      account: request.account,
    }));
    return {
      activeCount: active.length,
      sessionCount: new Set([...this.active.values()].map(request => request.sessionKey).filter(Boolean)).size,
      active,
      recent: this.recent.map(({ _timestampMs, ...event }) => event),
    };
  }
}
