param([int]$Repetitions = 20)
$ErrorActionPreference = 'Stop'
$php = $env:TEST_PHP_EXECUTABLE
if (-not $php -or -not (Test-Path $php)) { throw 'PHP test binary is unavailable' }
$buildDirectory = Split-Path (Split-Path $php)
$testsDirectory = Join-Path $buildDirectory 'tests'
$phpIni = Join-Path (Split-Path $php) 'php-test.ini'
$artifactDirectory = (Get-Location).Path
$originalJunit = $env:TEST_PHP_JUNIT
Push-Location $testsDirectory
try {
    for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
        $env:TEST_PHP_JUNIT = Join-Path $artifactDirectory "soap-recheck-$iteration.xml"
        & $php -n run-tests.php -p $php -n -c $phpIni -q --offline --show-diff ext/soap/tests/bugs/cookie_parse_options_offset.phpt ext/soap/tests/bugs/bug51561.phpt
        if ($LASTEXITCODE -ne 0) { throw "SOAP startup regression test failed on repetition $iteration" }
        [xml]$report = Get-Content $env:TEST_PHP_JUNIT -Raw
        $cases = @($report.SelectNodes('//testcase'))
        if ($cases.Count -ne 2 -or $report.SelectNodes('//testcase/failure|//testcase/error|//testcase/skipped').Count -ne 0) {
            throw "SOAP startup regression test did not pass on repetition $iteration"
        }
    }
    Write-Host "SOAP startup regression passed all $Repetitions repetitions"
} finally {
    $env:TEST_PHP_JUNIT = $originalJunit
    Pop-Location
}
