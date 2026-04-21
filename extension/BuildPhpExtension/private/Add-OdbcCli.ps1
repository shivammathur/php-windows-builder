Function Add-OdbcCli {
    <#
    .SYNOPSIS
        Add sdk for DB2 extension.
    .PARAMETER Config
        Configuration for the extension.
    #>
    [OutputType()]
    param(
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Configuration for the extension')]
        [PSCustomObject] $Config
    )
    begin {
    }
    process {
        $prefix = if ($Config.arch -eq "x86") {"nt32"} else {"ntx64"}
        if ($Config.arch -eq 'arm64') {
            Write-Warning 'IBM DB2 does not publish a dedicated ARM64 CLI package here yet. Falling back to the x64 package.'
        }
        $url = "https://public.dhe.ibm.com/ibmdl/export/pub/software/data/db2/drivers/odbc_cli/${prefix}_odbc_cli.zip"
        Get-File -Url $url -OutFile "odbc_cli.zip"
        Expand-Archive -Path "odbc_cli.zip" -DestinationPath "../deps"
        Copy-Item ../deps/clidriver/* -Destination "../deps" -Recurse -Force
    }
    end {
    }
}
