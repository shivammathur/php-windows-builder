param(
    [Parameter(Mandatory)][string] $Arch,
    [Parameter(Mandatory)][string] $Ts
)
$ErrorActionPreference = 'Stop'
$archives = @(Get-ChildItem artifacts -Filter 'php-*.zip' | Where-Object {
    $match = [regex]::Match($_.Name, "^php-(.+?)(-nts)?-Win32-v[sc]\d+-$Arch\.zip$")
    $match.Success -and (($Ts -eq 'nts') -eq $match.Groups[2].Success)
})
if ($archives.Count -ne 1) { throw "Expected one PHP archive for $Arch/$Ts, found $($archives.Count)" }
$destination = Join-Path $env:RUNNER_TEMP "libzip-qa-$Arch-$Ts"
Expand-Archive -LiteralPath $archives[0].FullName -DestinationPath $destination
$php = Join-Path $destination 'php.exe'
$extensions = Join-Path $destination 'ext'
& $php -n -d "extension_dir=$extensions" -d extension=zip (Join-Path $PSScriptRoot 'check-libzip.php')
if ($LASTEXITCODE -ne 0) { throw 'PHP libzip round-trip tests failed' }
if (@(Get-ChildItem $destination -Recurse -File -Filter '*zstd*.dll').Count -ne 0) {
    throw 'Unexpected zstd DLL in the PHP distribution'
}
$dumpbin = & vswhere -latest -find 'VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe' | Select-Object -Last 1
if (-not $dumpbin) { throw 'dumpbin was not found' }
$imports = & $dumpbin /DEPENDENTS (Join-Path $extensions 'php_zip.dll')
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect php_zip.dll imports' }
$imports | Write-Host
if ($imports -match '(?i)(libzip|zstd|bz2|lzma|zlib).*\.dll') {
    throw 'php_zip.dll unexpectedly imports a compression DLL'
}
