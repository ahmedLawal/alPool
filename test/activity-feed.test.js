import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ActivityFeed } from '../src/activity-feed.js';

test('activity feed exposes in-flight and completed requests without bodies', () => {
  let now = Date.parse('2026-08-19T12:00:00Z');
  const feed = new ActivityFeed({
    now: () => now,
    accountType: name => name === 'glm personal' ? 'provider' : 'oauth',
  });
  feed.onRequestStart(7, {
    method: 'POST', path: '/v1/messages?beta=true&api_key=secret-value', sessionKey: 'abcdef12-rest',
  });
  feed.onRequestRouted(7, { account: 'glm personal' });

  now += 1_250;
  const active = feed.snapshot();
  assert.equal(active.activeCount, 1);
  assert.equal(active.sessionCount, 1);
  assert.equal(active.active[0].elapsedMs, 1_250);
  assert.match(active.active[0].path, /api_key=%5Bredacted%5D/);
  assert.equal('sessionKey' in active.active[0], false, 'full session identifiers are not exposed');

  feed.onRequestEnd(7, { method: 'POST', path: '/v1/messages?beta=true', account: 'glm personal', status: 200 });
  const completed = feed.snapshot();
  assert.equal(completed.activeCount, 0);
  assert.equal(completed.recent[0].kind, 'request');
  assert.equal(completed.recent[0].durationMs, 1_250);
  assert.match(completed.recent[0].message, /POST \/v1\/messages\?beta=true → glm personal \(200, 1\.3s\)/);
  assert.match(completed.recent[0].message, /\[sess abcdef12\]/);
});

test('activity feed is newest-first, bounded, and de-duplicates TUI mirrors', () => {
  let now = 1_000;
  const feed = new ActivityFeed({ limit: 2, now: () => now });
  feed.addMessage('[alPool] first');
  now += 10;
  feed.addMessage('first');
  assert.equal(feed.snapshot().recent.length, 1, 'same TUI/event-log line is stored once');
  now += 300;
  feed.addMessage('second');
  now += 300;
  feed.addMessage('third', { level: 'error' });
  assert.deepEqual(feed.snapshot().recent.map(event => event.message), ['third', 'second']);
  assert.equal(feed.snapshot().recent[0].level, 'error');
});
