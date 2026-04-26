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
        $installExitCode = $null
        for($attempt = 1; $attempt -le 3; $attempt++) {
            Write-Host "Installing SQL Server Express (attempt $attempt of 3)..."
            & choco install sql-server-express -y --no-progress --install-arguments="/SECURITYMODE=SQL /SAPWD=Password12!"
            $installExitCode = $LASTEXITCODE
            if (@(0, 3010) -contains $installExitCode) {
                break
            }

            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                break
            }

            if ($attempt -lt 3) {
                Start-Sleep -Seconds (15 * $attempt)
            }
        }
        if (@(0, 3010) -notcontains $installExitCode -and -not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
            throw "Failed to install SQL Server Express. choco exited with $installExitCode."
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

