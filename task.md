# Coding-agent benchmark task: TaskFlow bug fixing

You are given an existing, small JavaScript Task Manager web application.
Fix its behavior while preserving existing working functionality and its public
function names/exports. Do not add third-party dependencies.

Acceptance criteria:
1. Search matches task titles case-insensitively.
2. Searching for a title with no matches returns an empty array and must not throw.
3. Status filtering: `completed` returns only completed tasks, `pending` only
   pending tasks, and `all` returns all tasks.
4. Tasks are sorted from high to medium to low priority.
5. Existing add, toggle, summary and other working behavior must remain correct.

Keep the application executable in the browser. Do not change test files or
benchmark runner configurations. Summarize what you changed when finished.
