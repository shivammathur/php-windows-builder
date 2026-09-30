param([string]$Runtime)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$metadata = Get-Content "$root/input/msvc/metadata.json" -Raw | ConvertFrom-Json
$arch = $metadata.arch
$qa = New-Item "$root/qa-services" -ItemType Directory -Force
$credentials = @{}
if ($env:VALIDATION_DATABASE_SERVICES -eq 'true') {
    $env:MYSQL_PWD = $env:MYSQL_TEST_PASSWD = $env:PDO_MYSQL_TEST_PASS = 'Password12!'
    $env:MYSQL_TEST_USER = $env:PDO_MYSQL_TEST_USER = 'root'
    $env:MYSQL_TEST_HOST = $env:PDO_MYSQL_TEST_HOST = '127.0.0.1'
    $env:MYSQL_TEST_PORT = $env:PDO_MYSQL_TEST_PORT = '3306'
    $env:PDO_MYSQL_TEST_DSN = 'mysql:host=127.0.0.1;port=3306;dbname=test'
    & mysql --host=127.0.0.1 --port=3306 --user=root -e 'CREATE DATABASE IF NOT EXISTS test'
    if ($LASTEXITCODE -ne 0) { throw 'MySQL test database setup failed' }
    $env:PGUSER = 'postgres'
    $env:PGPASSWORD = 'Password12!'
    $env:PGSQL_TEST_CONNSTR = 'host=127.0.0.1 dbname=test port=5432 user=postgres password=Password12!'
    $env:PDO_PGSQL_TEST_DSN = 'pgsql:host=127.0.0.1 port=5432 dbname=test user=postgres password=Password12!'
    & "$env:PGBIN/createdb.exe" test
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL test database setup failed' }
    $env:ODBC_TEST_USER = $env:PDO_ODBC_TEST_USER = 'sa'
    $env:ODBC_TEST_PASS = $env:PDO_ODBC_TEST_PASS = 'Password12!'
    $env:ODBC_TEST_DSN = 'Driver={ODBC Driver 17 for SQL Server};Server=(local)\SQLEXPRESS;Database=master;uid=sa;pwd=Password12!'
    $env:PDO_ODBC_TEST_DSN = "odbc:$env:ODBC_TEST_DSN"
    $credentials.mysql = @{user='root';password='Password12!';dsn=$env:PDO_MYSQL_TEST_DSN}
    $credentials.postgresql = @{user='postgres';password='Password12!';dsn=$env:PDO_PGSQL_TEST_DSN}
    $credentials.sqlserver = @{user='sa';password='Password12!';dsn=$env:PDO_ODBC_TEST_DSN}
}
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
$env:VALIDATION_EXTERNAL_DEPS = '1'
$credentials.firebird = @{user='SYSDBA';password='phpfi';dsn=$env:PDO_FIREBIRD_TEST_DSN}
$credentials.snmp = @{readCommunity='public';writeCommunity='private';testPassword='test1234';mibs=$env:MIBDIRS}
$credentials | ConvertTo-Json -Depth 4 | Set-Content "$root/regressions/qa-fixtures.json"
