$ErrorActionPreference = 'Stop'
function Expand-Runtime([string]$Variant) {
    $artifactRoot = Join-Path $env:GITHUB_WORKSPACE "input/$Variant"
    $metadata = Get-Content "$artifactRoot/metadata.json" -Raw | ConvertFrom-Json
    $expectedSource = & git -C "$env:GITHUB_WORKSPACE/source" rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify test source' }
    if ($metadata.source -ne $expectedSource) {
        if (-not $env:REUSE_SOURCE_REF -or $metadata.source -ne $env:REUSE_SOURCE_REF) { throw "$Variant artifact source does not match the test source" }
        # Reuse only MSVC baselines across the Clang-only TLS, Firebird
        # and guarded calling convention fixes. Clang artifacts must match the tested source.
        & git -C "$env:GITHUB_WORKSPACE/source" fetch --no-tags --depth=1 origin $metadata.source
        if ($LASTEXITCODE -ne 0) { throw 'Cannot fetch reused source for verification' }
        $changed = @(& git -C "$env:GITHUB_WORKSPACE/source" diff --name-only $metadata.source $expectedSource)
        if ($LASTEXITCODE -ne 0 -or $Variant -ne 'msvc' -or @($changed | Where-Object { $_ -notin @('ext/pdo_firebird/pdo_firebird_utils.h', 'TSRM/TSRM.h', 'win32/build/confutils.js', 'Zend/tests/vm_kind_tailcall_clang_windows.phpt') }).Count) { throw 'Reused artifact has unapproved source differences' }
    }
    $zips = @(Get-ChildItem $artifactRoot -Filter '*.zip' -Recurse | Where-Object { $_.Name -match '^php-.+-(?:nts-)?Win32-(?:vs\d+|clang)-(?:x64|x86)\.zip$' -and $_.Name -notmatch '^php-(debug|devel|test)-pack-' })
    if ($zips.Count -ne 1) { throw "Expected one $Variant runtime; found $($zips.Count)" }
    $dest = Join-Path $env:GITHUB_WORKSPACE "runtime/$Variant"
    Expand-Archive $zips[0].FullName $dest -Force
    return $dest
}
function Write-TestIni([string]$Runtime, [string]$Mode) {
    $lines = @('memory_limit=-1', ('extension_dir="{0}"' -f (Join-Path $Runtime 'ext')))
    foreach ($dll in Get-ChildItem "$Runtime/ext/php_*.dll" | Sort-Object Name) {
        if ($dll.Name -in @('php_dl_test.dll','php_pdo_oci.dll') -or $dll.Name -like 'php_oci8*.dll') { continue }
        if (-not $env:VALIDATION_EXTERNAL_DEPS -and $dll.Name -in @('php_pdo_firebird.dll','php_snmp.dll')) { continue }
        $key = if ($dll.Name -eq 'php_opcache.dll') { 'zend_extension' } else { 'extension' }
        $lines += "$key=$($dll.Name)"
    }
    $enabled = if ($Mode -eq 'nocache') { 0 } else { 1 }
    $lines += @('opcache.enable=1', "opcache.enable_cli=$enabled", 'opcache.memory_consumption=256', 'opcache.interned_strings_buffer=16')
    if ($Mode -eq 'jit') { $lines += @('opcache.jit=tracing','opcache.jit_buffer_size=64M') } else { $lines += @('opcache.jit=disable','opcache.jit_buffer_size=0') }
    $ini = "$Runtime/$Mode.ini"
    $lines | Set-Content $ini
    return $ini
}
