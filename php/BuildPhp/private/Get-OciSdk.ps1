function Get-OciSdk {
    <#
    .SYNOPSIS
        Add the OCI SDK for building oci and pdo_oci extensions

    .PARAMETER Arch
        The architecture of the OCI sdk.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The architecture of the OCI sdk.')]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,
        [string]$PhpVersion = ''
    )
    begin {
        $config = Get-Content (Join-Path $PSScriptRoot '..\config\oci.json') -Raw | ConvertFrom-Json
        $series = [regex]::Match($PhpVersion, '^\d+\.\d+').Value
        $sdk = if ($config.sdk.legacy.series -contains $series) { $config.sdk.legacy } else { $config.sdk.default }
        $url = $config.sdk.baseUrl + $sdk.$Arch
    }
    process {
        Get-File -Url $url -OutFile "instantclient-sdk.zip"
        Expand-Archive -Path "instantclient-sdk.zip" -DestinationPath "."
        Move-Item "instantclient_*" "instantclient"
    }
    end {
    }
}
