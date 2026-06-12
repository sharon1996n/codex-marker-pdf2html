param(
    [string]$SourceLang = "en",
    [string]$TargetLang = "zh",
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "TranslatorCommon.ps1")

$checked = New-Object System.Collections.Generic.List[object]
$found = $null

foreach ($candidate in Get-TranslatorCandidates) {
    if ($Refresh -and $candidate.source -eq "config") {
        continue
    }
    $check = Test-ArgosTranslator -PythonPath $candidate.python -SourceLang $SourceLang -TargetLang $TargetLang
    $checked.Add([pscustomobject]@{
        source = $candidate.source
        python = $candidate.python
        valid = $check.valid
        argos_version = $check.argos_version
        language_pair_installed = $check.language_pair_installed
        installed_languages = $check.installed_languages
        reason = $check.reason
    }) | Out-Null

    if ($check.valid) {
        $found = [pscustomobject]@{
            status = "found"
            engine = "argos-translate"
            python = $candidate.python
            argos_version = $check.argos_version
            source_lang = $SourceLang
            target_lang = $TargetLang
            language_pair_installed = $check.language_pair_installed
            install_root = Get-TranslatorInstallRoot
            config_path = Get-MarkerConfigPath
            candidates_checked = $checked
        }
        Set-MarkerConfigValues @{
            translator_python = $candidate.python
            translator_engine = "argos-translate"
        }
        break
    }
}

if ($null -eq $found) {
    $found = [pscustomobject]@{
        status = "missing"
        engine = "argos-translate"
        python = $null
        argos_version = $null
        source_lang = $SourceLang
        target_lang = $TargetLang
        language_pair_installed = $false
        install_root = Get-TranslatorInstallRoot
        config_path = Get-MarkerConfigPath
        candidates_checked = $checked
    }
}

ConvertTo-PrettyJson $found
