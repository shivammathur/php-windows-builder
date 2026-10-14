$ErrorActionPreference = 'Stop'
$evidence = Join-Path $env:GITHUB_WORKSPACE 'toolset-evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$env:BUILD_OUTCOME | Set-Content "$evidence/build-outcome.txt"
$files = @('Makefile','Makefile.objects','config.nice.bat','config.ts.bat','config.nts.bat','main/config.w32.h')
foreach ($file in $files) { if (Test-Path $file) { Copy-Item $file $evidence } }
Get-ChildItem $env:TEMP -Filter 'dd_*.log' -File | Copy-Item -Destination $evidence
$obj = Join-Path (Split-Path $env:GITHUB_WORKSPACE -Parent) 'obj'
if (Test-Path $obj) {
    @(Get-ChildItem $obj -Filter '*.pgd' -Recurse -File | Get-FileHash) |
        ConvertTo-Json -Depth 5 | Set-Content "$evidence/profile-hashes.json"
    [string[]]$stateFiles = if ($env:BUILD_OUTCOME -eq 'success') {
        @(Get-ChildItem $obj -Filter '*.pgd' -Recurse -File | ForEach-Object FullName)
    } else { @($obj) }
    if ($stateFiles.Count) {
        & 7z a -t7z -mx=1 "$evidence/build-state.7z" @stateFiles
        if ($LASTEXITCODE) { throw 'Could not preserve build state' }
    }
}
if (Test-Path artifacts) {
    @(Get-ChildItem artifacts -File | Get-FileHash) |
        ConvertTo-Json -Depth 5 | Set-Content "$evidence/artifact-hashes.json"
}
