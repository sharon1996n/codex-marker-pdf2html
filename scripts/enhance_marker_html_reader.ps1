param(
  [Parameter(Mandatory = $true)]
  [string]$HtmlPath,

  [string]$OutputDir,

  [switch]$EnableTranslation,

  [string]$SourceLang = "en",

  [string]$TargetLang = "zh",

  [switch]$InstallTranslatorIfMissing
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillDir = Split-Path -Parent $scriptDir
$assetDir = Join-Path $skillDir "assets"
$readerCss = Join-Path $assetDir "reader.css"
$readerJs = Join-Path $assetDir "reader.js"

if (-not (Test-Path -LiteralPath $readerCss)) {
  throw "Missing reader asset: $readerCss"
}
if (-not (Test-Path -LiteralPath $readerJs)) {
  throw "Missing reader asset: $readerJs"
}

$sourceHtml = Get-Item -LiteralPath $HtmlPath
$sourceDir = $sourceHtml.Directory.FullName
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourceHtml.Name)

if (-not $OutputDir) {
  $OutputDir = Join-Path $sourceDir ($baseName + "_reader")
}

$resolvedSourceDir = [System.IO.Path]::GetFullPath($sourceDir)
$resolvedOutputDir = [System.IO.Path]::GetFullPath($OutputDir)

if ($resolvedSourceDir.TrimEnd('\') -eq $resolvedOutputDir.TrimEnd('\')) {
  throw "OutputDir must be different from the source HTML directory."
}

New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

Get-ChildItem -LiteralPath $resolvedSourceDir -Force | ForEach-Object {
  if ($_.Name -in @("reader.css", "reader.js")) {
    return
  }
  Copy-Item -LiteralPath $_.FullName -Destination $resolvedOutputDir -Recurse -Force
}

Copy-Item -LiteralPath $readerCss -Destination (Join-Path $resolvedOutputDir "reader.css") -Force
Copy-Item -LiteralPath $readerJs -Destination (Join-Path $resolvedOutputDir "reader.js") -Force

$targetHtml = Join-Path $resolvedOutputDir $sourceHtml.Name
$html = [System.IO.File]::ReadAllText($targetHtml)

if ($html -notmatch 'reader\.css') {
  if ($html -match '</head>') {
    $html = $html.Replace('</head>', '  <link rel="stylesheet" href="reader.css"/>' + [Environment]::NewLine + ' </head>')
  } else {
    $html = '<link rel="stylesheet" href="reader.css"/>' + [Environment]::NewLine + $html
  }
}

if ($html -notmatch 'reader\.js') {
  if ($html -match '</body>') {
    $html = $html.Replace('</body>', '  <script defer src="reader.js"></script>' + [Environment]::NewLine + ' </body>')
  } else {
    $html = $html + [Environment]::NewLine + '<script defer src="reader.js"></script>'
  }
}

[System.IO.File]::WriteAllText($targetHtml, $html, [System.Text.UTF8Encoding]::new($false))

$translationSummary = $null
if ($EnableTranslation) {
  $translateArgs = @(
    "-HtmlPath", $targetHtml,
    "-InPlace",
    "-SourceLang", $SourceLang,
    "-TargetLang", $TargetLang
  )
  if ($InstallTranslatorIfMissing) {
    $translateArgs += "-InstallIfMissing"
  }
  $translationOutput = & (Join-Path $scriptDir "translate_marker_html.ps1") @translateArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Translation enhancement failed with exit code $LASTEXITCODE"
  }
  $translationJson = Join-Path $resolvedOutputDir ("translations." + $TargetLang + ".json")
  if (Test-Path -LiteralPath $translationJson -PathType Leaf) {
    $translationPayload = Get-Content -LiteralPath $translationJson -Raw | ConvertFrom-Json
    $translationSummary = [pscustomobject]@{
      translation_json = $translationJson
      sentence_count = $translationPayload.count
    }
  }
}

$imageCount = (Get-ChildItem -LiteralPath $resolvedOutputDir -File -Include *.jpeg,*.jpg,*.png,*.webp,*.gif,*.svg -Recurse).Count

[pscustomobject]@{
  Html = $targetHtml
  OutputDir = $resolvedOutputDir
  Images = $imageCount
  Css = Test-Path -LiteralPath (Join-Path $resolvedOutputDir "reader.css")
  Js = Test-Path -LiteralPath (Join-Path $resolvedOutputDir "reader.js")
  TranslationEnabled = [bool]$EnableTranslation
  TranslationJson = $(if ($translationSummary) { $translationSummary.translation_json } else { $null })
  TranslationSentenceCount = $(if ($translationSummary) { $translationSummary.sentence_count } else { 0 })
}
