param(
    [Parameter(Mandatory)][string]$BuildRuns,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch
)
$ErrorActionPreference = 'Stop'
$found = @()
foreach ($runId in $BuildRuns.Split(',')) {
    $response = gh api "repos/winlibs/winlib-builder/actions/runs/$runId/artifacts"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect run $runId" }
    $artifacts = ($response | ConvertFrom-Json).artifacts
    foreach ($artifact in $artifacts) {
        if ($artifact.name -eq "libheif-1.23.4-vs18-$Arch") {
            if ($artifact.expired) { throw 'libheif artifact expired' }
            $found += [pscustomobject]@{ Run = $runId; Name = $artifact.name }
        }
    }
}
if ($found.Count -ne 1) { throw "Expected one matching libheif build, found $($found.Count)" }
$deps = Join-Path $env:RUNNER_TEMP "security-libheif-$Arch"
gh run download $found[0].Run -R winlibs/winlib-builder -n $found[0].Name -D $deps
if ($LASTEXITCODE -ne 0) { throw 'Could not download libheif' }
& cl /nologo /W4 /MD "/I$deps\include" "$PSScriptRoot\libheif.c" /link "/LIBPATH:$deps\lib" heif.lib /OUT:security-libheif.exe
if ($LASTEXITCODE -ne 0) { throw 'libheif validation compilation failed' }
$env:PATH = "$deps\bin;$env:PATH"
& .\security-libheif.exe
if ($LASTEXITCODE -ne 0) { throw 'libheif codec roundtrip validation failed' }
