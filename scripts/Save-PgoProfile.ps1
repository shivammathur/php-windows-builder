param (
    [Parameter(Mandatory)]
    [ValidateSet('initialized', 'default', 'cache-no-jit', 'cache')]
    [string] $Stage
)
$ErrorActionPreference = 'Stop'
$match = [regex]::Match((Get-Content Makefile -Raw), '(?m)^BUILD_DIR=(.+)$')
if (-not $match.Success) { throw 'Missing BUILD_DIR in Makefile' }
$buildDirectory = $match.Groups[1].Value.Trim()
$destination = Join-Path $env:RUNNER_TEMP "pgo-evidence/profiles/$Stage"
New-Item -ItemType Directory -Force $destination | Out-Null
$databases = @(Get-ChildItem $buildDirectory -File -Filter '*.pgd' |
    Where-Object { $_.Name -match '^php(?:8(?:ts)?|_opcache)\.pgd$' })
if (-not $databases.Count) { throw "No core PGO database in $buildDirectory" }
foreach ($database in $databases) {
    $output = & pgomgr /summary /unique $database.FullName 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content (Join-Path $destination ($database.Name + '.txt'))
    $exitCode | Set-Content (Join-Path $destination ($database.Name + '.exit-code.txt'))
    # A freshly cleared database may not have statistics to display yet.
    if ($exitCode -ne 0 -and $Stage -ne 'initialized') { throw "pgomgr failed for $($database.Name): $exitCode" }
}
# Keep the actual generated settings alongside each profile snapshot.
Get-ChildItem $env:TEMP -Filter 'ini*' -File | ForEach-Object {
    if ((Get-Content $_.FullName -Raw) -match 'pgo_run_error') {
        Copy-Item $_.FullName $destination
    }
}
Write-Host "Saved PGO profile statistics after $Stage."
