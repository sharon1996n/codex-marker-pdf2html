param(
    [string]$InstallRoot,
    [string]$Version = "1.10.2",
    [string]$PythonPath,
    [switch]$SkipCudaTorch,
    [string]$TorchVersion = "2.7.1+cu118",
    [string]$TorchIndexUrl = "https://download.pytorch.org/whl/cu118"
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
$py = $null

if (![string]::IsNullOrWhiteSpace($PythonPath)) {
    if (!(Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        throw "PythonPath not found: $PythonPath"
    }
    $py = Test-PythonCommand -Command (Resolve-Path -LiteralPath $PythonPath).Path
    if ($null -eq $py) {
        throw "PythonPath is not usable: $PythonPath"
    }
}

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
    if ($null -eq $py) {
        $py = Get-UsablePythonCommand
    }
    if ($null -eq $py) {
        throw "No usable Python command found and uv is unavailable. Install Python 3.12+ or uv, or pass -PythonPath."
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

if (!$SkipCudaTorch) {
    $nvidia = Get-NvidiaSmiCommand
    $gpuBefore = Get-MarkerGpuStatus -PythonPath $python
    if ($null -ne $nvidia -and !$gpuBefore.cuda_available) {
        Write-Host "NVIDIA GPU detected but PyTorch CUDA is unavailable. Installing torch==$TorchVersion from $TorchIndexUrl ..."
        & $python -m pip install --force-reinstall "torch==$TorchVersion" --index-url $TorchIndexUrl
        if ($LASTEXITCODE -ne 0) {
            throw "CUDA torch install failed with exit code $LASTEXITCODE. Rerun with -SkipCudaTorch to keep CPU torch."
        }
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
    gpu = Get-MarkerGpuStatus -PythonPath $python
    last_installed_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$gpu = Get-MarkerGpuStatus -PythonPath $python
ConvertTo-PrettyJson ([pscustomobject]@{
    status = "installed"
    install_root = $InstallRoot
    marker_single = $candidate.marker_single
    marker_python = $candidate.python
    marker_version = $candidate.version
    gpu = $gpu
    config_path = Get-MarkerConfigPath
})
