param([string] $Makefile = 'Makefile')
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $Makefile).Path
$content = [IO.File]::ReadAllText($path)
if ($content -notmatch '(?m)^PHP_ARCHITECTURE=x86\s*$') {
    Write-Host 'PGO memory reservation unchanged for non-x86 builds.'
    return
}
if ($content -match '/USEPROFILE|/LTCG:PGUPDATE') { throw 'Reservation limit must only apply to the instrumented build' }
if ($content -notmatch '/GENPROFILE|/LTCG:PGINSTRUMENT') { throw 'No PGO instrumentation flags found' }
# Bound each instrumented module's reserved address space. Preserve GENPROFILE's
# 64-bit counters, path tracking and exception tracking; do not use FASTGENPROFILE.
$profile = '/GENPROFILE:MEMMAX=268435456'
$content = $content -replace '/GENPROFILE(?![\w:])', $profile
$content = $content -replace '/LTCG:PGINSTRUMENT\b', "/LTCG $profile"
[IO.File]::WriteAllText($path, $content)
Write-Host 'Limited x86 PGO reservation to 256 MiB per instrumented module.'
