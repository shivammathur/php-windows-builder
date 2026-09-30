$ErrorActionPreference = 'Stop'
function Expand-Runtime([string]$Variant) {
    $artifactRoot = Join-Path $env:GITHUB_WORKSPACE "input/$Variant"
    $metadata = Get-Content "$artifactRoot/metadata.json" -Raw | ConvertFrom-Json
    $expectedSource = & git -C "$env:GITHUB_WORKSPACE/source" rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $metadata.source -ne $expectedSource) { throw "$Variant artifact source does not match the test source" }
    $zips = @(Get-ChildItem $artifactRoot -Filter '*.zip' -Recurse | Where-Object { $_.Name -match '^php-.+-(?:nts-)?Win32-(?:vs\d+|clang)-(?:x64|x86)\.zip$' -and $_.Name -notmatch '^php-(debug|devel|test)-pack-' })
    if ($zips.Count -ne 1) { throw "Expected one $Variant runtime; found $($zips.Count)" }
    $dest = Join-Path $env:GITHUB_WORKSPACE "runtime/$Variant"
    Expand-Archive $zips[0].FullName $dest -Force
    return $dest
}
function Write-TestIni([string]$Runtime, [string]$Mode) {
    $lines = @('memory_limit=-1', ('extension_dir="{0}"' -f (Join-Path $Runtime 'ext')))
    foreach ($dll in Get-ChildItem "$Runtime/ext/php_*.dll" | Sort-Object Name) {
        if ($dll.Name -in @('php_pdo_firebird.dll','php_snmp.dll','php_pdo_oci.dll') -or $dll.Name -like 'php_oci8*.dll') { continue }
        $key = if ($dll.Name -eq 'php_opcache.dll') { 'zend_extension' } else { 'extension' }
        $lines += "$key=$($dll.Name)"
    }
    $enabled = if ($Mode -eq 'nocache') { 0 } else { 1 }
    $lines += @("opcache.enable=$enabled", "opcache.enable_cli=$enabled", 'opcache.memory_consumption=256', 'opcache.interned_strings_buffer=16')
    if ($Mode -eq 'jit') { $lines += @('opcache.jit=tracing','opcache.jit_buffer_size=64M') } else { $lines += @('opcache.jit=disable','opcache.jit_buffer_size=0') }
    $ini = "$Runtime/$Mode.ini"
    $lines | Set-Content $ini
    return $ini
}
