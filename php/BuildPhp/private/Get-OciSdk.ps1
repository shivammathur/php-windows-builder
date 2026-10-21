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
        [string]$Arch,
        [string]$PhpVersion = ''
    )
    begin {
        $suffix = if ($Arch -eq 'x86') { 'nt' } else { 'windows' }
        $url = "https://download.oracle.com/otn_software/nt/instantclient/instantclient-sdk-$suffix.zip"
        if ($PhpVersion -match '^(5\.[3-6]|7\.[01])(\.|$)') {
            $suffix = if ($Arch -eq 'x86') { 'nt' } else { 'windows.x64' }
            $url = "https://download.oracle.com/otn_software/nt/instantclient/1932000/instantclient-sdk-$suffix-19.32.0.0.0dbru.zip"
        }
    }
    process {
        Get-File -Url $url -OutFile "instantclient-sdk.zip"
        Expand-Archive -Path "instantclient-sdk.zip" -DestinationPath "."
        Move-Item "instantclient_*" "instantclient"
    }
    end {
    }
}
