param([string]$Mode)
. "$PSScriptRoot/common.ps1"
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/regressions" -ItemType Directory -Force
foreach ($variant in @('msvc','clang')) {
    $runtime = Expand-Runtime $variant
    $ini = Write-TestIni $runtime $Mode
    $env:TEST_PHP_EXECUTABLE = "$runtime/php.exe"
    $env:TEST_PHPDBG_EXECUTABLE = "$runtime/phpdbg.exe"
    $env:TEST_PHP_CGI_EXECUTABLE = "$runtime/php-cgi.exe"
    $env:TEST_PHP_JUNIT = "$out/$variant.xml"
    $env:NO_INTERACTION = '1'
    $env:REPORT_EXIT_STATUS = '1'
    $env:SKIP_IO_CAPTURE_TESTS = '1'
    Set-Location "$root/source"
    & $env:TEST_PHP_EXECUTABLE -n run-tests.php -p $env:TEST_PHP_EXECUTABLE -n -c $ini -q --offline --no-progress --show-diff --set-timeout 90 -j4 -g FAIL,BORK,WARN,LEAK tests Zend/tests sapi/cgi/tests sapi/cli/tests ext 2>&1 | Tee-Object "$out/$variant.log"
    $testExit = $LASTEXITCODE
    [ordered]@{variant=$variant; mode=$Mode;exitCode=$testExit;source=(& git rev-parse HEAD)} | ConvertTo-Json | Set-Content "$out/$variant-status.json"
    if (-not (Test-Path $env:TEST_PHP_JUNIT)) { throw "$variant failed to generate JUnit results" }
    $failures = Get-ChildItem -Path . -Recurse -File -Include '*.diff','*.out','*.exp','*.log' | Where-Object { $_.FullName -notmatch '\.git[\\/]' }
    $dest = New-Item "$out/$variant-failures" -ItemType Directory -Force
    foreach ($file in $failures) {
        $relative = [IO.Path]::GetRelativePath((Get-Location).Path, $file.FullName)
        $target = Join-Path $dest $relative
        New-Item ([IO.Path]::GetDirectoryName($target)) -ItemType Directory -Force | Out-Null
        Copy-Item $file.FullName $target
    }
    # Restore generated test files before the second compiler's run.
    git clean -fdx
    if ($LASTEXITCODE -ne 0) { throw 'Failed to clean isolated test source' }
}
