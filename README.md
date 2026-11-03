# Codex Harness Benchmarking Under Resource Constraints

A reproducible proof of concept for evaluating **OpenAI Codex CLI** when its local harness runs in a Docker container with restricted **RAM** and **CPU**.

## Objective

Evaluate whether a coding agent can modify an existing JavaScript application correctly under local resource constraints, and collect execution time, observed container memory usage, sampled CPU usage, process exit status, and independent test results. This project is an initial harness evaluation, **not** a comparison against Loop or other agents yet.

> **Scope:** Docker limits apply to Codex CLI and the local processes it launches. The AI model runs remotely on OpenAI infrastructure, outside these limits. Consequently, wall-clock time includes network and model latency.

## What happened before and after Codex

**Starting project:** TaskFlow, an existing JavaScript Task Manager supporting task creation, completion toggling, search, status filtering, priority sorting, and task summaries. We deliberately introduced **four bugs** into its task logic:

1. Searching was case-sensitive when it should ignore letter case.
2. Searching for a nonexistent task threw an error instead of returning an empty list.
3. The completed and pending filters returned the opposite tasks.
4. Priority sorting ran from low to high rather than high to low.

We created **14 independent tests** for the application's behavior. **Before Codex, 9 tests passed and 5 failed (9/14)**. The four bugs caused five test failures because the incorrect status filter affected both completed and pending cases. **These are counts of tests, not files.**

**Repair and verification workflow:** For each experiment, the runner copies the original buggy application into a fresh workspace, starts Codex CLI inside Docker with a specified CPU/RAM limit, and gives it the same bug-fixing prompt in `task.md`. Codex inspects and edits the application source. After it exits, a separate Node.js container runs the **14 independent acceptance tests**, which were not mounted in Codex's workspace. The runner also measures elapsed time, sampled container resource usage, process exit status, and OOM status.

**After successful Codex repairs, all 14 tests passed and none failed (14/14).** The task therefore improved from **9/14 → 14/14** on the tested behaviors while preserving existing features covered by those tests. This is a focused bug-fixing benchmark, not proof that every possible application behavior is correct.

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
├── .gitignore                  # Excludes raw logs, runs, and local credentials
├── .dockerignore               # Minimal Docker build context
├── .gitattributes              # Consistent Windows/Linux line endings
└── README.md
```

Generated folders (`run-*`), raw logs, and local authentication information are intentionally excluded from Git.

## Requirements

- Windows with PowerShell and Docker Desktop configured for Linux containers
- Docker Engine working (`docker run --rm hello-world`)
- Internet access and a valid Codex sign-in
- Git for uploading the project

The improved Dockerfile pins **Codex CLI 0.166.0** and the **Node.js 22 base image digest recorded for the original amd64 environment**, instead of installing moving `latest` dependencies. The independent Node.js test container also uses that image digest. This preserves the local tool version and base image; the remotely served AI model and its service behavior are outside the Docker image. Rebuilding the frozen image does not retroactively change the original measurements.

## Setup

From the repository root in PowerShell:

```powershell
docker build -t codex-benchmark .
docker run --rm codex-benchmark
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
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-benchmark.ps1 -Run run-14 -Memory 512m -Cpu 1
```

Example CPU-limited configuration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-benchmark.ps1 -Run run-15 -Memory 512m -Cpu 0.5 -TimeoutSec 180
```

The runner creates a fresh task copy, starts Codex inside the configured container, samples Docker resource statistics, retains the Codex log, and runs independent acceptance tests afterward. Local outputs are written under `results/` and excluded from Git. The updated runner also writes `results/run-ID-metadata.json` recording the image ID, Codex CLI version, model name if present in logs, Docker engine version, task/fixture/test hashes, resource limits, timestamps, and final exit classification. These metadata files are local and can be selectively reviewed before publication. The runner requires an existing `codex-auth` volume; it never copies authentication data into a repository.

To test the original fixture independently:

```powershell
docker run --rm --memory="512m" --cpus="1" `
  -v "${PWD}:/benchmark:ro" -w /benchmark `
  node:22-bookworm-slim node --test tests/taskManager.test.mjs
```

## Complete experiment results (one table)

The table includes the **initial baseline**, the **manual proof-of-concept run (01)**, and **all monitored runs (02–13)**. The memory sweep used **1 CPU**, while the CPU sweep used **512 MiB RAM**. Dashes mean the measurement was not collected or the test result was not established.

