# Codex / Loop harness benchmark starter

This archive intentionally contains **only** the new benchmark files. It will
not overwrite your existing `Dockerfile` or Docker image configuration.

## Contents
- `starter-project/`: the original buggy JavaScript TaskFlow application
- `tests/`: independent Node.js test suite (keep outside the agent's workspace)
- `task.md`: fixed prompt for a coding harness

## Baseline test (in PowerShell)
Open PowerShell in `C:\Users\prave\codex-benchmark` and run:

```powershell
docker run --rm --memory="2g" --cpus="1" -v "${PWD}:/benchmark:ro" -w /benchmark node:22-bookworm-slim node --test tests/taskManager.test.mjs
```

Expected intentional baseline: **14 tests total; 9 pass; 5 fail**.
The defects involve search case sensitivity, no-result search, reversed
status filtering, and reversed priority sorting. This is expected!

Do not show or mount `tests/` inside the coding agent's container. After each
agent run, execute these independent tests against the agent's output. Do not
run agents directly on `starter-project`: make a fresh copy for every run.
