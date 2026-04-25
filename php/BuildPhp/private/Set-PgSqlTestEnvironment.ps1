function Set-PgSqlTestEnvironment {
    <#
    .SYNOPSIS
        Configure environment variables for PostgreSQL-related PHP tests and ensure the test database exists.
    #>
    [CmdletBinding()]
    param ()
    process {
        $database = 'test'
        $hostName = '127.0.0.1'
        $port = 5432
        $env:PGUSER = 'postgres'
        $env:PGPASSWORD = 'Password12!'

        if(-not(Test-Path pgsql_init)) {
            Set-Service -Name "postgresql-x64-14" -StartupType manual -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Start-Service -Name "postgresql-x64-14" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $service = Get-Service -Name "postgresql-x64-14" -ErrorAction SilentlyContinue
            if ($service) {
                $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
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
