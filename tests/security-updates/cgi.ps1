param([int]$Repetitions = 20)
$ErrorActionPreference = 'Stop'
$php = $env:TEST_PHP_EXECUTABLE
if (-not $php -or -not (Test-Path $php)) { throw 'PHP test binary is unavailable' }
$buildDirectory = Split-Path (Split-Path $php)
$testsDirectory = Join-Path $buildDirectory 'tests'
$env:TEST_PHP_CGI_EXECUTABLE = Join-Path (Split-Path $php) 'php-cgi.exe'
$originalJunit = $env:TEST_PHP_JUNIT
Push-Location $testsDirectory
try {
    for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
        $env:TEST_PHP_JUNIT = Join-Path $buildDirectory "cgi-recheck-$iteration.xml"
        & $php -n run-tests.php -p $php -n -q --offline --show-diff sapi/cgi/tests/011.phpt
        if ($LASTEXITCODE -ne 0) { throw "CGI header_remove test failed on repetition $iteration" }
        [xml]$report = Get-Content $env:TEST_PHP_JUNIT -Raw
        $cases = @($report.SelectNodes('//testcase'))
        if ($cases.Count -ne 1 -or $cases[0].SelectNodes('failure|error|skipped').Count -ne 0) {
            throw "CGI header_remove test did not pass on repetition $iteration"
        }
    }
    Write-Host "CGI header_remove passed all $Repetitions repetitions"
} finally {
    $env:TEST_PHP_JUNIT = $originalJunit
    Pop-Location
}
