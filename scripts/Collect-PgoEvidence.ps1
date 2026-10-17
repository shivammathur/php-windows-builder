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
if (Test-Path Makefile) { Copy-Item Makefile (Join-Path $destination 'Makefile.pgo') }
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

# Both compilation phases must instrument/optimize extension objects, not only core objects.
$compileChecks = @()
foreach ($sourceGroup in @('Zend\zend.c', 'ext\standard\', 'ext\opcache\ZendAccelerator.c', 'ext\opcache\jit\zend_jit.c')) {
    $commands = @($content -split "`n" | Where-Object {
        $_ -match 'cl\.exe' -and $_.Contains(" /c $sourceGroup")
    })
    $check = [ordered]@{
        source = $sourceGroup
        commands = $commands
        has_both_phases = $commands.Count -ge 2
        all_have_gl_o2 = @($commands | Where-Object { $_ -notmatch ' /GL\b' -or $_ -notmatch ' /O2\b' }).Count -eq 0
    }
    $compileChecks += [pscustomobject]$check
}
$compileChecks | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $destination 'static-pgo-compiler-checks.json')
if (@($compileChecks | Where-Object { -not $_.has_both_phases -or -not $_.all_have_gl_o2 }).Count) {
    throw 'Static-extension /GL /O2 verification failed'
}
$finalProfiles = @(Get-ChildItem (Join-Path $destination 'profiles/cache') -Filter '*.pgd.txt')
$jitEntries = @($finalProfiles | Select-String -Pattern '^\s*_?zend_jit\w+')
if (-not $jitEntries.Count) { throw 'Final PGO profile has no native JIT functions' }
$jitEntries.Line | Set-Content (Join-Path $destination 'jit-profile-functions.txt')
Write-Host "Verified /GL /O2 in both compilation phases and $($jitEntries.Count) native JIT profile entries."
