param(
    [Parameter(Mandatory = $true)]
    [string]$HtmlPath,

    [string]$OutputHtmlPath,

    [string]$SourceLang = "en",

    [string]$TargetLang = "zh",

    [switch]$InPlace,

    [switch]$InstallIfMissing
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "TranslatorCommon.ps1")

if (!(Test-Path -LiteralPath $HtmlPath -PathType Leaf)) {
    throw "HTML path not found: $HtmlPath"
}

if ($InPlace -and ![string]::IsNullOrWhiteSpace($OutputHtmlPath)) {
    throw "Use either -InPlace or -OutputHtmlPath, not both."
}

$resolveOutput = & (Join-Path $scriptDir "resolve_translator.ps1") -SourceLang $SourceLang -TargetLang $TargetLang
if ($LASTEXITCODE -ne 0) {
    throw "Translator resolve failed with exit code $LASTEXITCODE"
}

$resolved = $resolveOutput | ConvertFrom-Json
if ($resolved.status -ne "found" -or !$resolved.language_pair_installed) {
    if ($InstallIfMissing) {
        & (Join-Path $scriptDir "install_translator.ps1") -SourceLang $SourceLang -TargetLang $TargetLang | Out-Host
        $resolveOutput = & (Join-Path $scriptDir "resolve_translator.ps1") -SourceLang $SourceLang -TargetLang $TargetLang -Refresh
        $resolved = $resolveOutput | ConvertFrom-Json
    }
    else {
        throw "TRANSLATOR_NOT_READY: Run install_translator.ps1 after user approval, or pass -InstallIfMissing. Required language pair: $SourceLang->$TargetLang."
    }
}

if ($resolved.status -ne "found" -or !$resolved.language_pair_installed) {
    throw "Translator is installed, but language pair is missing: $SourceLang->$TargetLang"
}

if ($InPlace) {
    $OutputHtmlPath = $HtmlPath
}

$args = @(
    (Join-Path $scriptDir "translate_marker_html.py"),
    "--html", $HtmlPath,
    "--source-lang", $SourceLang,
    "--target-lang", $TargetLang
)
if (![string]::IsNullOrWhiteSpace($OutputHtmlPath)) {
    $args += @("--output-html", $OutputHtmlPath)
}

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$output = & $resolved.python @args
$exit = $LASTEXITCODE
$timer.Stop()

if ($exit -ne 0) {
    throw "Translation failed with exit code $exit"
}

$result = ($output | Select-Object -Last 1) | ConvertFrom-Json
$summary = [pscustomobject]@{
    status = $result.status
    engine = $result.engine
    python = $resolved.python
    html = $result.html
    translation_json = $result.translation_json
    source_lang = $result.source_lang
    target_lang = $result.target_lang
    sentence_count = $result.sentence_count
    total_wall_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
}

Write-Host "TRANSLATION_SUMMARY_JSON:"
ConvertTo-PrettyJson $summary
