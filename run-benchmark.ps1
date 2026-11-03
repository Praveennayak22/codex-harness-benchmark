param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^run-[0-9]+$')]
    [string]$Run,

    [ValidateSet('256m', '512m', '1g', '2g')]
    [string]$Memory = '512m',

    [ValidateRange(0.1, 4.0)]
    [double]$Cpu = 0.5,

    [ValidateRange(30, 3600)]
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

foreach ($path in @('Dockerfile', 'task.md', 'starter-project', 'tests')) {
    if (-not (Test-Path $path)) { throw "Missing required file/folder: $path" }
}

$containerName = "codex-$Run"
$workDir = Join-Path $PSScriptRoot $Run
$resultsDir = Join-Path $PSScriptRoot 'results'
$statsFile = Join-Path $resultsDir "$Run-stats.csv"
$agentLog = Join-Path $resultsDir "$Run-codex.log"
$testLog = Join-Path $resultsDir "$Run-tests.log"
$summaryFile = Join-Path $resultsDir 'automated-summary.csv'
$metadataFile = Join-Path $resultsDir "$Run-metadata.json"

if (Test-Path $workDir) { throw "$Run already exists. Choose a new run number." }
if ((Test-Path $statsFile) -or (Test-Path $metadataFile)) { throw "Results for $Run already exist. Choose a new run number." }

# Validate prerequisites before creating a workspace. Authentication stays in the Docker volume.
# Inspect the image by its local name. PowerShell can be unreliable when the
# Docker Go-template output is piped through Select-Object with exit-code checks.
$imageId = (& docker image ls --no-trunc --quiet codex-benchmark | Out-String).Trim()
if (-not $imageId) { throw 'Codex image not found. Check: docker image ls codex-benchmark' }
$authVolume = (& docker volume inspect codex-auth --format '{{.Name}}' 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $authVolume) { throw 'Create and authenticate the codex-auth Docker volume first.' }
$dockerVersion = (& docker version --format '{{.Server.Version}}' | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Docker engine unavailable.' }
$codexVersion = (& docker run --rm codex-benchmark codex --version 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $codexVersion) { throw 'Codex CLI could not start in the Docker image.' }

New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'starter-project') $workDir -Recurse
$task = Get-Content (Join-Path $PSScriptRoot 'task.md') -Raw
$cpuArg = $Cpu.ToString([System.Globalization.CultureInfo]::InvariantCulture)

Write-Host "Creating $containerName ($Memory RAM, $cpuArg CPU)..."
$cid = docker create `
    --name $containerName `
    --memory=$Memory `
    --memory-swap=$Memory `
    --cpus=$cpuArg `
    --cap-drop=ALL `
    --security-opt=no-new-privileges `
    -v codex-auth:/home/node/.codex `
    -v "${workDir}:/workspace" `
    -w /workspace `
    codex-benchmark `
    codex exec --sandbox danger-full-access --skip-git-repo-check $task

if ($LASTEXITCODE -ne 0 -or -not $cid) { throw 'Docker container creation failed.' }
$cid = ($cid | Select-Object -Last 1).Trim()

$startedAt = (Get-Date).ToString('o')
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$timedOut = $false

try {
    docker start $cid | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker container start failed.' }

    while ($true) {
        $state = (docker inspect -f '{{.State.Running}}' $cid).Trim()
        if ($state -ne 'true') { break }

        if ($timer.Elapsed.TotalSeconds -ge $TimeoutSec) {
            $timedOut = $true
            Write-Warning "Stopping run after $TimeoutSec seconds (timeout)."
            docker stop -t 1 $cid | Out-Null
            break
        }

        $raw = docker stats --no-stream --format '{{json .}}' $cid 2>$null
        if ($raw) {
            $s = $raw | ConvertFrom-Json
            $memoryMiB = $null
            if ($s.MemUsage -match '^\s*([0-9.]+)\s*(B|KiB|MiB|GiB)\s*/') {
                $number = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
                switch ($matches[2]) {
                    'B'   { $memoryMiB = $number / 1048576 }
                    'KiB' { $memoryMiB = $number / 1024 }
                    'MiB' { $memoryMiB = $number }
                    'GiB' { $memoryMiB = $number * 1024 }
                }
            }
            if ($null -ne $memoryMiB -and $memoryMiB -gt 0) {
                [pscustomobject]@{
                    Timestamp = (Get-Date).ToString('o')
                    CPU = $s.CPUPerc
                    Memory = $s.MemUsage
                    MemoryMiB = [math]::Round($memoryMiB, 3)
                } | Export-Csv $statsFile -NoTypeInformation -Append
            }
        }
        Start-Sleep -Milliseconds 200
    }
}
finally {
    $timer.Stop()
    $finishedAt = (Get-Date).ToString('o')
}

$exitCode = (docker inspect -f '{{.State.ExitCode}}' $cid).Trim()
$oomKilled = (docker inspect -f '{{.State.OOMKilled}}' $cid).Trim()

# Docker sometimes writes normal Codex output to stderr; capture all streams.
$ErrorActionPreference = 'Continue'
docker logs $cid *> $agentLog
$ErrorActionPreference = 'Stop'
docker rm $cid | Out-Null

Write-Host 'Running independent tests in a separate container...'
& docker run --rm --memory=$Memory --cpus=$cpuArg `
    -v "${workDir}:/benchmark/starter-project:ro" `
    -v "${PSScriptRoot}\tests:/benchmark/tests:ro" `
    -w /benchmark `
    node:22-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da `
    node --test tests/taskManager.test.mjs | Tee-Object -FilePath $testLog
