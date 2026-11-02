import net from 'node:net';
import { readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

// Same switch file as upstream rc-gate. Only gate-routed clients follow it.
export class ClientRoute {
  constructor({ path = join(homedir(), '.config', 'rc-gate-route'), probe } = {}) {
    this.path = path;
    this.probe = probe || (() => new Promise(resolve => {
      const socket = net.createConnection({ host: '127.0.0.1', port: 3457 });
      const finish = value => { socket.destroy(); resolve(value); };
      socket.setTimeout(500);
      socket.once('connect', () => finish(true));
      socket.once('error', () => finish(false));
      socket.once('timeout', () => finish(false));
      socket.unref();
    }));
    this.available = false;
    this.checkedAt = 0;
    this.pending = null;
  }

  async check() {
    if (this.pending) return this.pending;
    this.pending = Promise.resolve().then(() => this.probe()).then(Boolean).catch(() => false);
    try { this.available = await this.pending; this.checkedAt = Date.now(); return this.available; }
    finally { this.pending = null; }
  }

  snapshot() {
    if (!this.pending && Date.now() - this.checkedAt > 5000) void this.check();
    let mode = 'pool';
    try { if (readFileSync(this.path, 'utf8').trim() === 'direct') mode = 'direct'; } catch { /* default */ }
    return { mode, gateAvailable: this.available };
  }

  async set(mode) {
    if (!['pool', 'direct'].includes(mode)) throw new Error('Choose pool or direct.');
    if (!await this.check()) throw new Error('rc-gate is not running. Your direct proxy connection continues using alPool.');
    await mkdir(dirname(this.path), { recursive: true });
    await writeFile(this.path, mode + '\n', { mode: 0o600 });
  }
}
