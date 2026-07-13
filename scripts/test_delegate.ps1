#!/usr/bin/env pwsh
# PowerShell port of scripts/test_delegate.sh (contract tests for delegate.ps1).
# The bash suite's stale-lock rename race test intercepts external `rm`/`mv`
# binaries; delegate.ps1 uses PowerShell cmdlets, so that test is not portable
# and is intentionally omitted.
$ErrorActionPreference = 'Stop'

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$RepoRoot = (& git rev-parse --show-toplevel).Trim()
$Target = Join-Path $RepoRoot 'scripts/delegate.ps1'
Assert (Test-Path $Target) "expected helper at $Target"

$TmpDir = Join-Path ([IO.Path]::GetTempPath()) "delegate-test-$PID-$(Get-Random)"
$TestRepo = Join-Path $TmpDir 'repo'
$Bin = Join-Path $TmpDir 'bin'
New-Item -ItemType Directory -Force -Path "$TestRepo/scripts", $Bin | Out-Null

try {
    git -C $TestRepo init -q
    Copy-Item $Target "$TestRepo/scripts/delegate.ps1"
    $Delegate = Join-Path $TestRepo 'scripts/delegate.ps1'

    # --- fake codex shim ------------------------------------------------------
    @'
@echo off
pwsh -NoProfile -File "%~dp0codex_shim.ps1" %*
exit /b %ERRORLEVEL%
'@ | Set-Content "$Bin/codex.cmd" -Encoding ascii

    @'
$model = ''
$resultPath = ''
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '-m' { $model = $args[++$i] }
        '--output-last-message' { $resultPath = $args[++$i] }
    }
}
Write-Output "model=$model"
if ($model -eq 'exit-7') { exit 7 }
if ($model -in @('hold', 'orphan-hold', 'hold-exit-7')) {
    Set-Content (Join-Path $env:DELEGATE_TEST_HOLD_DIR 'codex-pid') $PID
    Set-Content (Join-Path $env:DELEGATE_TEST_HOLD_DIR 'started') ''
    while (-not (Test-Path (Join-Path $env:DELEGATE_TEST_HOLD_DIR 'release'))) {
        Start-Sleep -Milliseconds 50
    }
    if ($model -eq 'hold-exit-7') { exit 7 }
    if ($model -eq 'orphan-hold') { exit 0 }
}
$stdin = [Console]::In.ReadToEnd()
Set-Content -LiteralPath $resultPath -Value $stdin -NoNewline
'@ | Set-Content "$Bin/codex_shim.ps1" -Encoding utf8

    $env:PATH = "$Bin;$env:PATH"

    $script:LastExit = $null
    function Run-Helper {
        param([string[]]$HelperArgs, [string]$StdinText)
        Push-Location $TestRepo
        try {
            if ($null -ne $StdinText) {
                $out = $StdinText | & pwsh -NoProfile -File $Delegate @HelperArgs 2>&1 | ForEach-Object { "$_" }
            } else {
                $out = & pwsh -NoProfile -File $Delegate @HelperArgs 2>&1 | ForEach-Object { "$_" }
            }
            $script:LastExit = $LASTEXITCODE
            return ($out -join "`n")
        } finally {
            Pop-Location
        }
    }

    function Start-HelperBackground {
        param([string[]]$HelperArgs, [string]$OutFile)
        return Start-Process pwsh `
            -ArgumentList (@('-NoProfile', '-File', $Delegate) + $HelperArgs) `
            -WorkingDirectory $TestRepo -PassThru -NoNewWindow `
            -RedirectStandardOutput $OutFile -RedirectStandardError "$OutFile.err"
    }

    function Wait-ForFile([string]$FilePath, [int]$TimeoutSec = 15) {
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while (-not (Test-Path -LiteralPath $FilePath)) {
            if ((Get-Date) -gt $deadline) { throw "timeout waiting for $FilePath" }
            Start-Sleep -Milliseconds 50
        }
    }

    function Get-DeadPid {
        $p = Start-Process cmd -ArgumentList '/c', 'exit 0' -PassThru -WindowStyle Hidden
        $p.WaitForExit()
        return $p.Id
    }

    $Today = Get-Date -Format 'yyyy-MM-dd'

    # --- 1. basic stdin run ---------------------------------------------------
    $Dir = Join-Path $TestRepo "agents/$Today-delegate-contract/luna-test"
    $RunOut = Run-Helper @('delegate-contract', 'luna-test', 'gpt-5.6-luna') 'stdin prompt'
    Assert ($script:LastExit -eq 0) "basic run exit code: $script:LastExit"
    Assert ((Get-Content "$Dir/input.md" -Raw).Trim() -eq 'stdin prompt') 'input.md content'
    Assert ((Get-Content "$Dir/result.md" -Raw).Trim() -eq 'stdin prompt') 'result.md content'
    Assert ((Get-Content "$Dir/output.md" -Raw).Trim() -eq 'model=gpt-5.6-luna') 'output.md content'
    foreach ($f in 'input.md', 'output.md', 'result.md') {
        Assert ($RunOut.Contains((Join-Path $Dir $f))) "stdout mentions $f"
    }

    # --- 2. refuse existing result.md ------------------------------------------
    $RefuseOut = Run-Helper @('delegate-contract', 'luna-test', 'gpt-5.6-luna') 'second prompt'
    Assert ($script:LastExit -eq 1) "overwrite refusal exit code: $script:LastExit"
    Assert ($RefuseOut.Contains('refusing to overwrite existing result.md')) 'overwrite refusal message'

    # --- 3. --force overwrites --------------------------------------------------
    Run-Helper @('--force', 'delegate-contract', 'luna-test', 'gpt-5.6-luna') 'forced prompt' | Out-Null
    Assert ($script:LastExit -eq 0) 'forced run exit code'
    Assert ((Get-Content "$Dir/result.md" -Raw).Trim() -eq 'forced prompt') 'forced result.md content'

    # --- 4. forced failing run truncates result.md and keeps exit code ---------
    $FfDir = Join-Path $TestRepo "agents/$Today-delegate-force-failure/luna-force-failure"
    Run-Helper @('delegate-force-failure', 'luna-force-failure', 'gpt-5.6-luna') 'successful prompt' | Out-Null
    Assert ((Get-Content "$FfDir/result.md" -Raw).Trim() -eq 'successful prompt') 'pre-failure result.md'
    Run-Helper @('--force', 'delegate-force-failure', 'luna-force-failure', 'exit-7') 'failing forced prompt' | Out-Null
    Assert ($script:LastExit -eq 7) "forced failure exit code: $script:LastExit"
    Assert (Test-Path "$FfDir/result.md") 'failed result.md exists'
    Assert ((Get-Item "$FfDir/result.md").Length -eq 0) 'failed result.md is empty'

    # --- 5. file input -----------------------------------------------------------
    Set-Content "$TmpDir/prompt.md" 'file prompt' -NoNewline
    Run-Helper @('delegate-file-input', 'luna-file', 'gpt-5.6-luna', "$TmpDir/prompt.md") | Out-Null
    Assert ($script:LastExit -eq 0) 'file input exit code'
    $FileInputPath = Join-Path $TestRepo "agents/$Today-delegate-file-input/luna-file/input.md"
    Assert ((Get-Content $FileInputPath -Raw).Trim() -eq 'file prompt') 'file input.md content'

    # --- 6. codex exit status preserved, all three files exist -------------------
    Run-Helper @('delegate-exit', 'luna-exit', 'exit-7') 'failing prompt' | Out-Null
    Assert ($script:LastExit -eq 7) "exit-7 preserved: $script:LastExit"
    $ExitDir = Join-Path $TestRepo "agents/$Today-delegate-exit/luna-exit"
    foreach ($f in 'input.md', 'output.md', 'result.md') {
        Assert (Test-Path "$ExitDir/$f") "exit-7 run created $f"
    }

    # --- 7. concurrent invocation refused ---------------------------------------
    $HoldDir = Join-Path $TmpDir 'hold'
    New-Item -ItemType Directory $HoldDir | Out-Null
    $env:DELEGATE_TEST_HOLD_DIR = $HoldDir
    Set-Content "$TmpDir/hold-prompt.md" 'hold prompt' -NoNewline
    $First = Start-HelperBackground @('delegate-concurrent', 'luna-concurrent', 'hold', "$TmpDir/hold-prompt.md") "$TmpDir/first.out"
    Wait-ForFile "$HoldDir/started"
    $SecondOut = Run-Helper @('delegate-concurrent', 'luna-concurrent', 'gpt-5.6-luna') 'second'
    Assert ($script:LastExit -eq 1) "concurrent refusal exit code: $script:LastExit"
    Assert ($SecondOut.Contains('another invocation is already writing audit files')) 'concurrent refusal message'
    Set-Content "$HoldDir/release" ''
    $First.WaitForExit()
    Assert ($First.ExitCode -eq 0) "held run exit code: $($First.ExitCode)"
    Assert (Test-Path (Join-Path $TestRepo "agents/$Today-delegate-concurrent/luna-concurrent/result.md")) 'held run result.md exists'

    # --- 8. stale lock (dead owner) is taken over --------------------------------
    $DeadPid = Get-DeadPid
    $StaleDir = Join-Path $TestRepo "agents/$Today-delegate-stale-lock/luna-stale-lock"
    New-Item -ItemType Directory -Force "$StaleDir/.lock" | Out-Null
    Set-Content "$StaleDir/.lock/pid" $DeadPid
    Run-Helper @('delegate-stale-lock', 'luna-stale-lock', 'gpt-5.6-luna') 'stale lock prompt' | Out-Null
    Assert ($script:LastExit -eq 0) "stale takeover exit code: $script:LastExit"
    Assert ((Get-Content "$StaleDir/result.md" -Raw).Trim() -eq 'stale lock prompt') 'stale takeover result.md'
    Assert (-not (Test-Path "$StaleDir/.lock")) 'stale lock cleaned up'

    # --- 9. dead owner with pending codex marker is refused ----------------------
    $PendingDir = Join-Path $TestRepo "agents/$Today-delegate-pending/luna-pending"
    New-Item -ItemType Directory -Force "$PendingDir/.lock" | Out-Null
    Set-Content "$PendingDir/.lock/pid" $DeadPid
    Set-Content "$PendingDir/.lock/codex_pid" 'pending'
    $PendingOut = Run-Helper @('delegate-pending', 'luna-pending', 'gpt-5.6-luna') 'must be refused'
    Assert ($script:LastExit -eq 1) "pending marker refusal exit code: $script:LastExit"
    Assert (Test-Path "$PendingDir/.lock") 'pending lock preserved'
    Assert (-not (Test-Path "$PendingDir/result.md")) 'pending run wrote no result.md'
    Assert ($PendingOut.Contains('another invocation is already writing audit files')) 'pending refusal message'

    # --- 10. lock with no pid file is refused ------------------------------------
    $NoPidDir = Join-Path $TestRepo "agents/$Today-delegate-missing-pid/luna-missing-pid"
    New-Item -ItemType Directory -Force "$NoPidDir/.lock" | Out-Null
    $NoPidOut = Run-Helper @('delegate-missing-pid', 'luna-missing-pid', 'gpt-5.6-luna') 'must be refused'
    Assert ($script:LastExit -eq 1) "missing-pid refusal exit code: $script:LastExit"
    Assert (Test-Path "$NoPidDir/.lock") 'missing-pid lock preserved'
    Assert ($NoPidOut.Contains('another invocation is already writing audit files')) 'missing-pid refusal message'

    # --- 11. live-owner lock is refused -------------------------------------------
    $LiveDir = Join-Path $TestRepo "agents/$Today-delegate-live-lock/luna-live-lock"
    New-Item -ItemType Directory -Force "$LiveDir/.lock" | Out-Null
    Set-Content "$LiveDir/.lock/pid" $PID
    $LiveOut = Run-Helper @('delegate-live-lock', 'luna-live-lock', 'gpt-5.6-luna') 'must be refused'
    Assert ($script:LastExit -eq 1) "live-owner refusal exit code: $script:LastExit"
    Assert ($LiveOut.Contains('another invocation is already writing audit files')) 'live-owner refusal message'
    Remove-Item "$LiveDir/.lock" -Recurse -Force

    # --- 12. orphaned codex child blocks a second writer --------------------------
    $OrphanHold = Join-Path $TmpDir 'orphan-hold'
    New-Item -ItemType Directory $OrphanHold | Out-Null
    $env:DELEGATE_TEST_HOLD_DIR = $OrphanHold
    $OrphanLock = Join-Path $TestRepo "agents/$Today-delegate-orphan/luna-orphan/.lock"
    Set-Content "$TmpDir/orphan-prompt.md" 'orphan prompt' -NoNewline
    $OrphanJob = Start-HelperBackground @('--force', 'delegate-orphan', 'luna-orphan', 'orphan-hold', "$TmpDir/orphan-prompt.md") "$TmpDir/orphan.out"
    Wait-ForFile "$OrphanHold/started"
    Wait-ForFile "$OrphanLock/codex_pid"
    $OrphanCodexPid = [int](Get-Content "$OrphanLock/codex_pid" -TotalCount 1)
    Stop-Process -Id $OrphanJob.Id -Force
    $OrphanJob.WaitForExit()
    Assert ($null -ne (Get-Process -Id $OrphanCodexPid -ErrorAction SilentlyContinue)) 'codex child survives wrapper kill'
    $OrphanOut = Run-Helper @('--force', 'delegate-orphan', 'luna-orphan', 'gpt-5.6-luna') 'second writer'
    Assert ($script:LastExit -eq 1) "orphan refusal exit code: $script:LastExit"
    Assert ($OrphanOut.Contains('another invocation is already writing audit files')) 'orphan refusal message'
    Set-Content "$OrphanHold/release" ''
    $deadline = (Get-Date).AddSeconds(15)
    while (Get-Process -Id $OrphanCodexPid -ErrorAction SilentlyContinue) {
        if ((Get-Date) -gt $deadline) { throw 'timeout waiting for orphaned codex to exit' }
        Start-Sleep -Milliseconds 50
    }

    # --- 13. held run propagates late exit code and cleans lock -------------------
    $WaitHold = Join-Path $TmpDir 'wait-hold'
    New-Item -ItemType Directory $WaitHold | Out-Null
    $env:DELEGATE_TEST_HOLD_DIR = $WaitHold
    $WaitLock = Join-Path $TestRepo "agents/$Today-delegate-wait-status/luna-wait/.lock"
    Set-Content "$TmpDir/wait-prompt.md" 'wait status prompt' -NoNewline
    $WaitJob = Start-HelperBackground @('delegate-wait-status', 'luna-wait', 'hold-exit-7', "$TmpDir/wait-prompt.md") "$TmpDir/wait.out"
    Wait-ForFile "$WaitHold/started"
    Wait-ForFile "$WaitLock/codex_pid"
    $WaitCodexPid = (Get-Content "$WaitLock/codex_pid" -TotalCount 1)
    Assert ($WaitCodexPid -match '^[0-9]+$') 'held lock codex_pid is numeric'
    Assert ($null -ne (Get-Process -Id ([int]$WaitCodexPid) -ErrorAction SilentlyContinue)) 'held lock codex_pid is alive'
    Set-Content "$WaitHold/release" ''
    $WaitJob.WaitForExit()
    Assert ($WaitJob.ExitCode -eq 7) "held run exit code: $($WaitJob.ExitCode)"
    Assert (-not (Test-Path $WaitLock)) 'held run cleaned lock'

    # --- 14. invalid arguments fail ------------------------------------------------
    Run-Helper @('invalid') | Out-Null
    Assert ($script:LastExit -eq 2) "invalid args exit code: $script:LastExit"

    Write-Output 'delegate.ps1 contract tests passed'
} finally {
    Remove-Item Env:\DELEGATE_TEST_HOLD_DIR -ErrorAction SilentlyContinue
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
