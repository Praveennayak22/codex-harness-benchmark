param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^run-[0-9]+$')]
    [string]$Run,

    [ValidateSet('256m', '512m', '1g', '2g')]
    [string]$Memory = '512m',

    [ValidateRange(0.1, 4.0)]
    [double]$Cpu = 0.5
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

if (Test-Path $workDir) { throw "$Run already exists. Choose a new run number." }
if (Test-Path $statsFile) { throw "$statsFile already exists. Choose a new run number." }

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

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$timedOut = $false

try {
    docker start $cid | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker container start failed.' }

    while ($true) {
        $state = (docker inspect -f '{{.State.Running}}' $cid).Trim()
        if ($state -ne 'true') { break }

        if ($timer.Elapsed.TotalSeconds -ge 180) {
            $timedOut = $true
            Write-Warning 'Stopping run after 180 seconds (timeout).'
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
    node:22-bookworm-slim `
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

$status = if ($timedOut) { 'Timeout' }
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
$record | Export-Csv $summaryFile -NoTypeInformation -Append
Write-Host "`n===== BENCHMARK SUMMARY ====="
$record | Format-List
Write-Host "Saved files: $statsFile, $agentLog, $testLog, $summaryFile"
Write-Host 'Note: Peak RAM and CPU are maxima of samples, not exact instantaneous peaks.'
