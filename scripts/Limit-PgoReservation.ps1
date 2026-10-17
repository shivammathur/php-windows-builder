param([string] $Makefile = 'Makefile')
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $Makefile).Path
$content = [IO.File]::ReadAllText($path)
if ($content -notmatch '(?m)^PHP_ARCHITECTURE=x86\s*$') {
    Write-Host 'PGO memory reservation unchanged for non-x86 builds.'
    return
}
if ($content -match '/USEPROFILE|/LTCG:PGUPDATE') { throw 'Stack reservation limit must only apply to the instrumented build' }
if ($content -notmatch '/GENPROFILE|/LTCG:PGINSTRUMENT') { throw 'No PGO instrumentation flags found' }
# Helper threads inherit the executable's stack reservation. The normal 64 MiB
# stacks consume most of x86's 2 GiB address space during instrumented training.
# Keep profiling buffers and counters unchanged; the optimized build regenerates
# its normal Makefile and retains the original 64 MiB stack reservation.
foreach ($sapi in @('CGI', 'CLI', 'CLI_WIN32')) {
    if ($content -notmatch "(?m)^LDFLAGS_$sapi=.*?/stack:67108864\b") {
        throw "Missing expected 64 MiB stack reservation for $sapi"
    }
}
$content = $content -replace '/stack:67108864\b', '/stack:8388608'
[IO.File]::WriteAllText($path, $content)
Write-Host 'Limited instrumented x86 executable stack reservations to 8 MiB; profiling buffers unchanged.'
