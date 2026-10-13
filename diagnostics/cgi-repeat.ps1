param([Parameter(Mandatory)][string]$Php, [Parameter(Mandatory)][string]$Ts, [switch]$PublishedX64)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$workspace = (Get-Location).Path
$results = (New-Item results -ItemType Directory -Force).FullName
$p = @(Get-Content diagnostics/core-runtime-plan.json -Raw | ConvertFrom-Json | Where-Object { $_.php -eq $Php -and $_.ts -eq $Ts })
if ($p.Count -ne 1) { throw 'Ambiguous package' }
$p = $p[0]
if ($PublishedX64) {
    $p=[pscustomobject]@{php='8.4.26-published-x64';ts='nts';run=$null;source='fix/windows-arm64-8.4';sourceSha='74523757b112babd04515feb8cfac4e531bf6add';binary='php-8.4.26-nts-Win32-vs17-x64.zip';binaryHash='da68394f9193b7f6b89d0c76861a4034ae10efee7fd55a7255d8118c2acf70d7'}
    New-Item artifacts -ItemType Directory -Force | Out-Null
    Invoke-WebRequest "https://downloads.php.net/~windows/releases/$($p.binary)" -OutFile "artifacts/$($p.binary)"
}
if ((git -C source rev-parse HEAD) -ne $p.sourceSha) { throw 'Source branch changed' }
if ((Get-FileHash "artifacts/$($p.binary)").Hash -ne $p.binaryHash) { throw 'Original package changed' }
Expand-Archive "artifacts/$($p.binary)" runtime
$bin = "$workspace/runtime"
$exe = "$bin/php.exe"
$env:PATH = "$bin;$env:PATH"
$env:TEST_PHP_EXECUTABLE = $exe
$env:TEST_PHP_EXECUTABLE_ESCAPED = '"' + $exe + '"'
$env:TEST_PHP_CGI_EXECUTABLE = "$bin/php-cgi.exe"
$env:NO_INTERACTION = '1'
$env:REPORT_EXIT_STATUS = '1'
$p | ConvertTo-Json | Set-Content "$results/provenance.json"
Get-Item "$env:WINDIR/System32/ntdll.dll", "$env:WINDIR/System32/vcruntime140.dll", "$env:WINDIR/System32/ucrtbase.dll" |
    ForEach-Object { @{path=$_.FullName;version=$_.VersionInfo.FileVersion;sha256=(Get-FileHash $_).Hash} } | ConvertTo-Json | Set-Content "$results/system-runtime.json"
foreach ($mode in 'nocache','opcache') {
    $flags = @('-n','-d',"extension_dir=$bin/ext",'-d','extension=intl','-d','display_errors=1','-d','fatal_error_backtraces=Off')
    if ($mode -eq 'opcache') {
        if (Test-Path "$bin/ext/php_opcache.dll") { $flags += @('-d','zend_extension=opcache') }
        $flags += @('-d','opcache.enable_cli=1')
    }
    & $exe @flags diagnostics/cgi-repeat.php "$workspace/source" "$results/processes-$mode.json" 2>&1 | Tee-Object "$results/processes-$mode.log"
    if ($LASTEXITCODE) { throw 'Runtime control did not finish' }
    $entries = @(Get-Content "$results/processes-$mode.json" -Raw | ConvertFrom-Json)
    if ($entries.Count -ne 2100) { throw 'Missing subprocess observations' }
    $bad = @($entries | Where-Object { ($_.output -replace "`r`n", "`n") -ne "Interactive mode enabled`n`nNo input file specified.`n" })
    @{cases=$entries.Count;missingOutput=$bad.Count;failures=$bad} | ConvertTo-Json -Depth 6 | Set-Content "$results/summary-$mode.json"
    Push-Location source
    try {
        foreach ($iteration in 1..10) {
            $env:TEST_PHP_JUNIT = "$results/cgi-$mode-$iteration.xml"
            & $exe -n run-tests.php -p $exe @flags --offline --show-diff --no-progress -q sapi/cgi/tests/005.phpt sapi/cgi/tests/011.phpt 2>&1 | Tee-Object "$results/cgi-$mode-$iteration.log"
            if (-not (Test-Path $env:TEST_PHP_JUNIT)) { throw 'Missing CGI report' }
        }
    } finally { Pop-Location }
}
$global:LASTEXITCODE = 0
