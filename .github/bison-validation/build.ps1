param(
    [Parameter(Mandatory)][string] $Version,
    [Parameter(Mandatory)][ValidateSet('x64', 'x86')][string] $Arch,
    [Parameter(Mandatory)][ValidateSet('nts', 'ts')][string] $Ts
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Get-Location).Path
$evidence = Join-Path $repo 'bison-evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$env:TEMP = $env:TMP = Join-Path $env:RUNNER_TEMP 'sdk-bison'
New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
$sdkExpected = Get-Content -Raw (Join-Path $PSScriptRoot 'sdk.json') | ConvertFrom-Json
$fixture = @(Get-Content -Raw (Join-Path $PSScriptRoot 'sources.json') | ConvertFrom-Json | Where-Object version -EQ $Version)
if ($fixture.Count -ne 1) { throw "No unique source fixture for $Version" }
$fixture = $fixture[0]

function Get-Sha256([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-TokenMap([string] $Path) {
    $map = @{}
    foreach ($match in [regex]::Matches((Get-Content -Raw $Path), '(?m)^\s*(T_[A-Z0-9_]+)\s*=\s*(\d+)')) {
        $map[$match.Groups[1].Value] = [int] $match.Groups[2].Value
    }
    if ($map.Count -lt 140) { throw "Incomplete token map: $Path" }
    return $map
}
function Assert-TokenMap($Actual, $Expected) {
    if ($Actual.Count -ne $Expected.Count) { throw 'Token count differs' }
    foreach ($name in $Expected.Keys) {
        if (-not $Actual.ContainsKey($name) -or $Actual[$name] -ne $Expected[$name]) {
            throw "Token ID differs: $name"
        }
    }
}

# Exercise the normal full snapshot build and packaging without PGO training.
# These edits apply only to this disposable validation checkout.
$config = Join-Path $repo 'php/BuildPhp/config'
Get-ChildItem $config -Recurse -Filter "config.$Ts.bat" | ForEach-Object {
    $content = Get-Content -Raw $_.FullName
    Set-Content $_.FullName ($content.Replace('"--enable-pgi"', ''))
}
$task = @"
call buildconf.bat
if errorlevel 1 exit /b 1
call config.$Ts.bat
if errorlevel 1 exit /b 2
nmake
if errorlevel 1 exit /b 3
nmake snap
exit /b %ERRORLEVEL%
"@
Set-Content (Join-Path $repo "php/BuildPhp/runner/task-$Ts.bat") $task -Encoding ascii
Import-Module (Join-Path $repo 'php/BuildPhp') -Force
Invoke-PhpBuild -PhpVersion $Version -Arch $Arch -Ts $Ts

$buildRoots = @(Get-ChildItem $env:TEMP -Directory -Filter 'php-*' | Where-Object {
    Test-Path (Join-Path $_.FullName 'php-sdk/msys2/usr/bin/bison.exe')
})
if ($buildRoots.Count -ne 1) { throw 'Expected exactly one SDK build directory' }
$root = $buildRoots[0].FullName
$sdk = Join-Path $root 'php-sdk'
$sdkFiles = @{
    bison_sha256 = 'msys2/usr/bin/bison.exe'
    m4_sha256 = 'msys2/usr/bin/m4.exe'
    runtime_sha256 = 'msys2/usr/bin/msys-2.0.dll'
}
foreach ($name in $sdkFiles.Keys) {
    if ((Get-Sha256 (Join-Path $sdk $sdkFiles[$name])) -ne $sdkExpected.$name) {
        throw "Unexpected SDK dependency: $name"
    }
}
$bisonVersion = & (Join-Path $sdk 'msys2/usr/bin/bison.exe') --version
if ($LASTEXITCODE -ne 0 -or $bisonVersion[0] -ne 'bison (GNU Bison) 3.8.2') { throw 'Incorrect Bison version' }
$vs = if ($Version -match '^8\.[23]\.') { 'vs16' } else { 'vs17' }
$source = Join-Path $root "config/$vs/$Arch/php-$Version"
$parsers = @()
foreach ($grammar in $fixture.grammars) {
    $inputFile = Join-Path $source $grammar.path
    if ((Get-Sha256 $inputFile) -ne $grammar.sha256) { throw "Changed grammar: $($grammar.path)" }
    $parser = $grammar.path -replace '\.y$', '.c'
    if ($grammar.path -eq 'ext/json/json_parser.y') { $parser = 'ext/json/json_parser.tab.c' }
    $header = $parser -replace '\.c$', '.h'
    foreach ($path in $parser, $header) {
        if ((Get-Content -Raw (Join-Path $source $path)) -notmatch 'GNU Bison 3\.8\.2') { throw "Incorrect generated parser: $path" }
        $destination = Join-Path $evidence $path
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        Copy-Item (Join-Path $source $path) $destination
    }
    $parsers += [ordered]@{ grammar = $grammar.path; source_sha256 = $grammar.sha256; parser_sha256 = Get-Sha256 (Join-Path $source $parser); header_sha256 = Get-Sha256 (Join-Path $source $header) }
}

$officialZip = Join-Path $env:TEMP 'official-devel.zip'
Invoke-WebRequest $fixture.devel_pack.url -OutFile $officialZip
if ((Get-Sha256 $officialZip) -ne $fixture.devel_pack.sha256) { throw 'Official devel pack checksum differs' }
$official = Join-Path $env:TEMP 'official-devel'
Expand-Archive $officialZip $official
$officialHeaders = @(Get-ChildItem $official -Recurse -Filter zend_language_parser.h)
if ($officialHeaders.Count -ne 1) { throw 'Expected one official token header' }
$expected = Get-TokenMap $officialHeaders[0].FullName
Assert-TokenMap (Get-TokenMap (Join-Path $source 'Zend/zend_language_parser.h')) $expected
$expected | ConvertTo-Json | Set-Content (Join-Path $evidence 'expected-tokens.json')
Copy-Item $officialHeaders[0].FullName (Join-Path $evidence 'official-zend_language_parser.h')

$artifacts = Join-Path $repo 'artifacts'
Invoke-PhpSmokeTests -ArtifactsDirectory $artifacts -Arch $Arch -Ts $Ts
$suffix = if ($Ts -eq 'nts') { '-nts' } else { '' }
$runtimeZip = Join-Path $artifacts "php-$Version$suffix-Win32-$vs-$Arch.zip"
$develZip = Join-Path $artifacts "php-devel-pack-$Version$suffix-Win32-$vs-$Arch.zip"
$runtime = Join-Path $env:TEMP 'runtime-check'
$devel = Join-Path $env:TEMP 'devel-check'
Expand-Archive $runtimeZip $runtime
Expand-Archive $develZip $devel
$packHeaders = @(Get-ChildItem $devel -Recurse -Filter zend_language_parser.h)
if ($packHeaders.Count -ne 1) { throw 'Expected one generated devel pack token header' }
Assert-TokenMap (Get-TokenMap $packHeaders[0].FullName) $expected
Copy-Item $packHeaders[0].FullName (Join-Path $evidence 'devel-zend_language_parser.h')
$php = Join-Path $runtime 'php.exe'
$runtimeScript = Join-Path $PSScriptRoot 'runtime.php'
$tokenFile = Join-Path $evidence 'expected-tokens.json'
foreach ($opcache in $false, $true) {
    $arguments = @('-n')
    if ($opcache) { $arguments += @('-d', "zend_extension=$runtime/ext/php_opcache.dll", '-d', 'opcache.enable_cli=1', '-d', 'opcache.jit=0') }
    $result = & $php @arguments $runtimeScript $tokenFile
    if ($LASTEXITCODE -ne 0) { throw 'Runtime token/parser regression' }
    $probe = $result | ConvertFrom-Json
    $bits = if ($Arch -eq 'x64') { 64 } else { 32 }
    if ($probe.version -ne $Version -or $probe.bits -ne $bits -or $probe.zts -ne ($Ts -eq 'ts')) { throw 'Runtime identity mismatch' }
    $result | Set-Content (Join-Path $evidence "runtime-opcache-$opcache.json")
}
[ordered]@{
    php = $Version; arch = $Arch; ts = $Ts; sdk = $sdkExpected; bison = $bisonVersion[0]
    parsers = $parsers; token_count = $expected.Count; official = $fixture.devel_pack
    runtime_zip_sha256 = Get-Sha256 $runtimeZip; devel_zip_sha256 = Get-Sha256 $develZip
    php_exe_sha256 = Get-Sha256 $php; php_dll_sha256 = Get-Sha256 (Join-Path $runtime $(if ($Ts -eq 'ts') { 'php8ts.dll' } else { 'php8.dll' }))
    smoke = 'passed'; runtime_tokens = 'passed'; line_regression = 'passed'; opcache_and_nocache = 'passed'
} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $evidence 'report.json')
Write-Host "PHP $Version $Arch ${Ts}: full build, packaged runtime smoke tests and all $($expected.Count) official token IDs passed."
