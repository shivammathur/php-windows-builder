param([ValidateSet('arm64','x64')][string]$Arch,[ValidateSet('full','signals')][string]$Mode)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$workspace=(Get-Location).Path
$results=(New-Item results -ItemType Directory -Force).FullName
$builderSha='1d4e815ca5467192388eb2c89d1227522cf1e3d5'
$p=if($Arch -eq 'arm64') {
    @{version='8.7.0-dev';source='fix/windows-arm64-master';sourceSha='97bec8b7114baf33cb9d83176c762ef97d583e2e';zip='php-8.7.0-dev-nts-Win32-vs18-arm64.zip';hash='f183b40210d720f0036521b05b2511304f53f955f923d9827cc2c5de4652ee85'}
} else {
    @{version='8.4.26';source='fix/windows-arm64-8.4';sourceSha='74523757b112babd04515feb8cfac4e531bf6add';zip='php-8.4.26-nts-Win32-vs17-x64.zip';hash='da68394f9193b7f6b89d0c76861a4034ae10efee7fd55a7255d8118c2acf70d7'}
}
if((git -C source rev-parse HEAD) -ne $p.sourceSha -or (git -C builder rev-parse HEAD) -ne $builderSha){throw 'Reviewed branch changed'}
if($Arch -eq 'x64') {
    New-Item artifacts -ItemType Directory -Force|Out-Null
    Invoke-WebRequest "https://downloads.php.net/~windows/releases/$($p.zip)" -OutFile "artifacts/$($p.zip)"
    Remove-Item Env:DEPS_DIR,Env:DEPS_CACHE_HIT -ErrorAction SilentlyContinue
}
if((Get-FileHash "artifacts/$($p.zip)").Hash -ne $p.hash){throw 'Package digest changed'}
@{package=$p;arch=$Arch;mode=$Mode;builder=$builderSha}|ConvertTo-Json -Depth 5|Set-Content "$results/provenance.json"
Get-Item "$env:WINDIR/System32/ntdll.dll","$env:WINDIR/System32/ucrtbase.dll"|ForEach-Object {@{path=$_.FullName;version=$_.VersionInfo.FileVersion;sha256=(Get-FileHash $_).Hash}}|ConvertTo-Json|Set-Content "$results/system-runtime.json"
Import-Module "$workspace/builder/php/BuildPhp" -Force

