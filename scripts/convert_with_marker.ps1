param(
    [Parameter(Mandatory = $true)]
    [string[]]$InputPath,

    [ValidateSet("html", "markdown", "json", "chunks")]
    [string]$Format = "html",

    [string]$OutputRoot,

    [string]$PageRange,

    [switch]$SetDefaultOutputRoot,

    [switch]$UseDocumentsDefault,

    [switch]$InstallIfMissing,

    [switch]$ForceCpu,

    [switch]$EnableMultiprocessing,

    [switch]$DisableImageExtraction,

    [string[]]$ExtraMarkerArgs
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "MarkerCommon.ps1")

$config = Read-MarkerConfig
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $configuredOutputRoot = Get-ConfigValue -Config $config -Name "output_root"
    if ($configuredOutputRoot) {
        $OutputRoot = $configuredOutputRoot
    }
    elseif ($UseDocumentsDefault) {
        $OutputRoot = Get-DocumentsDefaultOutputRoot
        Set-MarkerConfigValues @{ output_root = $OutputRoot }
    }
    else {
        throw "DEFAULT_OUTPUT_ROOT_NOT_CONFIGURED: Ask the user whether to use '$((Get-DocumentsDefaultOutputRoot))' as the default output root, or pass -OutputRoot."
    }
}
elseif ($SetDefaultOutputRoot) {
    Set-MarkerConfigValues @{ output_root = $OutputRoot }
}

if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$resolveOutput = & (Join-Path $scriptDir "resolve_marker.ps1")
if ($LASTEXITCODE -ne 0) {
    if ($InstallIfMissing) {
        & (Join-Path $scriptDir "install_marker.ps1") | Out-Host
        $resolveOutput = & (Join-Path $scriptDir "resolve_marker.ps1") -Refresh
    }
    else {
        throw "Marker environment not found. Run install_marker.ps1 after user approval, or pass -InstallIfMissing."
    }
}

$resolved = $resolveOutput | ConvertFrom-Json
if ($resolved.status -ne "found") {
    throw "Marker environment not found."
}

$markerSingle = $resolved.marker_single
$markerPython = $resolved.marker_python

$gpu = Get-MarkerGpuStatus -PythonPath $markerPython
$oldTorchDevice = $env:TORCH_DEVICE
$oldCudaVisibleDevices = $env:CUDA_VISIBLE_DEVICES

if ($ForceCpu) {
    $env:TORCH_DEVICE = "cpu"
    $selectedDevice = "cpu"
}
elseif ($gpu.cuda_available) {
    $env:TORCH_DEVICE = "cuda"
    if ([string]::IsNullOrWhiteSpace($env:CUDA_VISIBLE_DEVICES)) {
        $env:CUDA_VISIBLE_DEVICES = "0"
    }
    $selectedDevice = "cuda"
}
else {
    $env:TORCH_DEVICE = "cpu"
    $selectedDevice = "cpu"
}

$files = New-Object System.Collections.Generic.List[string]
foreach ($path in $InputPath) {
    if (Test-Path -LiteralPath $path -PathType Container) {
        Get-ChildItem -LiteralPath $path -File -Filter "*.pdf" | ForEach-Object {
            $files.Add($_.FullName) | Out-Null
        }
    }
    elseif (Test-Path -LiteralPath $path -PathType Leaf) {
        $files.Add((Resolve-Path -LiteralPath $path).Path) | Out-Null
    }
    else {
        throw "Input path not found: $path"
    }
}

if ($files.Count -eq 0) {
    throw "No input files found."
}

$extensionByFormat = @{
    html = ".html"
    markdown = ".md"
    json = ".json"
    chunks = ".json"
}

$results = New-Object System.Collections.Generic.List[object]

try {
    foreach ($file in $files) {
        $args = New-Object System.Collections.Generic.List[string]
        $args.Add($file) | Out-Null
        $args.Add("--output_dir") | Out-Null
        $args.Add($OutputRoot) | Out-Null
        $args.Add("--output_format") | Out-Null
        $args.Add($Format) | Out-Null
        if (!$EnableMultiprocessing) {
            $args.Add("--disable_multiprocessing") | Out-Null
        }
        if ($DisableImageExtraction) {
            $args.Add("--disable_image_extraction") | Out-Null
        }
        if (![string]::IsNullOrWhiteSpace($PageRange)) {
            $args.Add("--page_range") | Out-Null
            $args.Add($PageRange) | Out-Null
        }
        if ($ExtraMarkerArgs) {
            foreach ($extra in $ExtraMarkerArgs) {
                $args.Add($extra) | Out-Null
            }
        }

        & $markerSingle @args
        if ($LASTEXITCODE -ne 0) {
            throw "marker_single failed for '$file' with exit code $LASTEXITCODE"
        }

        $stem = [IO.Path]::GetFileNameWithoutExtension($file)
        $docOutputDir = Join-Path $OutputRoot $stem
        $primary = Join-Path $docOutputDir ($stem + $extensionByFormat[$Format])
        if (!(Test-Path -LiteralPath $primary -PathType Leaf)) {
            $fallback = Get-ChildItem -LiteralPath $docOutputDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq $extensionByFormat[$Format] } |
                Select-Object -First 1
            if ($null -ne $fallback) {
                $primary = $fallback.FullName
            }
        }

        $meta = Join-Path $docOutputDir ($stem + "_meta.json")
        $images = @(Get-ChildItem -LiteralPath $docOutputDir -File -Include "*.jpg", "*.jpeg", "*.png", "*.webp" -ErrorAction SilentlyContinue)

        $results.Add([pscustomobject]@{
            input = $file
            format = $Format
            output_dir = $docOutputDir
            primary_output = $(if (Test-Path -LiteralPath $primary -PathType Leaf) { $primary } else { $null })
            meta_json = $(if (Test-Path -LiteralPath $meta -PathType Leaf) { $meta } else { $null })
            image_count = $images.Count
            selected_device = $selectedDevice
            cuda_available = $gpu.cuda_available
            cuda_device_name = $gpu.cuda_device_name
            nvidia_smi_detected = $gpu.nvidia_smi_detected
            nvidia_smi_name = $gpu.nvidia_smi_name
        }) | Out-Null
    }
}
finally {
    $env:TORCH_DEVICE = $oldTorchDevice
    $env:CUDA_VISIBLE_DEVICES = $oldCudaVisibleDevices
}

$summary = [pscustomobject]@{
    status = "converted"
    marker_single = $markerSingle
    marker_python = $markerPython
    output_root = $OutputRoot
    selected_device = $selectedDevice
    gpu = $gpu
    results = $results
}

Write-Host "MARKER_CONVERSION_SUMMARY_JSON:"
ConvertTo-PrettyJson $summary
