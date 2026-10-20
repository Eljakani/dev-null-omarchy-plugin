import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Model.js is imported by QML; evaluate it as a script to test its pure functions.
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../Model.js', import.meta.url), 'utf8'), context);

test('usernames keeps five valid, unique handles', () => {
  const names = context.usernames(' @Ada, ada, invalid name, bob, c, d, e, f');
  assert.deepEqual(Array.from(names), ['Ada', 'bob', 'c', 'd', 'e']);
});

test('public log accepts only dev/null commit links', () => {
  const payload = JSON.stringify({ data: [
    { id: 1, author: { username: 'ada' }, created_at: '2026-01-02T00:00:00Z', html_url: 'https://dev-null.sh/commits/1', body: 'hello' },
    { id: 2, author: { username: 'bad' }, created_at: '2026-01-02T00:00:00Z', html_url: 'https://dev-null.sh.evil.test/commits/2' },
  ] });
  const commits = context.parseCommits(payload);
  assert.equal(commits.length, 1);
  assert.equal(commits[0].username, 'ada');
});

test('merged log deduplicates and orders commits newest first', () => {
  const old = { id: 'one', timestamp: 1 };
  const recent = { id: 'two', timestamp: 2 };
  const commits = context.merged([old], [recent, old]);
  assert.deepEqual(Array.from(commits, item => item.id), ['two', 'one']);
});
