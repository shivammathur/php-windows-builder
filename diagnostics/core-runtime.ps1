param([Parameter(Mandatory)][string]$Php, [Parameter(Mandatory)][string]$Ts)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$workspace = (Get-Location).Path
$results = New-Item results -ItemType Directory -Force
$p = @(Get-Content diagnostics/core-runtime-plan.json -Raw | ConvertFrom-Json | Where-Object { $_.php -eq $Php -and $_.ts -eq $Ts })
if ($p.Count -ne 1) { throw 'Ambiguous package provenance' }
$p = $p[0]
if ((git -C source rev-parse HEAD) -ne $p.sourceSha) { throw 'Source branch moved' }
foreach ($kind in 'binary','debug') {
    $archive = Join-Path "$workspace/artifacts" $p.$kind
    if ((Get-FileHash $archive).Hash -ne $p."${kind}Hash") { throw "$kind archive differs from the audited package" }
    Expand-Archive $archive "$workspace/$kind"
}
$bin = "$workspace/binary"
$exe = "$bin/php.exe"
$env:PATH = "$bin;$env:PATH"
$env:TEST_PHP_EXECUTABLE = $exe
$env:TEST_PHP_CGI_EXECUTABLE = "$bin/php-cgi.exe"
$env:TEST_PHPDBG_EXECUTABLE = "$bin/phpdbg.exe"
$env:NO_INTERACTION = '1'
$env:REPORT_EXIT_STATUS = '1'
$env:SKIP_IO_CAPTURE_TESTS = '1'
$p | ConvertTo-Json | Set-Content results/provenance.json
& $exe -n -v | Tee-Object results/php-version.txt
if ($LASTEXITCODE) { throw 'Original package cannot execute' }
Get-Item "$env:WINDIR/System32/ntdll.dll", "$env:WINDIR/System32/vcruntime140.dll", "$env:WINDIR/System32/ucrtbase.dll" |
    ForEach-Object { @{path=$_.FullName;version=$_.VersionInfo.FileVersion;sha256=(Get-FileHash $_).Hash} } |
    ConvertTo-Json | Set-Content results/system-runtime.json

function Invoke-Captured([string]$Name, [string]$Program, [string[]]$Arguments, [int]$Seconds = 120) {
    $start = [Diagnostics.ProcessStartInfo]::new($Program)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($arg in $Arguments) { $start.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($Seconds * 1000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $out = $stdout.GetAwaiter().GetResult()
    $err = $stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText("$results/$Name.stdout.txt", $out)
    [IO.File]::WriteAllText("$results/$Name.stderr.txt", $err)
    return @{name=$Name;program=$Program;arguments=$Arguments;exitCode=$process.ExitCode;timedOut=$timedOut;stdout=$out;stderr=$err}
}
$original = [IO.File]::ReadAllText("$workspace/source/Zend/tests/generators/gh9801.phpt")
$body = [regex]::Match($original, '(?s)--FILE--\r?\n(.*?)\r?\n--EXPECTF--').Groups[1].Value
if (-not $body.Contains('yield from a()')) { throw 'Unexpected generator regression test' }
[IO.File]::WriteAllText("$results/generator.php", $body)
$rawResults = @(foreach ($memory in '8M','16M','32M','64M') {
    Invoke-Captured "generator-$memory" $exe @('-n','-d',"memory_limit=$memory","$results/generator.php")
})
$rawResults | ConvertTo-Json -Depth 5 | Set-Content results/generator-processes.json

$cgi = @(foreach ($iteration in 1..30) {
    foreach ($mode in 'af','fa') {
        $flags = if ($mode -eq 'af') { @('-n','-a','-f','wrong') } else { @('-n','-f','wrong','-a') }
        Invoke-Captured "cgi-$iteration-$mode" "$bin/php-cgi.exe" $flags 30
    }
})
$cgi | ConvertTo-Json -Depth 5 | Set-Content results/cgi-processes.json

foreach ($mode in 'nocache','opcache') {
    $env:TEST_PHP_JUNIT = "$results/core-$mode.xml"
    $flags = @('-n','-d',"extension_dir=$bin/ext",'-d','display_errors=1')
    if ($mode -eq 'opcache') {
        if (Test-Path "$bin/ext/php_opcache.dll") { $flags += @('-d','zend_extension=opcache') }
        $flags += @('-d','opcache.enable_cli=1')
    }
    Push-Location source
    try {
        & $exe -n run-tests.php -p $exe @flags --offline --show-diff --no-progress -g FAIL,BORK,WARN,SKIP -q Zend/tests/generators Zend/tests/fibers sapi/cgi/tests 2>&1 |
            Tee-Object "$results/core-$mode.log"
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if (-not (Test-Path "$results/core-$mode.xml")) { throw 'Missing diagnostic PHPT report' }
    $xml = [xml](Get-Content "$results/core-$mode.xml" -Raw)
    @{exitCode=$code;cases=$xml.SelectNodes('//testcase').Count;skips=$xml.SelectNodes('//testcase[skipped]').Count;failures=@($xml.SelectNodes('//testcase[failure or error]') | ForEach-Object {$_.OuterXml})} |
        ConvertTo-Json -Depth 5 | Set-Content "$results/core-$mode.json"
}

$debugRoot = "${env:ProgramFiles(x86)}/Windows Kits/10/Debuggers/arm64"
$cdb = "$debugRoot/cdb.exe"
if (-not (Test-Path $cdb)) {
    $url = 'https://download.visualstudio.microsoft.com/download/pr/e690ed5c-a2c2-42aa-8cbb-4f3ea5f87edf/8184cebe60d18b62a5cfd99bd6551eff/winsdksetup.exe'
    Invoke-WebRequest $url -OutFile "$env:TEMP/winsdksetup.exe"
    if ((Get-FileHash "$env:TEMP/winsdksetup.exe").Hash -ne '9B447E73C9ADA8D912F1633662334927B3F4A0E6DFAAB787ABFB150A69A0225A') { throw 'Unexpected SDK installer hash' }
    $setup = Start-Process "$env:TEMP/winsdksetup.exe" -ArgumentList '/features','OptionId.WindowsDesktopDebuggers','/quiet','/norestart' -Wait -PassThru
    if ($setup.ExitCode -notin 0,3010) { throw "Debugger installation failed: $($setup.ExitCode)" }
}
if (-not (Test-Path $cdb)) { throw 'Native ARM64 debugger is unavailable' }
Get-FileHash $cdb | ConvertTo-Json | Set-Content results/debugger.json
$symbols = @((Get-ChildItem "$workspace/debug" -Recurse -Filter *.pdb).DirectoryName | Sort-Object -Unique) -join ';'
$symbols += ';srv*C:\symbols*https://msdl.microsoft.com/download/symbols'
$commands = @"
sxe -c ".echo BAD_STACK; .exr -1; .ecxr; kv 80; r; lm; .dump /ma $results/generator.dmp; q" 0xc0000028
sxe -c ".echo ACCESS_VIOLATION; .exr -1; .ecxr; kv 80; r; lm; .dump /ma $results/generator-av.dmp; q" av
g
q
"@
[IO.File]::WriteAllText("$results/debugger-commands.txt", $commands)
Invoke-Captured 'debugger' $cdb @('-G','-y',$symbols,'-cf',"$results/debugger-commands.txt",$exe,'-n','-d','memory_limit=16M',"$results/generator.php") 300 |
    ConvertTo-Json -Depth 5 | Set-Content results/debugger-process.json
