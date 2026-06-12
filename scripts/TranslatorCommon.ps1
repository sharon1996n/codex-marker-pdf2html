$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "MarkerCommon.ps1")

function Get-TranslatorInstallRoot {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME ".codex"
    }
    return (Join-Path $base "Codex\tools\argos-translate\.venv")
}

function Get-TranslatorPythonPath {
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

function Test-ArgosTranslator {
    param(
        [string]$PythonPath,
        [string]$SourceLang = "en",
        [string]$TargetLang = "zh"
    )

    if ([string]::IsNullOrWhiteSpace($PythonPath) -or !(Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $false
            python = $PythonPath
            argos_version = $null
            language_pair_installed = $false
            reason = "Python executable not found"
        }
    }

    $code = @'
import json
import sys

source = sys.argv[1]
target = sys.argv[2]
try:
    import importlib.metadata as metadata
    import argostranslate.translate as translate
    version = metadata.version('argostranslate')
    installed = translate.get_installed_languages()
    from_lang = next((lang for lang in installed if lang.code == source), None)
    to_lang = next((lang for lang in installed if lang.code == target), None)
    pair = bool(from_lang and to_lang and from_lang.get_translation(to_lang))
    print(json.dumps({
        'valid': True,
        'argos_version': version,
        'language_pair_installed': pair,
        'installed_languages': [lang.code for lang in installed],
    }, ensure_ascii=True))
except Exception as exc:
    print(json.dumps({
        'valid': False,
        'argos_version': None,
        'language_pair_installed': False,
        'reason': str(exc),
    }, ensure_ascii=True))
'@

    try {
        $output = & $PythonPath -c $code $SourceLang $TargetLang 2>&1
        if ($output) {
            $result = ($output | Select-Object -First 1) | ConvertFrom-Json
            return [pscustomobject]@{
                valid = [bool]$result.valid
                python = $PythonPath
                argos_version = $result.argos_version
                language_pair_installed = [bool]$result.language_pair_installed
                installed_languages = $result.installed_languages
                reason = $result.reason
            }
        }
    }
    catch {
        return [pscustomobject]@{
            valid = $false
            python = $PythonPath
            argos_version = $null
            language_pair_installed = $false
            installed_languages = @()
            reason = $_.Exception.Message
        }
    }

    return [pscustomobject]@{
        valid = $false
        python = $PythonPath
        argos_version = $null
        language_pair_installed = $false
        installed_languages = @()
        reason = ($output -join "`n")
    }
}

function Get-TranslatorCandidates {
    $candidates = New-Object System.Collections.Generic.List[object]

    if (![string]::IsNullOrWhiteSpace($env:ARGOS_TRANSLATE_PYTHON)) {
        $candidates.Add([pscustomobject]@{
            source = "ARGOS_TRANSLATE_PYTHON"
            python = $env:ARGOS_TRANSLATE_PYTHON
        }) | Out-Null
    }

    $config = Read-MarkerConfig
    $configuredPython = Get-ConfigValue -Config $config -Name "translator_python"
    if ($configuredPython) {
        $candidates.Add([pscustomobject]@{
            source = "config"
            python = $configuredPython
        }) | Out-Null
    }

    $toolPython = Get-TranslatorPythonPath -VenvRoot (Get-TranslatorInstallRoot)
    if ($toolPython) {
        $candidates.Add([pscustomobject]@{
            source = "codex_tool_install"
            python = $toolPython
        }) | Out-Null
    }

    return $candidates
}
