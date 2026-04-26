param(
    [string]$RepoPath,
    [switch]$Json
)

function Get-CommandVersion {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $null
    }

    try {
        $versionOutput = & $Name --version 2>&1 | Select-Object -First 1
    } catch {
        $versionOutput = $null
    }

    return [pscustomobject]@{
        name = $Name
        path = $cmd.Source
        version = $versionOutput
    }
}

function Test-RepoCandidate {
    param([string]$PathValue)

    if (-not $PathValue) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $PathValue)) {
        return $null
    }

    $launch = Join-Path $PathValue "launch_scientist_bfts.py"
    $ideation = Join-Path $PathValue "ai_scientist\\perform_ideation_temp_free.py"
    if ((Test-Path -LiteralPath $launch) -and (Test-Path -LiteralPath $ideation)) {
        return (Resolve-Path -LiteralPath $PathValue).Path
    }
    return $null
}

$repoCandidates = @(
    $RepoPath,
    $env:AI_SCIENTIST_V2_PATH,
    "$HOME\\AI-Scientist-v2",
    "$HOME\\source\\AI-Scientist-v2",
    "$HOME\\projects\\AI-Scientist-v2",
    "$HOME\\Desktop\\AI-Scientist-v2"
) | Where-Object { $_ }

$resolvedRepo = $null
foreach ($candidate in $repoCandidates) {
    $resolved = Test-RepoCandidate -PathValue $candidate
    if ($resolved) {
        $resolvedRepo = $resolved
        break
    }
}

$pythonCandidates = @("python", "py") | ForEach-Object { Get-CommandVersion $_ } | Where-Object { $_ }

$wslInfo = [pscustomobject]@{
    installed = $false
}

$wslCmd = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslCmd) {
    $wslInfo.installed = $true
}

$gpuInfo = [pscustomobject]@{
    nvidiaSmi = $false
    summary = @()
}

$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $gpuInfo.nvidiaSmi = $true
    try {
        $gpuInfo.summary = @(& nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>&1)
    } catch {
        $gpuInfo.summary = @($_.Exception.Message)
    }
}

$envFlags = [ordered]@{
    OPENAI_API_KEY = [bool]$env:OPENAI_API_KEY
    GEMINI_API_KEY = [bool]$env:GEMINI_API_KEY
    S2_API_KEY = [bool]$env:S2_API_KEY
    AWS_ACCESS_KEY_ID = [bool]$env:AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = [bool]$env:AWS_SECRET_ACCESS_KEY
    AWS_REGION_NAME = [bool]$env:AWS_REGION_NAME
}

$mode = "windows-prep"
if ($wslInfo.installed -and $gpuInfo.nvidiaSmi -and $resolvedRepo) {
    $mode = "wsl"
}

$blockers = @()
if (-not $pythonCandidates) {
    $blockers += "Python was not found on the Windows host."
}
if (-not $resolvedRepo) {
    $blockers += "AI-Scientist-v2 repository path was not found in common Windows locations."
}
if (-not $envFlags.OPENAI_API_KEY -and -not $envFlags.GEMINI_API_KEY -and -not $envFlags.AWS_ACCESS_KEY_ID) {
    $blockers += "No supported model credentials were detected."
}
if (-not $gpuInfo.nvidiaSmi) {
    $blockers += "nvidia-smi was not found on the Windows host."
}

$result = [ordered]@{
    platform = "windows"
    mode = $mode
    repoPath = $resolvedRepo
    python = $pythonCandidates
    wsl = $wslInfo
    gpu = $gpuInfo
    env = $envFlags
    blockers = $blockers
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Output ("Mode: {0}" -f $result.mode)
Write-Output ("Repo: {0}" -f ($(if ($result.repoPath) { $result.repoPath } else { "not found" })))
if ($pythonCandidates) {
    Write-Output "Python:"
    foreach ($item in $pythonCandidates) {
        Write-Output ("  - {0}: {1}" -f $item.name, $item.version)
    }
} else {
    Write-Output "Python: not found"
}
Write-Output ("WSL installed: {0}" -f $wslInfo.installed)
Write-Output ("NVIDIA GPU visible: {0}" -f $gpuInfo.nvidiaSmi)
if ($gpuInfo.summary.Count -gt 0) {
    foreach ($line in $gpuInfo.summary) {
        Write-Output ("  {0}" -f $line)
    }
}
Write-Output "API keys:"
foreach ($key in $envFlags.Keys) {
    Write-Output ("  - {0}: {1}" -f $key, $envFlags[$key])
}
if ($blockers.Count -gt 0) {
    Write-Output "Blockers:"
    foreach ($item in $blockers) {
        Write-Output ("  - {0}" -f $item)
    }
} else {
    Write-Output "Blockers: none detected on the Windows host."
}