# Kernel events observe the unchanged CGI process without wrapping shell_exec.
foreach($kind in 'Start','Stop') {
    Register-CimIndicationEvent -Namespace root/cimv2 -Query "SELECT * FROM Win32_Process${kind}Trace WHERE ProcessName='php-cgi.exe' OR ProcessName='php.exe' OR ProcessName='cmd.exe'" -SourceIdentifier "Cgi$kind"|Out-Null
}
function Save-ProcessEvents([string]$Name) {
    Start-Sleep -Seconds 2
    $records=@(foreach($kind in 'Start','Stop') {
        foreach($event in @(Get-Event -SourceIdentifier "Cgi$kind" -ErrorAction SilentlyContinue)) {
            $e=$event.SourceEventArgs.NewEvent
            @{kind=$kind;time=[DateTime]::FromFileTimeUtc([long]$e.TIME_CREATED).ToString('o');pid=$e.ProcessID;parent=$e.ParentProcessID;name=$e.ProcessName;exit=$e.ExitStatus;session=$e.SessionID}
            Remove-Event -EventIdentifier $event.EventIdentifier
        }
    })
    $records|ConvertTo-Json -Depth 4|Set-Content "$results/processes-$Name.json"
    if(-not @($records|Where-Object {$_.kind -eq 'Stop' -and $_.name -eq 'php-cgi.exe'}).Count){throw 'Missing CGI process-exit evidence'}
}
try {
    $passes=if($Mode -eq 'full'){1..3}else{1..1}
    foreach($iteration in $passes) {
        Push-Location "$workspace/artifacts"
        try {
            $args=@{PhpVersion=$p.version;Arch=$Arch;Ts='nts';Opcache='opcache';TestType='php';SourceRepository='shivammathur/php-src';SourceRef=$p.source}
            if($Mode -eq 'signals'){$args.TestDirectories=@('sapi/cgi/tests','sapi/cli/tests')}
            Invoke-PhpTests @args
            $env:DEPS_CACHE_HIT='true'
        } finally {Pop-Location}
        $build=Split-Path $env:TEST_PHP_JUNIT
        $tests=Join-Path $build tests
        $dest=(New-Item "$results/core-$iteration" -ItemType Directory -Force).FullName
        Copy-Item "$workspace/artifacts/test-$Arch-nts-opcache-php.*" $dest
        Copy-Item "$build/phpbin/php-test.ini" "$dest/php-test.ini"
        Copy-Item "$tests/php-tests-to-run.txt" $dest
        $sourceFiles=@(foreach($dir in 'Zend/tests','tests','sapi/cgi/tests','sapi/cli/tests'){Get-ChildItem "$workspace/source/$dir" -Recurse -File -Filter *.phpt})
        foreach($file in $sourceFiles) {
            $relative=[IO.Path]::GetRelativePath("$workspace/source",$file.FullName)
            if((Get-FileHash $file.FullName).Hash -ne (Get-FileHash (Join-Path $tests $relative)).Hash){throw "Changed PHPT: $relative"}
        }
        $xml=[xml](Get-Content $env:TEST_PHP_JUNIT -Raw)
        if($Arch -eq 'arm64' -and $Mode -eq 'full' -and $xml.SelectNodes('//testcase').Count -ne 6655){throw 'Incomplete core coverage'}
        @{sourceFilesVerified=$sourceFiles.Count;cases=$xml.SelectNodes('//testcase').Count;skips=$xml.SelectNodes('//testcase[skipped]').Count;failures=@($xml.SelectNodes('//testcase[failure or error]')|ForEach-Object OuterXml)}|ConvertTo-Json -Depth 5|Set-Content "$dest/review.json"
        Save-ProcessEvents "core-$iteration"
    }
    if($Mode -eq 'signals') {
        $exe="$build/phpbin/php.exe"
        $ini="$build/phpbin/php-test.ini"
        $signalSource=Get-Content "$tests/sapi/cli/tests/sapi_windows_set_ctrl_handler.phpt" -Raw
        $match=[regex]::Match($signalSource,'(?s)--FILE--\r?\n(.*?)\r?\n--EXPECTF--')
        if(-not $match.Success){throw 'Cannot extract unchanged console-control test'}
        $signalScript="$results/console-control.php"
        [IO.File]::WriteAllText($signalScript,$match.Groups[1].Value)
        $env:TEST_PHP_EXECUTABLE_ESCAPED='"'+$exe+'"'
        foreach($phase in 'baseline','console-control') {
            $args="-n -c `"$ini`" `"$workspace/diagnostics/cgi-trace.php`" `"$tests`" `"$results/calls-$phase.jsonl`""
            $process=Start-Process $exe -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput "$results/driver-$phase.out" -RedirectStandardError "$results/driver-$phase.err"
            if($phase -eq 'console-control') {
                $signalCount=0
                while(-not $process.HasExited -and $signalCount -lt 1000) {
                    $start=[DateTime]::UtcNow
                    $output=& $exe -n $signalScript 2>&1|Out-String
                    @{start=$start.ToString('o');end=[DateTime]::UtcNow.ToString('o');exit=$LASTEXITCODE;output=$output}|ConvertTo-Json -Compress|Add-Content "$results/signals.jsonl"
                    $signalCount++
                    $process.Refresh()
                }
            }
            if(-not $process.WaitForExit(600000)){throw 'CGI observation timed out'}
            $process.Refresh()
            $calls=@(Get-Content "$results/calls-$phase.jsonl"|ForEach-Object {$_|ConvertFrom-Json})
            $bad=@($calls|Where-Object {($_.output -replace "`r`n","`n") -cne "Interactive mode enabled`n`nNo input file specified.`n"})
            @{exit=$process.ExitCode;cases=$calls.Count;missingOutput=$bad.Count;failures=$bad}|ConvertTo-Json -Depth 6|Set-Content "$results/summary-$phase.json"
            Save-ProcessEvents $phase
            if($calls.Count -ne 4000){throw 'Incomplete CGI observations; inspect driver and process exits'}
        }
    }
} finally {
    foreach($kind in 'Start','Stop'){Unregister-Event -SourceIdentifier "Cgi$kind" -ErrorAction SilentlyContinue}
}
$global:LASTEXITCODE=0
