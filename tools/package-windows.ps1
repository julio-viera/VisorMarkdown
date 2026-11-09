param(
    [string]$BundleDir = "build\windows\x64\runner\Release",
    [string]$Iscc = "ISCC.exe"
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($BundleDir)) { $BundleDir = Join-Path $repoRoot $BundleDir }
$bundle = (Resolve-Path $BundleDir).Path
$metadata = Join-Path $bundle "data\flutter_assets\assets\app_info.json"
$info = Get-Content -Raw -Encoding UTF8 $metadata | ConvertFrom-Json
function Require-Text($value, [string]$field) {
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f\x7f]') {
        throw "Invalid or missing app_info.json field: $field"
    }
}
foreach ($field in @('name', 'version', 'buildDate', 'author', 'licenseName', 'licenseSpdx', 'licenseUrl', 'repository', 'issues', 'applicationId', 'binary')) {
    Require-Text $info.$field $field
}
if ($info.version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z') {
    throw "Invalid app_info.json field: version"
}
if (($info.buildNumber -isnot [int] -and $info.buildNumber -isnot [long]) -or $info.buildNumber -lt 1) {
    throw "Invalid or missing app_info.json field: buildNumber"
}
if ($info.binary -cnotmatch '\A[a-z0-9][a-z0-9-]+\z' -or
    $info.applicationId -cnotmatch '\A[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+\z') {
    throw "Invalid application identifier or binary name"
}
$languages = @('en', 'es', 'pt', 'de', 'fr', 'it')
foreach ($language in $languages) {
    Require-Text $info.descriptions.$language "descriptions.$language"
}
$version = $info.version
if (-not (Test-Path -LiteralPath (Join-Path $bundle "$($info.binary).exe") -PathType Leaf)) {
    throw "Build the Windows release first: flutter build windows --release"
}
$out = Join-Path $repoRoot "dist\$version\exe"
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($language in $languages) {
    $description = "# $($info.name) $($info.version)`n`n$($info.descriptions.$language)`n`n$($info.author) - [$($info.licenseName)]($($info.licenseUrl)) ($($info.licenseSpdx))`n`n$($info.repository)`n"
    Set-Content -Encoding UTF8 -Path (Join-Path $out "DESCRIPTION.$language.md") -Value $description
}
& $Iscc "/DAppName=$($info.name)" "/DAppVersion=$version" "/DAppAuthor=$($info.author)" "/DAppRepository=$($info.repository)" "/DAppId=$($info.applicationId)" "/DAppBinary=$($info.binary)" "/DAppDescription=$($info.descriptions.en)" "/DBundleDir=$bundle" "/DRepoRoot=$repoRoot" "/DOutputDir=$out" (Join-Path $PSScriptRoot "windows\installer.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
Write-Host "Installer output: $out"
