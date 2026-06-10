param(
    [string]$InstallRoot,
    [string]$Version = "1.10.2"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "MarkerCommon.ps1")

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME ".codex-tools"
    }
    $InstallRoot = Join-Path $base "Codex\tools\marker-pdf"
}

$venv = Join-Path $InstallRoot ".venv"
$python = Get-VenvPythonPath -VenvRoot $venv
$uv = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1

if (!(Test-Path -LiteralPath $InstallRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
}

if ($null -ne $uv) {
    if (!$python) {
        & $uv.Source venv $venv
        if ($LASTEXITCODE -ne 0) {
            throw "uv venv failed with exit code $LASTEXITCODE"
        }
        $python = Get-VenvPythonPath -VenvRoot $venv
    }
    & $uv.Source pip install --python $python "marker-pdf==$Version" psutil
    if ($LASTEXITCODE -ne 0) {
        throw "uv pip install failed with exit code $LASTEXITCODE"
    }
}
else {
    $py = Get-UsablePythonCommand
    if ($null -eq $py) {
        throw "No usable Python command found and uv is unavailable. Install Python 3.12+ or uv, then rerun."
    }
    if (!$python) {
        if ($py.args.Count -gt 0) {
            & $py.command @($py.args + @("-m", "venv", $venv))
        }
        else {
            & $py.command -m venv $venv
        }
        if ($LASTEXITCODE -ne 0) {
            throw "python -m venv failed with exit code $LASTEXITCODE"
        }
        $python = Get-VenvPythonPath -VenvRoot $venv
    }
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw "pip upgrade failed with exit code $LASTEXITCODE"
    }
    & $python -m pip install "marker-pdf==$Version" psutil
    if ($LASTEXITCODE -ne 0) {
        throw "pip install failed with exit code $LASTEXITCODE"
    }
}

$markerSingle = Get-MarkerSingleFromPython -PythonPath $python
$candidate = Test-MarkerCandidate -Source "install:$InstallRoot" -MarkerSingle $markerSingle -PythonPath $python
if (!$candidate.valid) {
    throw "Installed marker-pdf, but marker_single validation failed: $($candidate.reason)"
}

Set-MarkerConfigValues @{
    marker_single = $candidate.marker_single
    marker_python = $candidate.python
    marker_version = $candidate.version
    marker_source = $candidate.source
    last_installed_utc = (Get-Date).ToUniversalTime().ToString("o")
}

ConvertTo-PrettyJson ([pscustomobject]@{
    status = "installed"
    install_root = $InstallRoot
    marker_single = $candidate.marker_single
    marker_python = $candidate.python
    marker_version = $candidate.version
    config_path = Get-MarkerConfigPath
})
