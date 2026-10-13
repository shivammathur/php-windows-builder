param([Parameter(Mandatory)][ValidateSet('original','cache-off','modern','modern-cache-off','no-shrink-wrap')][string]$Mode,
      [Parameter(Mandatory)][string]$Deps, [switch]$FullCore)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$workspace = (Get-Location).Path
$results = (New-Item results -ItemType Directory -Force).FullName
$parent = Split-Path $workspace -Parent
if ($parent -ne [IO.Path]::GetFullPath('C:/a/php-windows-builder')) { throw 'Preserved absolute paths differ' }
if ((git rev-parse HEAD) -ne '6d72982f6f2f42fbfb6523ed777cb217f8925afd') { throw 'Source branch changed' }
& 7z x preserved/build-state.7z -oreplay -y
if ($LASTEXITCODE) { throw 'Cannot extract preserved objects' }
Move-Item replay/obj "$parent/obj"
Copy-Item $Deps "$parent/deps" -Recurse
Copy-Item replay/Makefile,replay/Makefile.objects .
$out = "$parent/obj/Release_TS"
$pgd = "$out/php8ts.pgd"
$pgdHash = (Get-FileHash $pgd).Hash
if ($pgdHash -ne '93539D43267BB737DEC8D2A84F2EE70F014ADD8540FB44B4D7A515E1FB8C9878') { throw 'Profile changed' }
$objects = @(Get-ChildItem $out -Filter *.obj -Recurse | Sort-Object FullName)
$before = $objects | Get-FileHash | ConvertTo-Json
$before | Set-Content "$results/objects-before.json"
Copy-Item $pgd "$results/input.pgd"
Get-Command cl.exe,link.exe | Select-Object Source | ConvertTo-Json | Set-Content "$results/tools.json"
$env:PATH = "$env:VCToolsInstallDir/bin/arm64;$parent/deps/bin;$env:PATH"
& pgomgr /summary $pgd 2>&1 | Tee-Object "$results/input-profile.txt"
if ($LASTEXITCODE) { throw 'Cannot inspect original profile' }

$package = 'artifacts/php-8.6.0-dev-Win32-vs18-arm64.zip'
if ((Get-FileHash $package).Hash -ne 'B75908B86982D42EF48178A6DF8119573B3488500F58B901AC2F64ECB0FEB2CB') { throw 'Runtime package changed' }
Expand-Archive $package runtime
$exe = "$workspace/runtime/php.exe"
$env:PATH = "$workspace/runtime;$env:PATH"
$generator = '<?php function a() { yield from a(); } foreach (a() as $v);'
[IO.File]::WriteAllText("$results/generator.php", $generator)
function Invoke-Generator([string]$Label) {
    @(foreach ($memory in '8M','16M','32M','64M') {
        $start = [Diagnostics.ProcessStartInfo]::new($exe)
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($arg in @('-n','-d','fatal_error_backtraces=Off','-d',"memory_limit=$memory","$results/generator.php")) { $start.ArgumentList.Add($arg) }
        $process = [Diagnostics.Process]::Start($start)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill($true); throw 'Generator timed out' }
        @{memory=$memory;exit=$process.ExitCode;stdout=$stdout.GetAwaiter().GetResult();stderr=$stderr.GetAwaiter().GetResult()}
    }) | ConvertTo-Json -Depth 5 | Set-Content "$results/generator-$Label.json"
}
Copy-Item "$out/php8ts.dll" runtime/php8ts.dll -Force
Invoke-Generator original-preserved

$makefile = [IO.File]::ReadAllText('Makefile')
$needle = 'STATIC_EXT_LDFLAGS=$(LDFLAGS_BCMATH) /LTCG:PGUPDATE '
if ([regex]::Matches($makefile,[regex]::Escape($needle)).Count -ne 1) { throw 'Unexpected core PGO flags' }
$flags = if ($Mode -like 'modern*') { '/LTCG /USEPROFILE' } else { '/LTCG:PGUPDATE' }
if ($Mode -like '*cache-off') { $flags += ' /d2:-FuncCache1' }
if ($Mode -eq 'no-shrink-wrap') { $flags += ' /d2:-shrink-wrapping-' }
$makefile = $makefile.Replace($needle, 'STATIC_EXT_LDFLAGS=$(LDFLAGS_BCMATH) ' + $flags + ' ')
# A phony target runs only the exact saved core link. No source regeneration or compilation.
$recipe = @'

