param([string]$Php, [string]$Arch, [string]$Case)
$ErrorActionPreference = 'Stop'
$workspace = (Get-Location).Path
$plan = Get-Content diagnostics/php-runs.json -Raw | ConvertFrom-Json | Where-Object php -eq $Php
$sourceSha = (git -C source rev-parse HEAD).Trim()
if ($sourceSha -ne $plan.sourceSha) { throw 'Control test source changed' }
$bin = Join-Path $workspace 'phpbin'
if ($Arch -eq 'x64') {
    $releases = Get-Content diagnostics/windows-releases.json -Raw | ConvertFrom-Json
    $vs = if ($Php -eq '8.4') { 'vs17' } else { 'vs16' }
    $package = $releases.$Php."nts-$vs-x64".zip
    Invoke-WebRequest "https://downloads.php.net/~windows/releases/$($package.path)" -OutFile control.zip
    if ((Get-FileHash control.zip).Hash -ne $package.sha256) { throw 'Published PHP package hash mismatch' }
    Expand-Archive control.zip $bin
    $binaryOrigin = $package.path
} else {
    $package = Get-ChildItem artifacts -Filter "php-$($plan.version)-nts-Win32-*-arm64.zip"
    if (@($package).Count -ne 1) { throw 'Expected one original ARM64 package' }
    Expand-Archive $package.FullName $bin
    $binaryOrigin = "run $($plan.run): $($package.Name)"
}
$exe = Join-Path $bin 'php.exe'
$env:PATH = "$bin;$env:PATH"
$env:TEST_PHP_EXECUTABLE = $exe
$env:TEST_PHPDBG_EXECUTABLE = Join-Path $bin 'phpdbg.exe'
$env:NO_INTERACTION = '1'
$env:REPORT_EXIT_STATUS = '1'
$env:SKIP_IO_CAPTURE_TESTS = '1'
@{source=$sourceSha;binary=$binaryOrigin;sha256=(Get-FileHash $exe).Hash;arch=$Arch;case=$Case} | ConvertTo-Json | Set-Content control-provenance.json
& $exe -n -v
if ($LASTEXITCODE) { throw 'Control PHP cannot execute' }

if ($Case -eq 'files') {
    $priority = @'
<?php
foreach ([10=>4, 5=>6, 0=>8, -5=>10, -10=>13] as $nice=>$expected) {
    if (!proc_nice($nice)) exit(1);
    $actual = (int)shell_exec('powershell.exe -NoProfile -Command "(Get-Process -Id '.getmypid().').BasePriority"');
    echo "$nice: $actual (expected $expected)\n";
    if ($actual !== $expected) exit(2);
}
'@
    Set-Content priority.php $priority
    & $exe -n priority.php 2>&1 | Tee-Object priority.log
    if ($LASTEXITCODE) { throw 'Real process priority check failed' }
    $cases = @('rename_variation-win32','unlink_variation8-win32','unlink_variation9-win32') | ForEach-Object { "ext/standard/tests/file/$_.phpt" }
} elseif ($Case -like 'firebird*') {
    if (Test-Path "$bin/fbclient.dll") { throw 'Bundled client would invalidate the PATH control' }
    if ($Case -eq 'firebird4') {
        $url = 'https://github.com/FirebirdSQL/firebird/releases/download/v4.0.4/Firebird-4.0.4.3010-0-x64.zip'
        $digest = ''
    } else {
        $url = 'https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.2210-0-5976482-windows-x64.zip'
        $digest = '46c9e139e248895b1c101353a3d907bce4725ff4851ef60c2ea1d9704edf2073'
    }
    Invoke-WebRequest $url -OutFile client.zip
    $hash = (Get-FileHash client.zip).Hash
    if ($digest -and $hash -ne $digest) { throw 'Firebird client changed' }
    Expand-Archive client.zip client
    $client = Join-Path $workspace 'client'
    $env:PATH = "$client;$env:PATH"
    Get-FileHash "$client/fbclient.dll" | Format-List | Out-File client.log
    (Get-Item "$client/fbclient.dll").VersionInfo | Format-List | Out-File client.log -Append
    # This regression test uses its own recorded-protocol server.
    $env:PDO_FIREBIRD_TEST_DSN = 'firebird:dbname=127.0.0.1:unused'
    $cases = @('ext/pdo_firebird/tests/bug_76452.phpt')
} elseif ($Case -eq 'postgres') {
    Import-Module ./php/BuildPhp -Force
    & (Get-Module BuildPhp) { Set-PgSqlTestEnvironment -Arch arm64 }
    $stress = @'
<?php
$times=[];
for ($i=0;$i<50;$i++) {
    $t=microtime(true);
    $p=new PDO(getenv('PDO_PGSQL_TEST_DSN'));
    if ($p->query('SELECT 42')->fetchColumn() != 42) exit(2);
    $p=null;
    $times[]=microtime(true)-$t;
}
echo json_encode(['connections'=>count($times),'seconds'=>array_sum($times),'maxSeconds'=>max($times)]),"\n";
'@
    Set-Content pgsql-stress.php $stress
    $workers = @(1..6 | ForEach-Object {
        Start-Process $exe -ArgumentList @('-n','-d',"extension_dir=$bin/ext",'-d','extension=pdo_pgsql',"$workspace/pgsql-stress.php") -PassThru -NoNewWindow -RedirectStandardOutput "$workspace/pgsql-$_.log" -RedirectStandardError "$workspace/pgsql-$_.error.log"
    })
    foreach ($worker in $workers) { $worker.WaitForExit(); $worker.Refresh() }
    Get-Content pgsql-*.log
    Copy-Item "$env:TEMP/php-test-postgresql/server.log" postgres-server.log
    $failed = @($workers | Where-Object ExitCode -ne 0)
    @{workers=6;connectionsPerWorker=50;failedWorkers=$failed.Count;exitCodes=@($workers.ExitCode)} | ConvertTo-Json | Set-Content postgres-summary.json
    if ($failed.Count) { throw 'PostgreSQL concurrent connection control failed; inspect server and worker logs' }
    $cases = @('ext/pdo_pgsql/tests')
} else { throw 'Unknown control case' }

$env:TEST_PHP_JUNIT = Join-Path $workspace 'control.xml'
Set-Location source
try {
    & $exe -n run-tests.php -p $exe -n -d "extension_dir=$bin/ext" --offline --show-diff --no-progress -g FAIL,BORK,WARN -q @cases 2>&1 | Tee-Object "$workspace/control.log"
    $result = $LASTEXITCODE
} finally { Set-Location $workspace }
if (-not (Test-Path control.xml)) { throw 'No control report' }
$xml = [xml](Get-Content control.xml -Raw)
@{exitCode=$result;cases=$xml.SelectNodes('//testcase').Count;skips=$xml.SelectNodes('//testcase[skipped]').Count;failures=@($xml.SelectNodes('//testcase[failure or error]') | ForEach-Object {$_.OuterXml})} | ConvertTo-Json -Depth 5 | Set-Content control-summary.json
if ($Case -eq 'postgres') { Copy-Item "$env:TEMP/php-test-postgresql/server.log" postgres-server.log -Force }
exit $result
