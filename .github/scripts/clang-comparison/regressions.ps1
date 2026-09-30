param([string]$Mode)
. "$PSScriptRoot/common.ps1"
$root = $env:GITHUB_WORKSPACE
[string[]]$tests = if ($env:VALIDATION_TEST_FILES) { @($env:VALIDATION_TEST_FILES | ConvertFrom-Json) } else { @('tests','Zend/tests','sapi','ext') }
$out = New-Item "$root/regressions" -ItemType Directory -Force
$started = Get-Date
$crashKey = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\php.exe'
New-Item $crashKey -Force | Out-Null
New-ItemProperty $crashKey -Name DumpFolder -Value "$out/crashes" -PropertyType ExpandString -Force | Out-Null
New-ItemProperty $crashKey -Name DumpType -Value 1 -PropertyType DWord -Force | Out-Null
$variants = if ($env:VALIDATION_VARIANT -in @('msvc','clang')) { @($env:VALIDATION_VARIANT) } else { @('msvc','clang') }
$fixturesPrepared = $false
foreach ($variant in $variants) {
    $runtime = Expand-Runtime $variant
    # Match php-src CI's SSL configuration setup for both architectures.
    $env:OPENSSL_CONF = Join-Path $runtime 'extras/ssl/openssl.cnf'
    $env:OPENSSL_MODULES = Join-Path $runtime 'extras/ssl'
    if (-not $fixturesPrepared -and ($env:VALIDATION_DATABASE_SERVICES -eq 'true' -or $tests -contains 'ext' -or $tests -contains 'ext/pdo_firebird/tests' -or $tests -contains 'ext/snmp/tests')) {
        . "$PSScriptRoot/prepare-services.ps1" -Runtime $runtime
        $fixturesPrepared = $true
    }
    & "$PSScriptRoot/start-snmp.ps1" -Runtime $runtime -Variant $variant
    $ini = Write-TestIni $runtime $Mode
    # run-tests spawns its controller workers without the parent's -c option.
    # Redirect tests execute in those workers and require COM/PDO there too.
    # Keep JIT on the tested programs; the test controllers use plain CLI.
    $controllerIni = Write-TestIni $runtime 'nocache'
    Copy-Item $controllerIni "$runtime/controller.ini" -Force
    $controllerIni = "$runtime/controller.ini"
    Add-Content $controllerIni @('log_errors=1', ('error_log="{0}"' -f "$out/$variant-controller-errors.log"))
    Copy-Item $controllerIni "$runtime/php.ini" -Force
    $env:PHPRC = $controllerIni
    & "$runtime/php.exe" -r 'echo json_encode(["ini"=>php_ini_loaded_file(),"com"=>class_exists("COM"),"pdo"=>class_exists("PDO")]); if (!class_exists("COM") || !class_exists("PDO")) { exit(1); }' | Set-Content "$out/$variant-controller.json"
    if ($LASTEXITCODE -ne 0) { throw "$variant controller dependencies are unavailable" }
    # This generated helper is absent from a source checkout and is needed by
    # proc_open_cmd.phpt. Test the helper shipped by each compiler's test pack.
    $testPack = @(Get-ChildItem "$root/input/$variant/php-test-pack-*.zip")
    if ($testPack.Count -ne 1) { throw "Expected one test pack for $variant" }
    $archive = [IO.Compression.ZipFile]::OpenRead($testPack[0].FullName)
    try {
        $helper = 'ext/standard/tests/helpers/bad_cmd.exe'
        $entry = $archive.GetEntry($helper)
        if (-not $entry) { throw "Test pack is missing $helper" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$root/source/$helper", $true)
    } finally { $archive.Dispose() }
    $env:TEST_PHP_EXECUTABLE = "$runtime/php.exe"
    $env:TEST_PHPDBG_EXECUTABLE = "$runtime/phpdbg.exe"
    $env:TEST_PHP_CGI_EXECUTABLE = "$runtime/php-cgi.exe"
    $env:TEST_PHP_JUNIT = "$out/$variant.xml"
    $env:NO_INTERACTION = '1'
    $env:REPORT_EXIT_STATUS = '1'
    $env:SKIP_IO_CAPTURE_TESTS = '1'
    Set-Location "$root/source"
    if ($tests -contains 'ext' -or $tests -contains 'ext/com_dotnet/tests') {
        & "$PSScriptRoot/prepare-comtest.ps1" -Variant $variant
    }
    # Redirect to a file in cmd, so a test's surviving child cannot hold open
    # PowerShell's native output pipe after run-tests has printed its summary.
    $arguments = @('-n','-c',$controllerIni,'run-tests.php','-p',$env:TEST_PHP_EXECUTABLE,'-n','-c',$ini,'-q','--offline','--no-progress','--show-diff','--set-timeout','90','-j4','-g','FAIL,BORK,WARN,LEAK','-W',"$out/$variant-results.txt") + $tests
    $command = '"' + $env:TEST_PHP_EXECUTABLE + '" ' + (($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ' > "' + "$out/$variant.log" + '" 2>&1'
    $launcher = Join-Path $out "$variant-tests.cmd"
    Set-Content $launcher "@echo off`r`n$command`r`nexit /b %errorlevel%" -Encoding ascii
    # Keep unrelated hosted-runner tool variables out of PHPT subprocesses.
    # PHP's existing Windows environment converter has a fixed 32760-wide-char
    # buffer; the stack_limit_006 fixture adds another ~20K environment block.
    $testEnvironment = @{}
    $keepEnvironment = '^(?:Path|PATHEXT|ComSpec|SystemRoot|SystemDrive|windir|TEMP|TMP|USERPROFILE|USERNAME|USERDOMAIN|HOMEDRIVE|HOMEPATH|APPDATA|LOCALAPPDATA|ALLUSERSPROFILE|ProgramData|ProgramFiles.*|CommonProgramFiles.*|PROCESSOR.*|NUMBER_OF_PROCESSORS|OS|COMPUTERNAME|PUBLIC|CI|GITHUB_ACTIONS|PHP.*|TEST_PHP.*|MYSQL.*|PDO_.*|PG.*|ODBC.*|SNMP.*|MIB.*|OPENSSL.*|NO_INTERACTION|REPORT_EXIT_STATUS|SKIP_.*)$'
    $kept = @()
    foreach ($item in Get-ChildItem Env:) {
        if ($item.Name -match $keepEnvironment) {
            $kept += [ordered]@{name=$item.Name;characters=$item.Name.Length + $item.Value.Length + 2}
        } else {
            $testEnvironment[$item.Name] = $null
        }
    }
    [ordered]@{characters=($kept | Measure-Object characters -Sum).Sum;variables=$kept} | ConvertTo-Json -Depth 3 | Set-Content "$out/$variant-test-environment.json"
    $process = Start-Process cmd.exe -ArgumentList @('/d','/c',('"' + $launcher + '"')) -NoNewWindow -PassThru -Environment $testEnvironment
    $deadline = [DateTime]::UtcNow.AddMinutes(90)
    while (-not $process.WaitForExit(60000)) {
        $progress = @(Get-Content "$out/$variant-results.txt" -ErrorAction SilentlyContinue)
        Write-Host "$variant $Mode tests: $($progress.Count) completed; latest: $($progress | Select-Object -Last 1)"
        if ([DateTime]::UtcNow -ge $deadline) {
            & taskkill /PID $process.Id /T /F
            throw "$variant regression controller exceeded 90 minutes"
        }
    }
    $testExit = $process.ExitCode
    Get-Content "$out/$variant.log" | Write-Host
    Write-Host "$variant test controller exited: $testExit; collecting results"
    [ordered]@{variant=$variant; mode=$Mode;exitCode=$testExit;source=(& git rev-parse HEAD)} | ConvertTo-Json | Set-Content "$out/$variant-status.json"
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$started} -ErrorAction Continue |
        Where-Object ProviderName -In 'Application Error','Windows Error Reporting' |
        Select-Object TimeCreated,Id,ProviderName,Message | ConvertTo-Json -Depth 5 | Set-Content "$out/$variant-crash-events.json"
    $failures = Get-ChildItem -Path . -Recurse -File -Include '*.diff','*.out','*.exp','*.log' | Where-Object { $_.FullName -notmatch '\.git[\\/]' }
    $dest = New-Item "$out/$variant-failures" -ItemType Directory -Force
    foreach ($file in $failures) {
        $relative = [IO.Path]::GetRelativePath((Get-Location).Path, $file.FullName)
        $target = Join-Path $dest $relative
        New-Item ([IO.Path]::GetDirectoryName($target)) -ItemType Directory -Force | Out-Null
        Copy-Item $file.FullName $target
    }
    if (-not (Test-Path $env:TEST_PHP_JUNIT) -or (Get-Item $env:TEST_PHP_JUNIT).Length -eq 0) {
        throw "$variant test runner terminated without JUnit results"
    }
    [xml]$junit = Get-Content $env:TEST_PHP_JUNIT -Raw
    if ($junit.SelectNodes('//testcase').Count -eq 0) { throw "$variant JUnit report contains no tests" }
    # Restore generated test files before the second compiler's run.
    git clean -fdx
    if ($LASTEXITCODE -ne 0) { throw 'Failed to clean isolated test source' }
}
