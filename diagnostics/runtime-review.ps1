param([string]$Php,[string]$Ts,[string]$Opcache,[string]$Scope)
$ErrorActionPreference='Stop'
$workspace=(Get-Location).Path
$plan=Get-Content diagnostics/php-runs.json -Raw|ConvertFrom-Json|Where-Object php -eq $Php
$invoke='builder/php/BuildPhp/public/Invoke-PhpTests.ps1'
$code=[IO.File]::ReadAllText($invoke)
$anchor="        `$testTimeout = if (`$TestType -eq 'ext') { '300' } else { '120' }"
if(-not $code.Contains($anchor)){throw 'Diagnostic injection point changed'}
$instrument=@'
        $runner = Join-Path $buildDirectory 'tests/run-tests.php'
        $runnerCode = [IO.File]::ReadAllText($runner)
        $traceAnchor = '        $result = [$extDir, $extensions];'
        $traceCode = '        file_put_contents(getenv("GITHUB_WORKSPACE")."/extension-discovery-".getmypid().".jsonl", json_encode(["command"=>$php,"directory"=>$extDir,"extensions"=>$extensions])."\n", FILE_APPEND);'
        if (substr_count_placeholder) { throw 'Unexpected extension discovery code' }
        $runnerCode = $runnerCode.Replace($traceAnchor, "$traceCode`n$traceAnchor")
        [IO.File]::WriteAllText($runner, $runnerCode)
        Copy-Item "$buildDirectory/phpbin/php-test.ini" "$env:GITHUB_WORKSPACE/review-test.ini"
        Get-FileHash "$buildDirectory/phpbin/php.exe", "$buildDirectory/phpbin/ext/php_pdo_pgsql.dll", $runner | ConvertTo-Json | Set-Content "$env:GITHUB_WORKSPACE/review-input-hashes.json"
'@
$instrument=$instrument.Replace('substr_count_placeholder','[regex]::Matches($runnerCode, [regex]::Escape($traceAnchor)).Count -ne 1')
$code=$code.Replace($anchor,"$instrument`n$anchor").Replace('FAIL,BORK,WARN,LEAK','FAIL,BORK,WARN,LEAK,SKIP')
[IO.File]::WriteAllText($invoke,$code)
Import-Module ./builder/php/BuildPhp -Force
$testParameters=@{PhpVersion=$plan.version;Arch='arm64';Ts=$Ts;Opcache=$Opcache;TestType='ext';SourceRepository='shivammathur/php-src';SourceRef=$plan.source;FailOnError=$true}
if($Scope -eq 'postgres'){$testParameters.TestDirectories=@('ext/pdo_pgsql/tests','ext/pgsql/tests')}
try { Invoke-PhpTests @testParameters }
finally {
    Set-Location $workspace
    if(Test-Path "$env:TEMP/php-test-postgresql/server.log"){Copy-Item "$env:TEMP/php-test-postgresql/server.log" review-postgres-server.log}
    Get-ChildItem C:/ -Directory -Filter 'php-*' | ForEach-Object {
        if(Test-Path "$($_.FullName)/opcache_error.log"){Copy-Item "$($_.FullName)/opcache_error.log" "review-opcache-$($_.Name).log"}
    }
}