| Experiment | Run | RAM limit | CPU limit | Time (s) | Highest sampled RAM (MiB) | Highest sampled CPU (%) | Tests passed | Exit code | Outcome |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| **Before Codex** | Baseline | — | — | — | — | — | **9/14** | — | **5 tests failing** |
| Initial manual validation | 01 | — | — | 30.05 | — | — | **14/14** | 0 | Success; resource measurements not collected |
| Memory sweep | 02 | 2048 MiB | 1 | 26.35 | 233.4 | 32.26 | **14/14** | 0 | Success |
| Memory sweep | 03 | 1024 MiB | 1 | 46.61 | 167.0 | 9.28 | — | 1 | Network/connection failure; not OOM |
| Memory sweep | 04 | 1024 MiB | 1 | 23.96 | 209.2 | 16.29 | **14/14** | 0 | Success |
| Memory sweep | 05 | 512 MiB | 1 | 30.31 | 226.4 | 27.23 | **14/14** | 0 | Success |
| Memory sweep | 06 | 256 MiB | 1 | 26.13 | 221.7 | 39.46 | **14/14** | 0 | Success |
| CPU sweep | 07 | 512 MiB | 0.5 | 28.58 | 230.6 | 35.83 | **14/14** | 0 | Success |
| CPU sweep | 08 | 512 MiB | 0.25 | 34.36 | 238.8 | 25.16 | **14/14** | 0 | Success |
| CPU sweep | 09 | 512 MiB | 1 | 26.32 | 222.7 | 38.71 | **14/14** | 0 | Success |
| CPU sweep | 10 | 512 MiB | 0.5 | 28.60 | 210.9 | 44.18 | **14/14** | 0 | Success |
| CPU sweep | 11 | 512 MiB | 0.25 | 30.28 | 217.6 | 25.24 | **14/14** | 0 | Success |
| CPU sweep | 12 | 512 MiB | 1 | 28.58 | 226.7 | 35.18 | **14/14** | 0 | Success |
| CPU sweep | 13 | 512 MiB | 1 | 28.40 | 213.4 | 26.05 | **14/14** | 0 | Success |

**What the results show:** Codex completed this particular repair successfully at **256 MiB RAM with 1 CPU** (Run 06) and separately at **0.25 CPU with 512 MiB RAM** (Runs 08 and 11). These two smallest limits were **not tested together**.

**CPU averages (512 MiB RAM; automated CPU runs only):** 1 CPU = **27.77 s** (Runs 09, 12, 13); 0.5 CPU = **28.59 s** (Runs 07, 10); 0.25 CPU = **32.32 s** (Runs 08, 11). The 0.25-CPU average was about **16.4% longer** than the 1-CPU average. With only two or three trials per CPU setting and remote model/network latency included, this is a preliminary observation, **not** a statistically established causal slowdown.

**Failure note:** Run 03 ended with a connection/routing error after a reported Wi-Fi interruption, with `OOMKilled=false`. It is included for completeness but excluded from successful-run performance comparisons. Run 01 was an initial manual validation without CPU/RAM samples and is likewise excluded from resource comparisons.

**Measurement note:** CPU and memory figures are the **highest observed samples**, not exact peaks. The Docker limits apply to the local Codex process and its child processes, while the AI model runs remotely.

For machine-readable results, see [memory-results.csv](benchmark-results/memory-results.csv) and [cpu-results.csv](benchmark-results/cpu-results.csv).

## Diagnostics and reproducibility

- Each new run must use an unused ID, so the original buggy fixture is never silently overwritten.
- The runner differentiates `Success`, `TestFailure`, `OOMKilled`, `Timeout`, `AgentError`, and a *heuristic* `NetworkError` based on messages in the private log. A network failure does not prove the resource limit is inadequate.
- The execution timer covers container startup, Codex execution, and monitoring overhead; **independent tests run afterward and are not included** in that time.
- Results already published in `benchmark-results/` are historic observations. The improved runner does not regenerate or alter them.
- For a comparable cross-harness study, record the underlying model, actual task inputs, repeated runs, and any interruptions; keep each tool's execution conditions equivalent as far as practical.

## Interpretation and limitations

- Codex completed the TaskFlow task successfully in the tested configurations, including one run at **256 MiB RAM / 1 CPU** and two runs at **512 MiB RAM / 0.25 CPU**. These were tested **separately**; the combination of 256 MiB and 0.25 CPU has not been established.
- The measured memory peaks and CPU percentages are **sampled Docker statistics**, not exact instantaneous peaks. The highest reported CPU percentage is not cumulative CPU time. `docker stats --no-stream` has nontrivial sampling overhead; despite a short sleep, samples may be several seconds apart.
- A low CPU quota may affect local commands while remote inference latency can dominate wall-clock duration. Internet interruptions can cause unrelated failures.
- One task and a small number of runs per setting do not establish general reliability, minimum hardware requirements, or statistically significant differences. This is a **smoke-test benchmark**: the task prompt explicitly names the bugs, making it less challenging than an unseen real-world issue.
- All 14 Node.js tests passing validates the behaviors covered by those tests. It is not a substitute for browser integration, visual checks, or broader correctness tests. The independent acceptance tests are outside the agent workspace but the intended behaviors are specified in the prompt.
- The setup measures the *Codex-based coding agent* as configured here; no claim of superiority over **Loop**, Claude Code, or any other harness is made.
- For a fair multi-harness study, use the same starter commit, prompt, independent tests, CPU/RAM limits, measurement method, repetition count, and (where feasible) model. Different remote models introduce an additional comparison variable.

## Security notes

The benchmark runner uses `codex exec --sandbox danger-full-access` **inside a Docker container**, where Docker is the primary isolation boundary. The container is not an absolute security boundary: use only trusted fixtures; do not mount personal directories, the Docker socket, or secrets into the workspace. Authentication uses a separate Docker volume (which should not be exported). Raw agent logs can contain sensitive details and are excluded from Git. Review all exported artifacts before publication.

## Next steps

1. Repeat memory-limit runs using the same automated runner and several trials per configuration.
2. Improve resource sampling and distinguish local compute time from network/model waiting.
3. Benchmark additional tasks of different difficulty, then run the exact same task suite against Loop and other harnesses.
4. Publish the reproducible methodology, code, configuration, and aggregated results.