$testExitCode = $LASTEXITCODE

$pass = 0
$fail = 0
foreach ($line in (Get-Content $testLog)) {
    if ($line -match '^# pass (\d+)') { $pass = [int]$matches[1] }
    if ($line -match '^# fail (\d+)') { $fail = [int]$matches[1] }
}

$peakMemory = $null
$highestCpu = $null
if (Test-Path $statsFile) {
    $samples = @(Import-Csv $statsFile)
    if ($samples.Count -gt 0) {
        $peakMemory = ($samples | ForEach-Object { [double]::Parse($_.MemoryMiB, [System.Globalization.CultureInfo]::InvariantCulture) } | Measure-Object -Maximum).Maximum
        $highestCpu = ($samples | ForEach-Object { [double]::Parse(($_.CPU -replace '%', ''), [System.Globalization.CultureInfo]::InvariantCulture) } | Measure-Object -Maximum).Maximum
    }
}

# Classify the cause without mistaking connectivity failures for resource failures.
$logText = if (Test-Path $agentLog) { Get-Content $agentLog -Raw } else { '' }
$networkFailure = $logText -match '(?i)(workspace routing discovery failed|request timed out|failed to connect|connection refused|network is unreachable)'
$modelName = if ($logText -match '(?m)^model:\s*(.+)$') { $matches[1].Trim() } else { 'not captured' }
$status = if ($timedOut) { 'Timeout' }
          elseif ($oomKilled -eq 'true') { 'OOMKilled' }
          elseif ($exitCode -ne '0' -and $networkFailure) { 'NetworkError' }
          elseif ($exitCode -ne '0') { 'AgentError' }
          elseif ($testExitCode -ne 0) { 'TestFailure' }
          elseif ($pass -eq 14 -and $fail -eq 0) { 'Success' }
          else { 'CheckTests' }

$record = [pscustomobject]@{
    Run = $Run
    RAM_Limit = $Memory
    CPU_Limit = $cpuArg
    Time_s = [math]::Round($timer.Elapsed.TotalSeconds, 2)
    Observed_Peak_RAM_MiB = $peakMemory
    Highest_Sampled_CPU_Pct = $highestCpu
    Tests_Passed = $pass
    Tests_Failed = $fail
    Exit_Code = $exitCode
    OOM_Killed = $oomKilled
    Status = $status
}
$metadata = [ordered]@{
    run = $Run
    started_at = $startedAt
    finished_at = $finishedAt
    host_os = [Environment]::OSVersion.VersionString
    docker_server_version = $dockerVersion
    docker_image_id = $imageId.Trim()
    codex_cli_version = $codexVersion.Trim()
    model_name_from_log = $modelName
    test_image = 'node:22-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da'
    task_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'task.md') -Algorithm SHA256).Hash
    fixture_logic_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'starter-project/src/taskManager.mjs') -Algorithm SHA256).Hash
    tests_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'tests/taskManager.test.mjs') -Algorithm SHA256).Hash
    memory_limit = $Memory
    cpu_limit = $cpuArg
    timeout_seconds = $TimeoutSec
    exit_code = $exitCode
    oom_killed = $oomKilled
    test_exit_code = $testExitCode
    classification = $status
    note = 'Elapsed time is container execution plus monitoring overhead; independent verification tests are excluded.'
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $metadataFile

$record | Export-Csv $summaryFile -NoTypeInformation -Append
Write-Host "`n===== BENCHMARK SUMMARY ====="
$record | Format-List
Write-Host "Saved files: $statsFile, $agentLog, $testLog, $summaryFile, $metadataFile"
Write-Host 'Note: Peak RAM and CPU are maxima of samples, not exact instantaneous peaks.'
