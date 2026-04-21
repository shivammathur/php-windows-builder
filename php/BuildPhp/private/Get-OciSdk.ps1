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
        [string]$Arch
    )
    begin {
        $suffix = if ($Arch -eq 'x86') { 'nt' } else { 'windows' }
        $url = "https://download.oracle.com/otn_software/nt/instantclient/instantclient-sdk-$suffix.zip"
    }
    process {
        if ($Arch -eq 'arm64') {
            Write-Warning 'Oracle does not publish a dedicated ARM64 Instant Client SDK package here yet. Falling back to the x64 package.'
        }
        Get-File -Url $url -OutFile "instantclient-sdk.zip"
        Expand-Archive -Path "instantclient-sdk.zip" -DestinationPath "."
        Move-Item "instantclient_*" "instantclient"
    }
    end {
    }
}
