function Set-FirebirdTestEnvironment {
    <#
    .SYNOPSIS
        Configure Firebird for PDO_Firebird tests on Windows.
    .PARAMETER Arch
        PHP architecture.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position=0, HelpMessage='PHP architecture')]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch = 'x64'
    )
    process {
        if ($Arch -eq 'arm64') {
            # Run the x64 server separately; PHP requires a native client DLL.
            Set-FirebirdTestEnvironment -Arch x64
            $client = 'C:\Firebird-arm64'
            $archive = Join-Path $env:TEMP 'firebird-arm64.zip'
            Get-File -Url 'https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.2190-0-1d6051b-windows-arm64.zip' -OutFile $archive
            if ((Get-FileHash $archive).Hash -ne '5BB0D4B013F3BE3A03B2F56BC180A77FD6CB2777BEC34D51490A7C715AA92ADA') {
                throw 'Unexpected Firebird ARM64 client archive'
            }
            Expand-Archive -LiteralPath $archive -DestinationPath $client -Force
            Add-Path $client
            return
        }
        $destDir = "C:\Firebird-$Arch"
        $firebirdVersion = 'v4.0.4'
        $firebirdRelease = "https://github.com/FirebirdSQL/firebird/releases/download/$firebirdVersion"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null

        $url = if ($Arch -eq 'x64') {
            "$firebirdRelease/Firebird-4.0.4.3010-0-x64.zip"
        } else {
            "$firebirdRelease/Firebird-4.0.4.3010-0-Win32.zip"
        }

        $zipPath = Join-Path $destDir 'Firebird.zip'
        Get-File -Url $url -OutFile $zipPath

        try {
            Expand-Archive -LiteralPath $zipPath -DestinationPath $destDir -Force
        } catch {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destDir)
        }

        $env:PDO_FIREBIRD_TEST_DATABASE = "C:\test-$Arch.fdb"
        $env:PDO_FIREBIRD_TEST_DSN      = "firebird:dbname=127.0.0.1:$($env:PDO_FIREBIRD_TEST_DATABASE)"
        $env:PDO_FIREBIRD_TEST_USER     = 'SYSDBA'
        $env:PDO_FIREBIRD_TEST_PASS     = 'phpfi'
        $serviceName = "PHPTestFirebird$Arch"

        $createUserSql = Join-Path $destDir 'create_user.sql'
        Set-Content -Path $createUserSql -Value "create user $($env:PDO_FIREBIRD_TEST_USER) password '$($env:PDO_FIREBIRD_TEST_PASS)';" -Encoding ASCII
        Add-Content -Path $createUserSql -Value 'commit;' -Encoding ASCII

        $setupSql = Join-Path $destDir 'setup.sql'
        Set-Content -Path $setupSql -Value "create database '$($env:PDO_FIREBIRD_TEST_DATABASE)' user '$($env:PDO_FIREBIRD_TEST_USER)' password '$($env:PDO_FIREBIRD_TEST_PASS)';" -Encoding ASCII
        if(-not(Test-Path pdo_firebird_db_created)) {
            if (Test-Path -LiteralPath $env:PDO_FIREBIRD_TEST_DATABASE) {
                Remove-Item -LiteralPath $env:PDO_FIREBIRD_TEST_DATABASE -Force
            }
            & (Join-Path $destDir 'instsvc.exe') install -n $serviceName | Out-Null
            & (Join-Path $destDir 'isql') -q -i $setupSql | Out-Null
            & (Join-Path $destDir 'isql') -q -i $createUserSql -user sysdba $env:PDO_FIREBIRD_TEST_DATABASE | Out-Null
            & (Join-Path $destDir 'instsvc.exe') start -n $serviceName | Out-Null
            Set-Content -Path pdo_firebird_db_created -Value "db_created" -Encoding ASCII
        }

        Add-Path $destDir
    }
}
