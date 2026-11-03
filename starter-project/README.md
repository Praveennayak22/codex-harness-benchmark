# TaskFlow: intentionally buggy starter application

This small dependency-free HTML/CSS/JavaScript application is a benchmark fixture.
It contains known defects by design. Agents should fix the code under `src/`.

Features: create task, toggle completed, search, filter by status, sort by priority.

To view the browser UI, serve `src/` with any static HTTP server. For example,
from the `src/` directory run `python -m http.server 8080` if Python is installed,
then visit http://localhost:8080.

Do not edit benchmark verification tests, which live outside this repository.
