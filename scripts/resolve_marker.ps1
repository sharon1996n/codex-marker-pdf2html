param(
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "MarkerCommon.ps1")

$candidates = New-Object System.Collections.Generic.List[object]

function Add-Candidate {
    param(
        [string]$Source,
        [string]$MarkerSingle,
        [string]$PythonPath
    )
    if (![string]::IsNullOrWhiteSpace($MarkerSingle)) {
        $candidates.Add([pscustomobject]@{
            source = $Source
            marker_single = $MarkerSingle
            python = $PythonPath
        }) | Out-Null
    }
}

if ($env:MARKER_SINGLE_EXE) {
    Add-Candidate -Source "env:MARKER_SINGLE_EXE" -MarkerSingle $env:MARKER_SINGLE_EXE -PythonPath $env:MARKER_PYTHON
}

$config = Read-MarkerConfig
if (!$Refresh) {
    $cachedMarker = Get-ConfigValue -Config $config -Name "marker_single"
    $cachedPython = Get-ConfigValue -Config $config -Name "marker_python"
    if ($cachedMarker) {
        Add-Candidate -Source "config" -MarkerSingle $cachedMarker -PythonPath $cachedPython
    }
}

foreach ($name in @("marker_single", "marker_single.exe", "marker_single.cmd")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) {
        Add-Candidate -Source "PATH:$name" -MarkerSingle $cmd.Source -PythonPath (Get-PythonFromMarkerSingle -MarkerSingle $cmd.Source)
    }
}

$commonRoots = New-Object System.Collections.Generic.List[string]
$commonRoots.Add((Get-Location).Path) | Out-Null
if ($env:LOCALAPPDATA) {
    $commonRoots.Add((Join-Path $env:LOCALAPPDATA "Codex\tools")) | Out-Null
}
if ($HOME) {
    $commonRoots.Add((Join-Path $HOME ".codex-tools")) | Out-Null
    $commonRoots.Add((Join-Path $HOME "Desktop")) | Out-Null
    $commonRoots.Add((Join-Path $HOME "Documents")) | Out-Null
}

$venvNames = @(".marker-venv", ".venv", "venv", "env")
foreach ($root in $commonRoots) {
    if (!(Test-Path -LiteralPath $root -PathType Container)) {
        continue
    }

    foreach ($venvName in $venvNames) {
        $direct = Join-Path $root $venvName
        $python = Get-VenvPythonPath -VenvRoot $direct
        if ($python) {
            $marker = Get-MarkerSingleFromPython -PythonPath $python
            Add-Candidate -Source "venv:$direct" -MarkerSingle $marker -PythonPath $python
        }
    }

    if ($root -match "\\Desktop$|/Desktop$|\\Codex\\tools$|/Codex/tools$") {
        $children = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            foreach ($venvName in $venvNames) {
                $nested = Join-Path $child.FullName $venvName
                $python = Get-VenvPythonPath -VenvRoot $nested
                if ($python) {
                    $marker = Get-MarkerSingleFromPython -PythonPath $python
                    Add-Candidate -Source "venv:$nested" -MarkerSingle $marker -PythonPath $python
                }
            }
        }
    }
}

foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) {
        $check = Test-PythonHasMarker -PythonPath $cmd.Source
        if ($check.valid) {
            $marker = Get-MarkerSingleFromPython -PythonPath $cmd.Source
            Add-Candidate -Source "python:$name" -MarkerSingle $marker -PythonPath $cmd.Source
        }
    }
}

$checked = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($candidate in $candidates) {
    $key = "$($candidate.marker_single)|$($candidate.python)"
    if ($seen.ContainsKey($key)) {
        continue
    }
    $seen[$key] = $true

    $result = Test-MarkerCandidate -Source $candidate.source -MarkerSingle $candidate.marker_single -PythonPath $candidate.python
    $checked.Add($result) | Out-Null
    if ($result.valid) {
        Set-MarkerConfigValues @{
            marker_single = $result.marker_single
            marker_python = $result.python
            marker_version = $result.version
            marker_source = $result.source
            last_resolved_utc = (Get-Date).ToUniversalTime().ToString("o")
        }
        ConvertTo-PrettyJson ([pscustomobject]@{
            status = "found"
            marker_single = $result.marker_single
            marker_python = $result.python
            marker_version = $result.version
            marker_source = $result.source
            config_path = Get-MarkerConfigPath
            output_root = Get-ConfigValue -Config (Read-MarkerConfig) -Name "output_root"
            candidates_checked = $checked
        })
        exit 0
    }
}

ConvertTo-PrettyJson ([pscustomobject]@{
    status = "not_found"
    marker_single = $null
    marker_python = $null
    marker_version = $null
    config_path = Get-MarkerConfigPath
    documents_default_output_root = Get-DocumentsDefaultOutputRoot
    candidates_checked = $checked
    install_hint = "Run scripts/install_marker.ps1 after user approval."
})
exit 2
