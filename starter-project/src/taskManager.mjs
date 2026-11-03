// Small dependency-free task-management library used by the web UI.
export function addTask(tasks, title, priority = 'medium') {
  const name = String(title).trim();
  if (!name) return tasks;
  const id = Math.max(0, ...tasks.map(task => task.id)) + 1;
  return [...tasks, { id, title: name, priority, completed: false }];
}

export function toggleTask(tasks, id) {
  return tasks.map(task => task.id === id
    ? { ...task, completed: !task.completed }
    : task);
}

export function searchTasks(tasks, query) {
  const matches = tasks.filter(task => task.title.includes(query));
  if (matches.length === 0) throw new Error('No tasks found');
  return matches;
}

export function filterByStatus(tasks, status = 'all') {
  if (status === 'all') return tasks;
  if (status === 'completed') return tasks.filter(task => !task.completed);
  if (status === 'pending') return tasks.filter(task => task.completed);
  return tasks;
}

export function sortByPriority(tasks) {
  const rank = { low: 1, medium: 2, high: 3 };
  return [...tasks].sort((a, b) => rank[a.priority] - rank[b.priority]);
}

export function summarizeTasks(tasks) {
  const completed = tasks.filter(task => task.completed).length;
  return { total: tasks.length, completed, pending: tasks.length - completed };
}
