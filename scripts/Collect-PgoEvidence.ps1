$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:RUNNER_TEMP 'pgo-evidence'
New-Item -ItemType Directory -Force $destination | Out-Null
$log = Join-Path $env:RUNNER_TEMP 'php-sdk-build.log'
if (Test-Path $log) {
    Copy-Item $log $destination
}
$resources = Join-Path $env:RUNNER_TEMP 'pgo-resources.jsonl'
if (Test-Path $resources) { Copy-Item $resources $destination }
$source = (git rev-parse HEAD).Trim()
[ordered]@{
    branch = $env:PGO_SOURCE_BRANCH
    source_sha = $source
    expected_source_sha = $env:PGO_SOURCE_SHA
    sdk_sha = $env:PGO_SDK_REF
    variant = $env:PGO_VARIANT
    runner = $env:RUNNER_NAME
    image = $env:ImageVersion
} | ConvertTo-Json | Set-Content (Join-Path $destination 'provenance.json')
if ($source -ne $env:PGO_SOURCE_SHA) { throw 'Source SHA mismatch' }

if ($env:PHP_SDK_TEST_DIR -and (Test-Path $env:PHP_SDK_TEST_DIR)) {
    $sdk = $env:PHP_SDK_TEST_DIR
    Get-ChildItem (Join-Path $sdk 'pgo') -Recurse -File |
        Where-Object { $_.Extension -eq '.log' -or $_.Name -eq 'phpsdk_pgo.json' } |
        ForEach-Object {
            $relative = [IO.Path]::GetRelativePath($sdk, $_.FullName)
            $target = Join-Path $destination $relative
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item $_.FullName $target
        }
}
Get-ChildItem $env:TEMP -Filter 'ini*' -File | ForEach-Object {
    if ((Get-Content $_.FullName -Raw) -match 'pgo_run_error') {
        Copy-Item $_.FullName (Join-Path $destination $_.Name)
    }
}
$obj = Join-Path (Split-Path (Get-Location).Path) 'obj'
if (Test-Path $obj) {
    Get-ChildItem $obj -Recurse -File -Filter 'pgo_run_error.log' | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $destination ('php-' + $_.Directory.Name + '-error.log'))
    }
}
if (-not (Test-Path $log)) { throw 'Missing build log' }
$content = Get-Content $log -Raw
$responses = @([regex]::Matches($content, '(?m)^\s*(\d+) received (\d+) times\s*$'))
$summary = @($responses | ForEach-Object {
    [pscustomobject]@{ status = [int]$_.Groups[1].Value; count = [int]$_.Groups[2].Value }
})
ConvertTo-Json -InputObject $summary | Set-Content (Join-Path $destination 'http-responses.json')
$summary | Format-Table | Out-String | Write-Host
$expectedPasses = if ($env:PGO_VARIANT -eq 'candidate') { 3 } else { 2 }
if ($responses.Count -ne $expectedPasses) { throw "Expected $expectedPasses HTTP training summaries" }
$stages = @('initialized', 'default', 'cache')
if ($env:PGO_VARIANT -eq 'candidate') { $stages += 'cache-no-jit' }
foreach ($stage in $stages) {
    if (-not @(Get-ChildItem (Join-Path $destination "profiles/$stage") -Filter '*.pgd.txt' -ErrorAction SilentlyContinue).Count) {
        throw "Missing profile statistics for $stage"
    }
}
if (@($summary | Where-Object { $_.status -ne 200 }).Count) {
    throw 'PGO training returned unsuccessful HTTP responses'
}
if ($content -match 'Not all HTTP responses|PHP Fatal error|Access violation|0xc0000005') {
    throw 'PGO log contains a crash or unsuccessful training warning'
}
$trainingErrors = @(Get-ChildItem $destination -File -Filter 'php-*-error.log' |
    Select-String -Pattern 'mysqli.*(?:HY000|Connection|connect)|PHP Fatal error|Access violation')
if ($trainingErrors.Count) {
    $trainingErrors | ForEach-Object { Write-Host $_.Line }
    throw 'PHP error logs show incomplete training despite the HTTP response status'
}
