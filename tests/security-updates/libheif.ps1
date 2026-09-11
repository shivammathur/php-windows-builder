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

$series = (Invoke-WebRequest "https://downloads.php.net/~windows/php-sdk/deps/series/packages-8.6-vs18-$Arch-staging.txt").Content
$jpegName = @($series -split '[\r\n]+' | Where-Object { $_ -match '^libjpeg-turbo-' })
if ($jpegName.Count -ne 1 -or $jpegName[0] -ne "libjpeg-turbo-3.2.0-vs18-$Arch.zip") {
    throw 'The selected JPEG package changed; review libheif static compatibility'
}
$jpegRoot = Join-Path $env:RUNNER_TEMP "security-jpeg-$Arch"
$jpegZip = "$jpegRoot.zip"
Invoke-WebRequest "https://downloads.php.net/~windows/php-sdk/deps/vs18/$Arch/$($jpegName[0])" -OutFile $jpegZip
Expand-Archive $jpegZip -DestinationPath $jpegRoot -Force
& cl /nologo /W4 /MD /Zi /DLIBHEIF_STATIC_BUILD "/I$deps\include" "$PSScriptRoot\libheif.c" /link /DEBUG /WX "/LIBPATH:$deps\lib" "/LIBPATH:$jpegRoot\lib" heif_a.lib aom_a.lib dav1d_a.lib libjpeg_a.lib Advapi32.lib /OUT:security-libheif-static.exe
if ($LASTEXITCODE -ne 0) { throw 'Static libheif validation compilation failed' }
& .\security-libheif-static.exe
if ($LASTEXITCODE -ne 0) { throw 'Static libheif codec roundtrip validation failed' }