core-replay:
	copy win32\build\default.manifest $(BUILD_DIR)\$(PHPDLL).manifest >nul
	"$(LINK)" $(PHP_GLOBAL_OBJS_RESP) $(STATIC_EXT_OBJS_RESP) $(STATIC_EXT_LIBS) $(LIBS) $(ASM_OBJS) $(PHPDLL_RES) /out:$(BUILD_DIR)\$(PHPDLL) $(PHP8_PGD_OPTION) $(PHP_LDFLAGS) $(LDFLAGS) $(STATIC_EXT_LDFLAGS) /MAP:results/core.map
	if exist $(BUILD_DIR)\$(PHPDLL).manifest $(MT) -nologo -manifest $(BUILD_DIR)\$(PHPDLL).manifest -outputresource:$(BUILD_DIR)\$(PHPDLL);2
'@
[IO.File]::WriteAllText('Makefile', $makefile + $recipe + "`n")
Copy-Item Makefile "$results/Makefile"
Remove-Item "$out/php8ts.dll"
& nmake /nologo core-replay 2>&1 | Tee-Object "$results/link.log"
if ($LASTEXITCODE -or -not (Test-Path "$out/php8ts.dll")) { throw 'Fresh PGO link failed' }
if (($objects | Get-FileHash | ConvertTo-Json) -cne $before) { throw 'Input objects changed' }
if (-not (Select-String "$results/link.log" -Pattern '\d+ of \d+ instructions .* were optimized using profile data' -Quiet)) { throw 'Missing real PGO optimization evidence' }
& dumpbin /headers "$out/php8ts.dll" > "$results/headers.txt"
if ($LASTEXITCODE -or -not (Select-String "$results/headers.txt" -Pattern 'AA64 machine' -Quiet)) { throw 'Fresh DLL is not ARM64' }
& dumpbin /unwindinfo "$out/php8ts.dll" > "$results/unwind.txt"
Copy-Item "$out/php8ts.dll","$out/php8ts.pdb",$pgd $results
Get-FileHash "$results/php8ts.dll","$results/php8ts.pdb",$pgd | ConvertTo-Json | Set-Content "$results/outputs.json"
Copy-Item "$out/php8ts.dll" runtime/php8ts.dll -Force
& $exe -n -r 'if (PHP_VERSION !== "8.6.0-dev" || PHP_INT_SIZE !== 8 || array_sum(range(1,10000)) !== 50005000) exit(1); echo "Fresh core smoke passed\n";'
if ($LASTEXITCODE) { throw 'Fresh core cannot execute' }
Invoke-Generator replay
$env:TEST_PHP_EXECUTABLE = $exe
$env:TEST_PHP_CGI_EXECUTABLE = "$workspace/runtime/php-cgi.exe"
$env:TEST_PHPDBG_EXECUTABLE = "$workspace/runtime/phpdbg.exe"
$env:NO_INTERACTION = '1'
$env:REPORT_EXIT_STATUS = '1'
$env:SKIP_IO_CAPTURE_TESTS = '1'
foreach ($cache in 'nocache','opcache') {
    $env:TEST_PHP_JUNIT = "$results/core-$cache.xml"
    $options = @('-n','-d','fatal_error_backtraces=Off','-d',"extension_dir=$workspace/runtime/ext",'-d','display_errors=1')
    if ($FullCore) { $options += @('-d','memory_limit=-1','-d','extension=openssl','-d','extension=sockets') }
    if ($cache -eq 'opcache') { $options += @('-d','opcache.enable_cli=1') }
    $directories = if ($FullCore) { @('Zend/tests','tests','sapi/cgi/tests','sapi/cli/tests') } else { @('Zend/tests/generators','Zend/tests/fibers','sapi/cgi/tests') }
    & $exe -n run-tests.php -p $exe @options --offline --show-diff --no-progress -g FAIL,BORK,WARN,SKIP -q -j6 @directories 2>&1 | Tee-Object "$results/core-$cache.log"
    $testExit = $LASTEXITCODE
    if (-not (Test-Path "$results/core-$cache.xml")) { throw 'No PHPT report' }
    $xml = [xml](Get-Content "$results/core-$cache.xml" -Raw)
    @{exitCode=$testExit;cases=$xml.SelectNodes('//testcase').Count;skips=$xml.SelectNodes('//testcase[skipped]').Count;failures=@($xml.SelectNodes('//testcase[failure or error]') | ForEach-Object OuterXml)} | ConvertTo-Json -Depth 5 | Set-Content "$results/core-$cache.json"
}
$global:LASTEXITCODE = 0
