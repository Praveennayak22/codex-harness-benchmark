# Codex Harness Benchmarking Under Resource Constraints

A reproducible proof of concept for evaluating **OpenAI Codex CLI** when its local harness runs in a Docker container with restricted **RAM** and **CPU**.

## Objective

Evaluate whether a coding agent can modify an existing JavaScript application correctly under local resource constraints, and collect execution time, observed container memory usage, sampled CPU usage, process exit status, and independent test results. This project is an initial harness evaluation, **not** a comparison against Loop or other agents yet.

> **Scope:** Docker limits apply to Codex CLI and the local processes it launches. The AI model runs remotely on OpenAI infrastructure, outside these limits. Consequently, wall-clock time includes network and model latency.

## Task: TaskFlow bug fixing

The `starter-project/` directory contains a small, dependency-free JavaScript task-management web application with deliberately introduced defects. The task, defined in `task.md`, asks the agent to:

1. Make searches case-insensitive.
2. Return an empty array for searches with no matches, without throwing.
3. Correct the completed and pending status filters.
4. Sort task priorities high → medium → low.
5. Preserve existing add, toggle, and summary functionality.

The independent Node.js tests in `tests/` are mounted only into the **verification** container and are not presented to the agent's working directory. Before repair, the fixture passes **9/14** tests; after a correct repair, it should pass **14/14**.

## Repository structure

```text
codex-harness-benchmark/
├── Dockerfile                  # Codex CLI environment
├── run-benchmark.ps1           # Automated runner for Windows PowerShell
├── task.md                     # Identical coding task prompt
├── starter-project/            # Original intentionally buggy application
├── tests/                      # Independent acceptance tests
├── benchmark-results/
│   ├── cpu-results.csv         # Shared automated experiment summary
│   └── memory-results.csv      # Shared memory-experiment summary
├── .gitignore
└── README.md
```

Generated folders (`run-*`), raw logs, and local authentication information are intentionally excluded from Git.

## Requirements

- Windows with PowerShell and Docker Desktop configured for Linux containers
- Docker Engine working (`docker run --rm hello-world`)
- Internet access and a valid Codex sign-in
- Git for uploading the project

The Dockerfile builds the container using a Node.js 22 Linux base and installs `@openai/codex`. Initial experiments used **Codex CLI 0.166.0**; npm's latest version may differ when rebuilding. For strict reproducibility, pin the Codex package and image digest before performing a formal comparison.

## Setup

From the repository root in PowerShell:

```powershell
docker build -t codex-benchmark .
docker volume create codex-auth
```

Grant the container's non-root `node` user access to the authentication volume (one time):

```powershell
docker run --rm --user root -v codex-auth:/home/node/.codex codex-benchmark sh -c "chown 1000:1000 /home/node/.codex"
```

Sign in interactively:

```powershell
docker run --rm -it -v codex-auth:/home/node/.codex codex-benchmark codex login --device-auth
```

The volume is stored by Docker and **must not be exported or committed**. Never place access tokens in the repository.

## Reproduce a benchmark

Use a new run ID for every experiment to ensure the project starts from the original buggy fixture:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-benchmark.ps1 -Run run-13 -Memory 512m -Cpu 1
```

Example CPU-limited configuration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-benchmark.ps1 -Run run-14 -Memory 512m -Cpu 0.5
```

The runner creates a fresh task copy, starts Codex inside the configured container, samples Docker resource statistics, retains the Codex log, and runs independent acceptance tests afterward. Local outputs are written under `results/` and excluded from Git. The exact metrics available depend on the runner version.

To test the original fixture independently:

```powershell
docker run --rm --memory="512m" --cpus="1" `
  -v "${PWD}:/benchmark:ro" -w /benchmark `
  node:22-bookworm-slim node --test tests/taskManager.test.mjs
```

## Preliminary results

### Memory limits (1 CPU)

| Run | RAM limit | Wall time (s) | Highest sampled RAM (MiB) | Tests | Exit |
|---|---:|---:|---:|---:|---:|
| run-02 | 2048 MiB | 26.35 | 233.4 | 14/14 | 0 |
| run-04 | 1024 MiB | 23.96 | 209.2 | 14/14 | 0 |
| run-05 | 512 MiB | 30.31 | 226.4 | 14/14 | 0 |
| run-06 | 256 MiB | 26.13 | 221.7 | 14/14 | 0 |

Run 03 at 1024 MiB terminated with a connection/routing error after a reported Wi-Fi interruption (exit code 1, `OOMKilled=false`). It is **excluded from successful-run performance comparisons**, but retained as a recorded operational failure.

### CPU limits (512 MiB RAM; automated runner)

| CPU quota | Runs | Times (s) | Average time (s) | Correctness |
|---:|---|---|---:|---|
| 1 CPU | run-09, run-12 | 26.32, 28.58 | **27.45** | 2/2 passed 14/14 |
| 0.5 CPU | run-07, run-10 | 28.58, 28.60 | **28.59** | 2/2 passed 14/14 |
| 0.25 CPU | run-08, run-11 | 34.36, 30.28 | **32.32** | 2/2 passed 14/14 |

The average at 0.25 CPU was approximately 17.7% longer than the average at 1 CPU. This is a **descriptive observation**, not a causal estimate of CPU slowdown.

## Interpretation and limitations

- Codex completed the TaskFlow task successfully in the tested configurations, including one run at **256 MiB RAM / 1 CPU** and two runs at **512 MiB RAM / 0.25 CPU**. These were tested **separately**; the combination of 256 MiB and 0.25 CPU has not been established.
- The measured memory peaks and CPU percentages are **sampled Docker statistics**, not exact instantaneous peaks. The highest reported CPU percentage is not cumulative CPU time.
- A low CPU quota may affect local commands while remote inference latency can dominate wall-clock duration. Internet interruptions can cause unrelated failures.
- One task and a small number of runs per setting do not establish general reliability, minimum hardware requirements, or statistically significant differences.
- All 14 Node.js tests passing validates the behaviors covered by those tests. It is not a substitute for browser integration, visual checks, or broader correctness tests.
- The setup measures the *Codex-based coding agent* as configured here; no claim of superiority over **Loop**, Claude Code, or any other harness is made.
- For a fair multi-harness study, use the same starter commit, prompt, independent tests, CPU/RAM limits, measurement method, repetition count, and (where feasible) model. Different remote models introduce an additional comparison variable.

## Security notes

The benchmark runner uses `codex exec --sandbox danger-full-access` **inside a Docker container**, where Docker is the primary isolation boundary. The container is not an absolute security boundary: use only trusted fixtures; do not mount personal directories, the Docker socket, or secrets into the workspace. Authentication uses a separate Docker volume. Review all exported artifacts before publication.

## Next steps

1. Repeat memory-limit runs using the same automated runner and several trials per configuration.
2. Improve resource sampling and distinguish local compute time from network/model waiting.
3. Benchmark additional tasks of different difficulty, then run the exact same task suite against Loop and other harnesses.
4. Publish the reproducible methodology, code, configuration, and aggregated results.
