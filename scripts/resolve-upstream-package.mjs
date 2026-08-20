#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { writeFile } from 'node:fs/promises';

function readStage(stage) {
  const result = spawnSync('git', ['show', `:${stage}:package.json`], {
    cwd: process.cwd(),
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    throw new Error(`Could not read Git stage ${stage} for package.json.`);
  }
  return JSON.parse(result.stdout);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function equal(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function mergeValue(base, ours, theirs, path, conflicts) {
  if (equal(ours, theirs)) return ours;
  if (equal(ours, base)) return theirs;
  if (equal(theirs, base)) return ours;

  if (isPlainObject(base) && isPlainObject(ours) && isPlainObject(theirs)) {
    const merged = {};
    const keys = new Set([...Object.keys(base), ...Object.keys(ours), ...Object.keys(theirs)]);
    for (const key of keys) {
      const nextPath = path ? `${path}.${key}` : key;
      const hasBase = Object.hasOwn(base, key);
      const hasOurs = Object.hasOwn(ours, key);
      const hasTheirs = Object.hasOwn(theirs, key);
      const baseValue = hasBase ? base[key] : undefined;
      const ourValue = hasOurs ? ours[key] : undefined;
      const theirValue = hasTheirs ? theirs[key] : undefined;
      const value = mergeValue(baseValue, ourValue, theirValue, nextPath, conflicts);
      if (value !== undefined) merged[key] = value;
    }
    return merged;
  }

  conflicts.push(path);
  return ours;
}

const base = readStage(1);
const ours = readStage(2);
const theirs = readStage(3);

if (base.name !== 'maxpool' || ours.name !== 'alpool' || theirs.name !== 'maxpool') {
  throw new Error('Package identities do not match the guarded MaxPool-to-alPool merge case.');
}
if (typeof theirs.version !== 'string' || !theirs.version) {
  throw new Error('The upstream package version is missing.');
}

const conflicts = [];
const merged = mergeValue(base, ours, theirs, '', conflicts);
if (conflicts.length > 0) {
  throw new Error(`Package metadata changed incompatibly at: ${conflicts.join(', ')}`);
}

await writeFile('package.json', `${JSON.stringify(merged, null, 2)}\n`);
