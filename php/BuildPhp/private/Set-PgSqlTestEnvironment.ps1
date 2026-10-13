function Set-PgSqlTestEnvironment {
    <#
    .SYNOPSIS
        Configure environment variables for PostgreSQL-related PHP tests and ensure the test database exists.
    #>
    [CmdletBinding()]
    param (
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch = 'x64'
    )
    process {
        $database = 'test'
        $hostName = '127.0.0.1'
        $port = 5432
        $env:PGUSER = 'postgres'
        $env:PGPASSWORD = 'Password12!'

        if ($Arch -eq 'arm64' -and -not (Test-Path pgsql_init)) {
            # The ARM runner has no PostgreSQL server. Run the x64 server separately from the ARM64 PHP client.
            $serverRoot = Join-Path $env:TEMP 'php-test-postgresql'
            New-Item -ItemType Directory -Path $serverRoot -Force | Out-Null
            $archive = Join-Path $serverRoot 'postgresql.zip'
            Get-File -Url 'https://get.enterprisedb.com/postgresql/postgresql-16.15-1-windows-x64-binaries.zip' -OutFile $archive
            Expand-Archive -LiteralPath $archive -DestinationPath $serverRoot -Force
            $env:PGBIN = Join-Path $serverRoot 'pgsql\bin'
            $data = Join-Path $serverRoot 'data'
            & "$env:PGBIN\initdb.exe" -D $data -U postgres --auth=trust --encoding=UTF8 --locale=C
            if ($LASTEXITCODE) { throw 'Could not initialize the PostgreSQL test server' }
            & "$env:PGBIN\pg_ctl.exe" -D $data -l "$serverRoot\server.log" -o '-h 127.0.0.1 -p 5432' -w start
            if ($LASTEXITCODE) { throw 'Could not start the PostgreSQL test server' }
            Set-Content -Path pgsql_init -Value 'initialized' -Encoding ASCII
        }

        if(-not(Test-Path pgsql_init)) {
            $service = Get-Service -Name "postgresql-x64-*" -ErrorAction SilentlyContinue |
                Sort-Object -Property @{ Expression = { if ($_.Name -match '^postgresql-x64-(\d+)$') { [int]$Matches[1] } else { 0 } } } -Descending |
                Select-Object -First 1
            if ($service) {
                Write-Host "Using PostgreSQL service $($service.Name)."
                Set-Service -Name $service.Name -StartupType manual -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                Start-Service -Name $service.Name -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
            } else {
                Write-Warning "No PostgreSQL service matching postgresql-x64-* was found."
            }
            Set-Content -Path pgsql_init -Value "initialized" -Encoding ASCII
        }

        if ($env:PGBIN) {
            $env:TMP_POSTGRESQL_BIN = $env:PGBIN
        }

        $psql = Join-Path $env:TMP_POSTGRESQL_BIN 'psql.exe'
        $createdb = Join-Path $env:TMP_POSTGRESQL_BIN 'createdb.exe'
        if (-not (Test-Path $psql)) {
            throw "psql.exe not found. Ensure PGBIN is set to PostgreSQL bin directory."
        }
        if (-not (Test-Path $createdb)) {
            throw "createdb.exe not found. Ensure PGBIN is set to PostgreSQL bin directory."
        }

        $connStr = "host=$hostName dbname=$database port=$port user=$($env:PGUSER) password=$($env:PGPASSWORD)"
        $env:PGSQL_TEST_CONNSTR = $connStr
        $env:PDO_PGSQL_TEST_DSN = "pgsql:host=$hostName port=$port dbname=$database user=$($env:PGUSER) password=$($env:PGPASSWORD)"

        if(-not(Test-Path pgsql_password_set)) {
            $prevPgPwd = $env:PGPASSWORD
            try {
                $env:PGPASSWORD = 'root'
                & $psql -U postgres -c "ALTER USER $($env:PGUSER) WITH PASSWORD '$prevPgPwd';"
            } finally {
                $env:PGPASSWORD = $prevPgPwd
            }
            Set-Content -Path pgsql_password_set -Value "password_set" -Encoding ASCII
        }

        if(-not(Test-Path pgsql_test_db_created)) {
            & $createdb $database
            Set-Content -Path pgsql_test_db_created -Value "test_db_created" -Encoding ASCII
        }
    }
}
