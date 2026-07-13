#!/usr/bin/env pwsh
# PowerShell port of scripts/delegate.sh
# Usage: scripts/delegate.ps1 [-Force] <task-slug> <role> <model> [input-file]
$ErrorActionPreference = 'Stop'

function Show-Usage {
    [Console]::Error.WriteLine('Usage: scripts/delegate.ps1 [-f|--force|-Force] <task-slug> <role> <model> [input-file]')
}

function Fail-Usage([string]$Message) {
    [Console]::Error.WriteLine("error: $Message")
    Show-Usage
    exit 2
}

function Test-SafeComponent([string]$Value) {
    return $Value -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function Test-PidAlive([string]$ProcId) {
    if ($ProcId -notmatch '^[0-9]+$') { return $false }
    try {
        Get-Process -Id ([int]$ProcId) -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# --- Argument parsing -------------------------------------------------------
$Force = $false
$Positional = @()
$PassThrough = $false

foreach ($Arg in $args) {
    if ($PassThrough) { $Positional += $Arg; continue }
    switch -CaseSensitive ($Arg) {
        '--'      { $PassThrough = $true }
        '-f'      { $Force = $true }
        '--force' { $Force = $true }
        '-Force'  { $Force = $true }
        default {
            if ($Arg -like '-*') { Fail-Usage "unknown option: $Arg" }
            $Positional += $Arg
        }
    }
}

if ($Positional.Count -lt 3 -or $Positional.Count -gt 4) {
    Fail-Usage 'expected <task-slug> <role> <model> [input-file]'
}

$TaskSlug = $Positional[0]
$Role = $Positional[1]
$Model = $Positional[2]
$InputFile = if ($Positional.Count -eq 4) { $Positional[3] } else { $null }

if (-not (Test-SafeComponent $TaskSlug)) {
    Fail-Usage 'task-slug must use letters, numbers, dots, underscores, or hyphens'
}
if (-not (Test-SafeComponent $Role)) {
    Fail-Usage 'role must use letters, numbers, dots, underscores, or hyphens'
}
if ($Model -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$') {
    Fail-Usage 'model must use letters, numbers, dots, underscores, hyphens, or colons'
}
if ($InputFile -and -not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
    Fail-Usage "input-file is not a readable file: $InputFile"
}

# --- Paths -------------------------------------------------------------------
$RepoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $RepoRoot) {
    [Console]::Error.WriteLine('error: could not determine the Git repository root')
    exit 1
}
$RepoRoot = $RepoRoot.Trim()

# Directory layout: agents/<YYYY-MM-DD>-<NN>-<task-slug>/<NN>-<role>/
# NN is auto-allocated (per-date for tasks, per-task for roles); an existing
# directory with the same slug/role is reused so reruns and --force keep working.
function Resolve-NumberedDir([string]$Parent, [string]$Prefix, [string]$Slug) {
    $Max = 0
    $Found = $null
    if (Test-Path -LiteralPath $Parent) {
        foreach ($Dir in (Get-ChildItem -LiteralPath $Parent -Directory)) {
            if ($Dir.Name -cmatch ('^' + [regex]::Escape($Prefix) + '([0-9]+)-(.+)$')) {
                $Num = [int]$Matches[1]
                if ($Num -gt $Max) { $Max = $Num }
                if ($Matches[2] -ceq $Slug) { $Found = $Dir.Name }
            }
        }
    }
    if ($Found) { return $Found }
    return ('{0}{1:d2}-{2}' -f $Prefix, ($Max + 1), $Slug)
}

$AgentsRoot = Join-Path $RepoRoot 'agents'
$DateStr = Get-Date -Format 'yyyy-MM-dd'
$TaskDirName = Resolve-NumberedDir $AgentsRoot "$DateStr-" $TaskSlug
$RoleDirName = Resolve-NumberedDir (Join-Path $AgentsRoot $TaskDirName) '' $Role
$AgentDir = Join-Path $AgentsRoot (Join-Path $TaskDirName $RoleDirName)
$InputPath = Join-Path $AgentDir 'input.md'
$OutputPath = Join-Path $AgentDir 'output.md'
$ResultPath = Join-Path $AgentDir 'result.md'
$LockPath = Join-Path $AgentDir '.lock'

New-Item -ItemType Directory -Force -Path $AgentDir | Out-Null

# --- Lock (atomic directory creation, stale-owner takeover) ------------------
function Write-LockOwner {
    try {
        Set-Content -LiteralPath (Join-Path $LockPath 'pid') -Value $PID -Encoding ascii
        return $true
    } catch {
        try { Remove-Item -LiteralPath $LockPath -Force -ErrorAction Stop } catch {}
        return $false
    }
}

function Acquire-Lock {
    try {
        New-Item -ItemType Directory -Path $LockPath -ErrorAction Stop | Out-Null
        return (Write-LockOwner)
    } catch {}

    $PidFile = Join-Path $LockPath 'pid'
    $CodexPidFile = Join-Path $LockPath 'codex_pid'

    if (-not (Test-Path -LiteralPath $PidFile -PathType Leaf)) { return $false }
    try { $OwnerPid = (Get-Content -LiteralPath $PidFile -TotalCount 1) } catch { return $false }
    if ($OwnerPid -notmatch '^[0-9]+$') { return $false }

    $OwnerCodexPid = $null
    if (Test-Path -LiteralPath $CodexPidFile) {
        try { $OwnerCodexPid = (Get-Content -LiteralPath $CodexPidFile -TotalCount 1) } catch { return $false }
        if ($OwnerCodexPid -notmatch '^[0-9]+$') { return $false }
    }

    if ((Test-PidAlive $OwnerPid) -or ($OwnerCodexPid -and (Test-PidAlive $OwnerCodexPid))) {
        return $false
    }

    # Stale lock: rename it aside atomically, then recreate.
    $StalePath = "$LockPath.stale.$PID.$(Get-Random)"
    if (Test-Path -LiteralPath $StalePath) { return $false }
    try { Move-Item -LiteralPath $LockPath -Destination $StalePath -ErrorAction Stop } catch { return $false }

    try {
        New-Item -ItemType Directory -Path $LockPath -ErrorAction Stop | Out-Null
    } catch {
        try { Remove-Item -LiteralPath $StalePath -Recurse -Force } catch {}
        return $false
    }

    if (-not (Write-LockOwner)) {
        try { Remove-Item -LiteralPath $StalePath -Recurse -Force } catch {}
        return $false
    }

    try { Remove-Item -LiteralPath $StalePath -Recurse -Force } catch {}
    return $true
}

function Release-Lock {
    $PidFile = Join-Path $LockPath 'pid'
    try {
        if ((Test-Path -LiteralPath $PidFile) -and ((Get-Content -LiteralPath $PidFile -TotalCount 1) -eq "$PID")) {
            Remove-Item -LiteralPath (Join-Path $LockPath 'codex_pid') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $LockPath 'run.cmd') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

if (-not (Acquire-Lock)) {
    [Console]::Error.WriteLine("error: refusing to start; another invocation is already writing audit files: $AgentDir")
    exit 1
}

$CodexStatus = 1
try {
    if ((Test-Path -LiteralPath $ResultPath) -and -not $Force) {
        [Console]::Error.WriteLine("error: refusing to overwrite existing result.md: $ResultPath (pass --force to replace it)")
        exit 1
    }

    Set-Content -LiteralPath $ResultPath -Value '' -NoNewline

    if ($InputFile) {
        Copy-Item -LiteralPath $InputFile -Destination $InputPath -Force
    } else {
        # Read the prompt from stdin, like `cat > input.md`.
        $StdinText = [Console]::In.ReadToEnd()
        Set-Content -LiteralPath $InputPath -Value $StdinText -NoNewline
    }

    # Conservative marker: written before the child starts so a wrapper killed in
    # the start->pid-write gap leaves a non-numeric codex_pid, which takeover refuses.
    Set-Content -LiteralPath (Join-Path $LockPath 'codex_pid') -Value 'pending' -Encoding ascii

    # cmd.exe performs the stdin/stdout redirection so stdout and stderr are
    # merged into output.md in order, matching the bash version.
    $RunCmd = Join-Path $LockPath 'run.cmd'
    @(
        '@echo off'
        ('codex exec -m "{0}" --output-last-message "{1}" - < "{2}" > "{3}" 2>&1' -f $Model, $ResultPath, $InputPath, $OutputPath)
    ) | Set-Content -LiteralPath $RunCmd -Encoding ascii

    $Child = Start-Process -FilePath 'cmd.exe' -ArgumentList '/d', '/c', "`"$RunCmd`"" -NoNewWindow -PassThru
    Set-Content -LiteralPath (Join-Path $LockPath 'codex_pid') -Value $Child.Id -Encoding ascii

    $Child.WaitForExit()
    $CodexStatus = $Child.ExitCode
} finally {
    Release-Lock
}

if (-not (Test-Path -LiteralPath $ResultPath)) {
    Set-Content -LiteralPath $ResultPath -Value '' -NoNewline
}

Write-Output "input.md: $InputPath"
Write-Output "output.md: $OutputPath"
Write-Output "result.md: $ResultPath"

exit $CodexStatus
