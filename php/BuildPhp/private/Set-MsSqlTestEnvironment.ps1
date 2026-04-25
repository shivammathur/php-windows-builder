function Set-MsSqlTestEnvironment {
    <#
    .SYNOPSIS
        Install Microsoft SQL Server Express required for SQL Server-related tests.
    #>
    [CmdletBinding()]
    param ()
    process {
        if(Test-Path mssql_init) {
            return
        }

        $serviceName = 'MSSQL$SQLEXPRESS'
        & choco install sql-server-express -y --no-progress --install-arguments="/SECURITYMODE=SQL /SAPWD=Password12!"
        if (@(0, 3010) -notcontains $LASTEXITCODE) {
            throw "Failed to install SQL Server Express. choco exited with $LASTEXITCODE."
        }

        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if (-not $service) {
            throw "SQL Server Express service $serviceName was not found."
        }

        Set-Service -Name $serviceName -StartupType Manual
        if ($service.Status -ne 'Running') {
            Start-Service -Name $serviceName
            $service = Get-Service -Name $serviceName
        }
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(120))
        Set-Content -Path mssql_init -Value "initialized" -Encoding ASCII
    }
}

