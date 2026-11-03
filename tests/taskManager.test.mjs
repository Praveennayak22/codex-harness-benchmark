import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// For post-agent evaluation, set BENCH_TARGET to the fresh run's project folder.
const fallback = fileURLToPath(new URL('../starter-project', import.meta.url));
const target = process.env.BENCH_TARGET || fallback;
const mod = await import(pathToFileURL(path.join(target, 'src', 'taskManager.mjs')).href);
const { addTask, toggleTask, searchTasks, filterByStatus, sortByPriority, summarizeTasks } = mod;

const original = () => [
  { id: 1, title: 'Write report', priority: 'low', completed: false },
  { id: 2, title: 'PAY BILLS', priority: 'high', completed: true },
  { id: 3, title: 'Read book', priority: 'medium', completed: false }
];

test('adds a new task with selected priority and pending status', () => {
  const result = addTask(original(), 'Review code', 'high');
  assert.equal(result.length, 4);
  assert.deepEqual(result[3], { id: 4, title: 'Review code', priority: 'high', completed: false });
});

test('adding a task does not mutate original tasks', () => {
  const tasks = original();
  addTask(tasks, 'New task');
  assert.equal(tasks.length, 3);
});

test('toggling a task changes completed state', () => {
  assert.equal(toggleTask(original(), 1)[0].completed, true);
});

test('toggling an unknown id leaves tasks unchanged', () => {
  assert.deepEqual(toggleTask(original(), 999), original());
});

test('summary gives correct totals', () => {
  assert.deepEqual(summarizeTasks(original()), { total: 3, completed: 1, pending: 2 });
});

test('empty search shows every task', () => {
  assert.deepEqual(searchTasks(original(), ''), original());
});

test('search is case-insensitive', () => {
  assert.deepEqual(searchTasks(original(), 'pay').map(t => t.id), [2]);
});

test('no-match search returns an empty list without throwing', () => {
  assert.deepEqual(searchTasks(original(), 'does not exist'), []);
});

test('completed filter returns completed tasks only', () => {
  assert.deepEqual(filterByStatus(original(), 'completed').map(t => t.id), [2]);
});

test('pending filter returns pending tasks only', () => {
  assert.deepEqual(filterByStatus(original(), 'pending').map(t => t.id), [1, 3]);
});

test('all filter does not remove any tasks', () => {
  assert.deepEqual(filterByStatus(original(), 'all'), original());
});

test('sort orders high then medium then low', () => {
  assert.deepEqual(sortByPriority(original()).map(t => t.priority), ['high', 'medium', 'low']);
});

test('sorting leaves original input order unchanged', () => {
  const tasks = original();
  sortByPriority(tasks);
  assert.deepEqual(tasks.map(t => t.id), [1, 2, 3]);
});

test('blank titles are not added', () => {
  assert.equal(addTask(original(), '    ').length, 3);
});
