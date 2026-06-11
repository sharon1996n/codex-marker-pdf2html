$ErrorActionPreference = "Stop"

function Get-MarkerConfigPath {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME ".codex"
    }
    return (Join-Path $base "Codex\codex-marker-pdf2html\config.json")
}

function Read-MarkerConfig {
    $path = Get-MarkerConfigPath
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{}
    }
    try {
        return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{}
    }
}

function Get-ConfigValue {
    param(
        [object]$Config,
        [string]$Name
    )
    if ($null -eq $Config) {
        return $null
    }
    if ($Config.PSObject.Properties.Name -contains $Name) {
        return $Config.$Name
    }
    return $null
}

function Set-MarkerConfigValues {
    param([hashtable]$Values)

    $path = Get-MarkerConfigPath
    $dir = Split-Path -Parent $path
    if (!(Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $merged = @{}
    $existing = Read-MarkerConfig
    foreach ($prop in $existing.PSObject.Properties) {
        $merged[$prop.Name] = $prop.Value
    }
    foreach ($key in $Values.Keys) {
        $merged[$key] = $Values[$key]
    }

    $merged["updated_utc"] = (Get-Date).ToUniversalTime().ToString("o")
    $merged | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-DocumentsDefaultOutputRoot {
    $docs = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($docs)) {
        $docs = Join-Path $HOME "Documents"
    }
    return (Join-Path $docs "MarkerOutput")
}

function Get-VenvPythonPath {
    param([string]$VenvRoot)
    $windows = Join-Path $VenvRoot "Scripts\python.exe"
    $posix = Join-Path $VenvRoot "bin/python"
    if (Test-Path -LiteralPath $windows -PathType Leaf) {
        return $windows
    }
    if (Test-Path -LiteralPath $posix -PathType Leaf) {
        return $posix
    }
    return $null
}

function Get-CodexBundledPythonPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($homePath in @($HOME, $env:USERPROFILE)) {
        if ([string]::IsNullOrWhiteSpace($homePath)) {
            continue
        }
        $candidate = Join-Path $homePath ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
        if (!$paths.Contains($candidate)) {
            $paths.Add($candidate) | Out-Null
        }
    }
    return $paths
}

function Get-MarkerSingleFromPython {
    param([string]$PythonPath)
    if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        return $null
    }
    $dir = Split-Path -Parent $PythonPath
    $candidates = @(
        (Join-Path $dir "marker_single.exe"),
        (Join-Path $dir "marker_single.cmd"),
        (Join-Path $dir "marker_single")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Get-PythonFromMarkerSingle {
    param([string]$MarkerSingle)
    if ([string]::IsNullOrWhiteSpace($MarkerSingle)) {
        return $null
    }
    $dir = Split-Path -Parent $MarkerSingle
    $candidates = @(
        (Join-Path $dir "python.exe"),
        (Join-Path $dir "python")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Test-PythonCommand {
    param(
        [string]$Command,
        [string[]]$CommandArgs = @()
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $null
    }

    try {
        $output = & $Command @($CommandArgs + @("-c", "import sys; print(sys.executable)")) 2>&1
        if ($LASTEXITCODE -eq 0 -and $output) {
            return [pscustomobject]@{
                command = $Command
                args = $CommandArgs
                executable = ($output | Select-Object -First 1).ToString().Trim()
            }
        }
    }
    catch {
        return $null
    }
    return $null
}

function Test-PythonHasMarker {
    param([string]$PythonPath)

    if ([string]::IsNullOrWhiteSpace($PythonPath) -or !(Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $false
            version = $null
            reason = "Python executable not found"
        }
    }

    $code = "import importlib.metadata as m; print(m.version('marker-pdf'))"
    try {
        $output = & $PythonPath -c $code 2>&1
        if ($LASTEXITCODE -eq 0 -and $output) {
            return [pscustomobject]@{
                valid = $true
                version = ($output | Select-Object -First 1).ToString().Trim()
                reason = $null
            }
        }
        return [pscustomobject]@{
            valid = $false
            version = $null
            reason = ($output -join "`n")
        }
    }
    catch {
        return [pscustomobject]@{
            valid = $false
            version = $null
            reason = $_.Exception.Message
        }
    }
}

function Test-MarkerCandidate {
    param(
        [string]$Source,
        [string]$MarkerSingle,
        [string]$PythonPath
    )

    if ([string]::IsNullOrWhiteSpace($MarkerSingle) -or !(Test-Path -LiteralPath $MarkerSingle -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $false
            source = $Source
            marker_single = $MarkerSingle
            python = $PythonPath
            version = $null
            reason = "marker_single not found"
        }
    }

    if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        $PythonPath = Get-PythonFromMarkerSingle -MarkerSingle $MarkerSingle
    }

    $pythonCheck = Test-PythonHasMarker -PythonPath $PythonPath
    if ($pythonCheck.valid) {
        return [pscustomobject]@{
            valid = $true
            source = $Source
            marker_single = $MarkerSingle
            python = $PythonPath
            version = $pythonCheck.version
            reason = $null
        }
    }

    try {
        $help = & $MarkerSingle --help 2>&1 | Select-Object -First 8
        if ($LASTEXITCODE -eq 0 -and (($help -join "`n") -match "Convert a single PDF|Usage:")) {
            return [pscustomobject]@{
                valid = $true
                source = $Source
                marker_single = $MarkerSingle
                python = $PythonPath
                version = $null
                reason = $null
            }
        }
    }
    catch {
        # Continue to invalid result below.
    }

    return [pscustomobject]@{
        valid = $false
        source = $Source
        marker_single = $MarkerSingle
        python = $PythonPath
        version = $null
        reason = $pythonCheck.reason
    }
}

function Get-UsablePythonCommand {
    foreach ($pythonPath in Get-CodexBundledPythonPaths) {
        if (Test-Path -LiteralPath $pythonPath -PathType Leaf) {
            $result = Test-PythonCommand -Command $pythonPath
            if ($null -ne $result) {
                return $result
            }
        }
    }

    $commands = @("python", "python3", "py")
    foreach ($cmd in $commands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $found) {
            continue
        }
        $args = $(if ($cmd -eq "py") { @("-3") } else { @() })
        $result = Test-PythonCommand -Command $found.Source -CommandArgs $args
        if ($null -ne $result) {
            return $result
        }
    }
    return $null
}

function Get-NvidiaSmiCommand {
    $candidates = New-Object System.Collections.Generic.List[string]
    $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd -and ![string]::IsNullOrWhiteSpace($cmd.Source)) {
        $candidates.Add($cmd.Source) | Out-Null
    }

    if ($env:SystemRoot) {
        $candidates.Add((Join-Path $env:SystemRoot "System32\nvidia-smi.exe")) | Out-Null
    }
    $candidates.Add("C:\Windows\System32\nvidia-smi.exe") | Out-Null
    $candidates.Add("C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe") | Out-Null

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or $seen.ContainsKey($candidate)) {
            continue
        }
        $seen[$candidate] = $true
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Get-MarkerGpuStatus {
    param([string]$PythonPath)

    $status = [ordered]@{
        cuda_available = $false
        cuda_device_count = 0
        cuda_device_name = $null
        torch_version = $null
        torch_cuda_version = $null
        nvidia_smi_detected = $false
        nvidia_smi_name = $null
        nvidia_smi_driver_version = $null
        nvidia_smi_cuda_version = $null
        reason = $null
    }

    if (![string]::IsNullOrWhiteSpace($PythonPath) -and (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        $code = "import json, torch; available=bool(torch.cuda.is_available()); count=int(torch.cuda.device_count() if available else 0); name=torch.cuda.get_device_name(0) if available and count else None; print(json.dumps({'cuda_available': available, 'cuda_device_count': count, 'cuda_device_name': name, 'torch_version': torch.__version__, 'torch_cuda_version': torch.version.cuda, 'reason': None}))"
        try {
            $probeOutput = & $PythonPath -c $code 2>&1
            $jsonLine = $probeOutput | Where-Object { $_.ToString().TrimStart().StartsWith("{") } | Select-Object -Last 1
            if ($LASTEXITCODE -eq 0 -and $jsonLine) {
                $torch = $jsonLine | ConvertFrom-Json
                $status.cuda_available = [bool]$torch.cuda_available
                $status.cuda_device_count = [int]$torch.cuda_device_count
                $status.cuda_device_name = $torch.cuda_device_name
                $status.torch_version = $torch.torch_version
                $status.torch_cuda_version = $torch.torch_cuda_version
                $status.reason = $torch.reason
            }
            elseif ($probeOutput) {
                $status.reason = ($probeOutput | Select-Object -First 1).ToString()
            }
        }
        catch {
            $status.reason = $_.Exception.Message
        }
    }

    $nvidia = Get-NvidiaSmiCommand
    if ($null -ne $nvidia) {
        try {
            $gpuInfo = & $nvidia --query-gpu=name,driver_version --format=csv,noheader 2>$null | Select-Object -First 1
            if ($gpuInfo) {
                $parts = $gpuInfo.ToString().Split(",", 2)
                $status.nvidia_smi_detected = $true
                $status.nvidia_smi_name = $parts[0].Trim()
                if ($parts.Count -gt 1) {
                    $status.nvidia_smi_driver_version = $parts[1].Trim()
                }
            }

            $raw = & $nvidia 2>$null
            $cudaLine = $raw | Where-Object { $_ -match "CUDA Version:\s*([0-9.]+)" } | Select-Object -First 1
            if ($cudaLine -and $cudaLine.ToString() -match "CUDA Version:\s*([0-9.]+)") {
                $status.nvidia_smi_cuda_version = $Matches[1]
            }

            if (!$status.nvidia_smi_detected) {
                $gpuLine = $raw | Where-Object { $_ -match "^\|\s*\d+\s+(.+?)\s+(WDDM|TCC)\s+\|" } | Select-Object -First 1
                if ($gpuLine -and $gpuLine.ToString() -match "^\|\s*\d+\s+(.+?)\s+(WDDM|TCC)\s+\|") {
                    $status.nvidia_smi_detected = $true
                    $status.nvidia_smi_name = $Matches[1].Trim()
                }
            }
        }
        catch {
            # Ignore nvidia-smi probing errors.
        }
    }

    if (!$status.cuda_available -and $status.nvidia_smi_detected -and [string]::IsNullOrWhiteSpace($status.reason)) {
        $status.reason = "NVIDIA GPU detected, but PyTorch CUDA is unavailable. Install a CUDA-enabled torch wheel compatible with the driver."
    }

    return [pscustomobject]$status
}

function ConvertTo-PrettyJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 12)
}
