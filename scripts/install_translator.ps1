param(
    [string]$SourceLang = "en",
    [string]$TargetLang = "zh",
    [switch]$SkipLanguagePackage
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "TranslatorCommon.ps1")

function Get-BasePython {
    $commands = @(
        @{ command = "python"; args = @() },
        @{ command = "py"; args = @("-3") }
    )

    foreach ($candidate in $commands) {
        $result = Test-PythonCommand -Command $candidate.command -CommandArgs $candidate.args
        if ($null -ne $result) {
            return $result
        }
    }

    foreach ($pythonPath in Get-CodexBundledPythonPaths) {
        if (Test-Path -LiteralPath $pythonPath -PathType Leaf) {
            $result = Test-PythonCommand -Command $pythonPath
            if ($null -ne $result) {
                return $result
            }
        }
    }

    return $null
}

$installRoot = Get-TranslatorInstallRoot
$pythonPath = Get-TranslatorPythonPath -VenvRoot $installRoot

if ([string]::IsNullOrWhiteSpace($pythonPath)) {
    $basePython = Get-BasePython
    if ($null -eq $basePython) {
        throw "No usable Python found. Install Python or make Codex bundled Python available."
    }

    $parent = Split-Path -Parent $installRoot
    if (!(Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    & $basePython.command @($basePython.args + @("-m", "venv", $installRoot))
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create translator virtual environment at $installRoot"
    }
    $pythonPath = Get-TranslatorPythonPath -VenvRoot $installRoot
}

if ([string]::IsNullOrWhiteSpace($pythonPath)) {
    throw "Translator Python was not found after venv creation: $installRoot"
}

& $pythonPath -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upgrade pip in translator environment."
}

& $pythonPath -m pip install "argostranslate==1.9.6" "beautifulsoup4==4.12.3"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install argostranslate and beautifulsoup4."
}

if (!$SkipLanguagePackage) {
    $code = @"
import json
import sys
from argostranslate import package, translate

source = sys.argv[1]
target = sys.argv[2]

package.update_package_index()
installed = translate.get_installed_languages()
from_lang = next((lang for lang in installed if lang.code == source), None)
to_lang = next((lang for lang in installed if lang.code == target), None)
if from_lang and to_lang and from_lang.get_translation(to_lang):
    print(json.dumps({"status": "already_installed"}, ensure_ascii=True))
    raise SystemExit(0)

available = package.get_available_packages()
match = next((pkg for pkg in available if pkg.from_code == source and pkg.to_code == target), None)
if match is None:
    raise SystemExit(f"No Argos package found for {source}->{target}")
path = match.download()
package.install_from_path(path)
print(json.dumps({"status": "installed", "package": str(path)}, ensure_ascii=True))
"@
    & $pythonPath -c $code $SourceLang $TargetLang
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Argos language package for $SourceLang->$TargetLang."
    }
}

$check = Test-ArgosTranslator -PythonPath $pythonPath -SourceLang $SourceLang -TargetLang $TargetLang
Set-MarkerConfigValues @{
    translator_python = $pythonPath
    translator_engine = "argos-translate"
}

$summary = [pscustomobject]@{
    status = "installed"
    engine = "argos-translate"
    python = $pythonPath
    install_root = $installRoot
    argos_version = $check.argos_version
    source_lang = $SourceLang
    target_lang = $TargetLang
    language_pair_installed = $check.language_pair_installed
    skipped_language_package = [bool]$SkipLanguagePackage
}

Write-Host "TRANSLATOR_INSTALL_SUMMARY_JSON:"
ConvertTo-PrettyJson $summary
