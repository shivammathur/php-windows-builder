param([ValidateSet('x64','arm64')][string]$Arch)
$ErrorActionPreference='Stop'
$workspace=(Get-Location).Path
if((git -C source rev-parse HEAD) -ne '74523757b112babd04515feb8cfac4e531bf6add'){throw 'PHP source moved'}
$release=(Get-Content diagnostics/windows-releases.json -Raw|ConvertFrom-Json).'8.4'.'nts-vs17-x64'
if($Arch -eq 'x64'){
    foreach($kind in 'zip','devel_pack'){
        $p=$release.$kind
        Invoke-WebRequest "https://downloads.php.net/~windows/releases/$($p.path)" -OutFile "$kind.zip"
        if((Get-FileHash "$kind.zip").Hash -ne $p.sha256){throw 'Published package changed'}
    }
    Expand-Archive zip.zip phpbin
    Expand-Archive devel_pack.zip dev
    $clientUrl='https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.2210-0-5976482-windows-x64.zip'
    $clientHash='46c9e139e248895b1c101353a3d907bce4725ff4851ef60c2ea1d9704edf2073'
}else{
    Expand-Archive artifacts/php-8.4.28-dev-nts-Win32-vs17-arm64.zip phpbin
    Expand-Archive artifacts/php-devel-pack-8.4.28-dev-nts-Win32-vs17-arm64.zip dev
    $clientUrl='https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.2190-0-1d6051b-windows-arm64.zip'
    $clientHash='5bb0d4b013f3be3a03b2f56bc180a77fd6cb2777bec34d51490a7c715aa92ada'
}
Invoke-WebRequest $clientUrl -OutFile client.zip
if((Get-FileHash client.zip).Hash -ne $clientHash){throw 'Client package changed'}
Expand-Archive client.zip client
$dev=@(Get-ChildItem dev -Directory)
if($dev.Count -ne 1){throw 'Unexpected development pack'}
$include=Join-Path $dev[0].FullName include
$phpLib=Join-Path $dev[0].FullName lib/php8.lib
$exe=Join-Path $workspace phpbin/php.exe
$env:PATH="$workspace/client;$workspace/phpbin;$env:PATH"
$env:TEST_PHP_EXECUTABLE=$exe
$env:NO_INTERACTION='1';$env:REPORT_EXIT_STATUS='1'
$env:PDO_FIREBIRD_TEST_DSN='firebird:dbname=127.0.0.1:unused'
if(Test-Path phpbin/fbclient.dll){throw 'Unexpected bundled client'}
$original=[IO.File]::ReadAllText("$workspace/source/ext/pdo_firebird/firebird_statement.c")
$change="`t} else {`n`t`tZVAL_EMPTY_STRING(result);`n`t}"
$original=$original.Replace("`r`n","`n")
if([regex]::Matches($original,[regex]::Escape($change)).Count -ne 1){throw 'Upstream empty-BLOB change not found exactly once'}
$files=@('pdo_firebird.c','firebird_driver.c','firebird_statement.c','pdo_firebird_utils.cpp')
$flags=@('/nologo','/MD','/O2','/EHsc','/guard:cf','/Zc:preprocessor','/Zc:__cplusplus','/D','_WINDOWS','/D','WINDOWS=1','/D','ZEND_WIN32=1','/D','PHP_WIN32=1','/D','WIN32','/D','ZEND_COMPILE_DL_EXT=1','/D','COMPILE_DL_PDO_FIREBIRD','/D','PDO_FIREBIRD_EXPORTS=1','/D','ZEND_DEBUG=0','/D','HAVE_IBASE_H=1','/D','HAVE_FIREBIRD_INTERFACE_H=1')
foreach($dir in @($include,"$include/main","$include/Zend","$include/TSRM","$include/ext","$workspace/fbdeps/include/interbase","$workspace/source/ext/pdo_firebird")){
    if(-not(Test-Path $dir)){throw "Missing header directory $dir"}
    $flags+=@('/I',$dir)
}
if(-not(Test-Path $phpLib) -or -not(Test-Path fbdeps/lib/fbclient_ms.lib)){throw 'Missing import library'}
$records=@()
foreach($mode in 'before-upstream-change','current-source'){
    $dir=Join-Path $workspace $mode
    New-Item $dir -ItemType Directory|Out-Null
    foreach($file in $files){Copy-Item "source/ext/pdo_firebird/$file" $dir}
    $content=if($mode -eq 'before-upstream-change'){$original.Replace($change,"`t}")}else{$original}
    [IO.File]::WriteAllText("$dir/firebird_statement.c",$content)
    Set-Location $dir
    try{
        & cl @flags /c @files 2>&1|Tee-Object "$workspace/firebird-$mode-compile.log"
        if($LASTEXITCODE){throw 'Cannot compile control extension'}
        $objects=@($files|ForEach-Object{[IO.Path]::ChangeExtension($_,'.obj')})
        & link /nologo /dll /out:php_pdo_firebird.dll @objects $phpLib "$workspace/fbdeps/lib/fbclient_ms.lib" kernel32.lib ole32.lib user32.lib advapi32.lib shell32.lib ws2_32.lib Dnsapi.lib psapi.lib bcrypt.lib 2>&1|Tee-Object "$workspace/firebird-$mode-link.log"
        if($LASTEXITCODE){throw 'Cannot link control extension'}
        Copy-Item php_pdo_firebird.dll "$workspace/phpbin/ext/php_pdo_firebird.dll" -Force
    }finally{Set-Location $workspace}
    & $exe -n -d "extension_dir=$workspace/phpbin/ext" -d extension=pdo_firebird -r 'if (!extension_loaded("pdo_firebird")) exit(1); echo PHP_VERSION," ",phpversion("pdo_firebird"),"\n";'
    if($LASTEXITCODE){throw 'Control extension cannot load'}
    $env:TEST_PHP_JUNIT="$workspace/firebird-$mode.xml"
    Set-Location source
    try{
        & $exe -n run-tests.php -p $exe -n -d "extension_dir=$workspace/phpbin/ext" --offline --show-diff --no-progress -q ext/pdo_firebird/tests/bug_76452.phpt 2>&1|Tee-Object "$workspace/firebird-$mode.log"
        $exit=$LASTEXITCODE
    }finally{Set-Location $workspace}
    $xml=[xml](Get-Content "firebird-$mode.xml" -Raw)
    if($xml.SelectNodes('//testcase').Count -ne 1 -or $xml.SelectNodes('//testcase[skipped]').Count){throw 'Control case did not execute'}
    $records+=@{mode=$mode;exit=$exit;failures=@($xml.SelectNodes('//testcase[failure or error]')|ForEach-Object{$_.OuterXml});dllHash=(Get-FileHash "$dir/php_pdo_firebird.dll").Hash}
}
@{arch=$Arch;source=(git -C source rev-parse HEAD);client=$clientUrl;clientHash=$clientHash;results=$records}|ConvertTo-Json -Depth 6|Set-Content firebird-results.json
