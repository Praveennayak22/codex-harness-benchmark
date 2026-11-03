import {
  addTask,
  toggleTask,
  searchTasks,
  filterByStatus,
  sortByPriority,
  summarizeTasks
} from './taskManager.mjs';

let tasks = [
  { id: 1, title: 'Prepare project report', priority: 'high', completed: false },
  { id: 2, title: 'Review JavaScript tests', priority: 'medium', completed: true },
  { id: 3, title: 'Update README', priority: 'low', completed: false }
];

const list = document.querySelector('#task-list');
const stats = document.querySelector('#stats');
const form = document.querySelector('#task-form');
const search = document.querySelector('#search');
const status = document.querySelector('#status');

function render() {
  const summary = summarizeTasks(tasks);
  stats.textContent = `${summary.total} total · ${summary.completed} completed · ${summary.pending} pending`;

  const visible = sortByPriority(filterByStatus(searchTasks(tasks, search.value), status.value));
  list.replaceChildren();

  if (visible.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'empty';
    empty.textContent = 'No matching tasks.';
    list.append(empty);
    return;
  }

  for (const task of visible) {
    const item = document.createElement('li');
    item.className = 'task';
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = task.completed;
    checkbox.setAttribute('aria-label', `Toggle ${task.title}`);
    checkbox.addEventListener('change', () => {
      tasks = toggleTask(tasks, task.id);
      render();
    });

    const title = document.createElement('span');
    title.className = task.completed ? 'done' : '';
    title.textContent = task.title;

    const priority = document.createElement('small');
    priority.className = `priority ${task.priority}`;
    priority.textContent = task.priority.toUpperCase();
    item.append(checkbox, title, priority);
    list.append(item);
  }
}

form.addEventListener('submit', event => {
  event.preventDefault();
  const title = document.querySelector('#title');
  const priority = document.querySelector('#priority');
  tasks = addTask(tasks, title.value, priority.value);
  title.value = '';
  render();
});
search.addEventListener('input', render);
status.addEventListener('change', render);
render();
