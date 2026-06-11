param(
    [string[]]$Model = @(
        "layout/2025_09_23",
        "text_recognition/2025_09_23",
        "table_recognition/2025_02_18",
        "text_detection/2025_05_07",
        "ocr_error_detection/2025_02_18"
    ),

    [string]$CacheRoot,
    [string]$BaseUrl = "https://models.datalab.to",
    [int]$Retry = 30,
    [int]$RetryDelay = 2,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "MarkerCommon.ps1")

function Get-DefaultModelCacheRoot {
    if ($env:DATALAB_MODEL_CACHE_DIR) {
        return $env:DATALAB_MODEL_CACHE_DIR
    }
    if ($env:MODEL_CACHE_DIR) {
        return $env:MODEL_CACHE_DIR
    }
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA "datalab\datalab\Cache\models")
    }
    return (Join-Path $HOME ".cache\datalab\models")
}

function Invoke-CurlDownload {
    param(
        [string]$Url,
        [string]$OutputPath,
        [switch]$Resume
    )

    $parent = Split-Path -Parent $OutputPath
    if (!(Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $curl) {
        throw "curl.exe not found; install curl or download Marker models manually."
    }

    $args = @("-sS", "-fL", "--retry", $Retry, "--retry-all-errors", "--retry-delay", $RetryDelay)
    if ($Resume) {
        $args += @("-C", "-")
    }
    $args += @($Url, "-o", $OutputPath)

    & $curl.Source @args
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed with exit code $LASTEXITCODE for $Url"
    }
}

function Test-ManifestComplete {
    param(
        [string]$ModelDir,
        [object]$Manifest
    )

    foreach ($file in $Manifest.files) {
        $path = Join-Path $ModelDir $file
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            return $false
        }
        if ((Get-Item -LiteralPath $path).Length -eq 0) {
            return $false
        }
    }
    return $true
}

if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Get-DefaultModelCacheRoot
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($modelName in $Model) {
    $modelName = $modelName.Trim("/")
    $remoteRoot = "$($BaseUrl.TrimEnd('/'))/$modelName"
    $modelDir = Join-Path $CacheRoot $modelName
    if (!(Test-Path -LiteralPath $modelDir -PathType Container)) {
        New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
    }

    $manifestPath = Join-Path $modelDir "manifest.json"
    if ($Force -or !(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Invoke-CurlDownload -Url "$remoteRoot/manifest.json" -OutputPath $manifestPath
    }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $downloaded = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[object]

    foreach ($file in $manifest.files) {
        $finalPath = Join-Path $modelDir $file
        if (!$Force -and (Test-Path -LiteralPath $finalPath -PathType Leaf) -and ((Get-Item -LiteralPath $finalPath).Length -gt 0)) {
            $skipped.Add([pscustomobject]@{
                file = $file
                bytes = (Get-Item -LiteralPath $finalPath).Length
            }) | Out-Null
            continue
        }

        $partPath = "$finalPath.part"
        Invoke-CurlDownload -Url "$remoteRoot/$file" -OutputPath $partPath -Resume
        Move-Item -Force -LiteralPath $partPath -Destination $finalPath
        $downloaded.Add([pscustomobject]@{
            file = $file
            bytes = (Get-Item -LiteralPath $finalPath).Length
        }) | Out-Null
    }

    $complete = Test-ManifestComplete -ModelDir $modelDir -Manifest $manifest
    if (!$complete) {
        throw "Model cache incomplete after download: $modelName"
    }

    $results.Add([pscustomobject]@{
        model = $modelName
        cache_dir = $modelDir
        complete = $complete
        downloaded = $downloaded
        skipped = $skipped
    }) | Out-Null
}

ConvertTo-PrettyJson ([pscustomobject]@{
    status = "models_ready"
    cache_root = $CacheRoot
    results = $results
})
