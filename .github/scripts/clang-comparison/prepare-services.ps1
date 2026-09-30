param([string]$Runtime)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$metadata = Get-Content "$root/input/msvc/metadata.json" -Raw | ConvertFrom-Json
$arch = $metadata.arch
$qa = New-Item "$root/qa-services" -ItemType Directory -Force
$platform = if ($arch -eq 'x86') { 'Win32' } else { 'x64' }
# Use the same Firebird fixture as php-src's Windows CI.
Invoke-WebRequest "https://github.com/FirebirdSQL/firebird/releases/download/v4.0.4/Firebird-4.0.4.3010-0-$platform.zip" -OutFile "$qa/firebird.zip"
Expand-Archive "$qa/firebird.zip" "$qa/firebird"
$fb = "$qa/firebird"
$env:Path = "$fb;$Runtime;$env:Path"
$env:PDO_FIREBIRD_TEST_DATABASE = "$qa/test.fdb"
$env:PDO_FIREBIRD_TEST_DSN = "firebird:dbname=127.0.0.1:$env:PDO_FIREBIRD_TEST_DATABASE"
$env:PDO_FIREBIRD_TEST_USER = 'SYSDBA'
$env:PDO_FIREBIRD_TEST_PASS = 'phpfi'
"create database '$env:PDO_FIREBIRD_TEST_DATABASE' user 'SYSDBA' password 'phpfi';" | Set-Content "$qa/setup.sql" -Encoding ascii
"create user SYSDBA password 'phpfi';`ncommit;" | Set-Content "$qa/create-user.sql" -Encoding ascii
& "$fb/instsvc.exe" install -n TestInstance
if ($LASTEXITCODE -ne 0) { throw 'Firebird service installation failed' }
& "$fb/isql.exe" -q -i "$qa/setup.sql"
if ($LASTEXITCODE -ne 0) { throw 'Firebird database setup failed' }
& "$fb/isql.exe" -q -i "$qa/create-user.sql" -user sysdba $env:PDO_FIREBIRD_TEST_DATABASE
if ($LASTEXITCODE -ne 0) { throw 'Firebird test user setup failed' }
& "$fb/instsvc.exe" start -n TestInstance
if ($LASTEXITCODE -ne 0) { throw 'Firebird service startup failed' }

# Match the net-snmp package recorded in the tested artifact's SBOM.
$sbom = Get-Content (Get-ChildItem "$root/input/msvc/*.cdx.json").FullName -Raw | ConvertFrom-Json
$component = $sbom.components | Where-Object name -eq 'net-snmp'
$url = ($component.externalReferences | Where-Object type -eq 'distribution').url
if (-not $url.StartsWith('https://downloads.php.net/~windows/php-sdk/deps/')) { throw 'Unexpected SNMP fixture source' }
Invoke-WebRequest $url -OutFile "$qa/snmp.zip"
Expand-Archive "$qa/snmp.zip" "$qa/snmp"
$env:MIBDIRS = "$qa/snmp/share/mibs"
$env:SNMP_MIBDIR = $env:MIBDIRS
$config = Get-Content "$root/source/ext/snmp/tests/snmpd.conf" -Raw
$config = $config -replace 'exec HexTest .*', "exec HexTest cscript.exe /nologo $($root.Replace('\','/'))/source/ext/snmp/tests/bigtest.js"
Set-Content "$qa/snmpd.conf" $config -Encoding ascii
$server = Start-Process "$qa/snmp/bin/snmpd.exe" -ArgumentList @('-C','-c',"$qa/snmpd.conf",'-Ln') -PassThru -RedirectStandardOutput "$root/regressions/snmp-server.log" -RedirectStandardError "$root/regressions/snmp-server-errors.log"
if ($server.WaitForExit(1000)) { throw "SNMP fixture exited: $($server.ExitCode)" }
$env:VALIDATION_EXTERNAL_DEPS = '1'
@{firebird=@{user='SYSDBA';password='phpfi';dsn=$env:PDO_FIREBIRD_TEST_DSN};snmp=@{pid=$server.Id;readCommunity='public';writeCommunity='private';testPassword='test1234';mibs=$env:MIBDIRS}} | ConvertTo-Json -Depth 4 | Set-Content "$root/regressions/qa-fixtures.json"
