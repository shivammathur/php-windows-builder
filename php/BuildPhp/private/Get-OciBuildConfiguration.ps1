function Get-OciBuildConfiguration {
    <#
    .SYNOPSIS
        Get the OCI build configuration for a PHP version.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $true)]
        [string] $SdkDirectory
    )

    $config = Get-Content (Join-Path $PSScriptRoot '..\config\oci.json') -Raw | ConvertFrom-Json
    $majorMinor = [regex]::Match($PhpVersion, '^\d+\.\d+').Value
    $options = $config.extensions | Where-Object { $_.series -contains $majorMinor }
    if ($options) {
        $sdkPath = (Resolve-Path -LiteralPath $SdkDirectory -ErrorAction Stop).Path
        foreach ($file in @('include\oci.h', 'lib\msvc\oci.lib')) {
            if (-not (Test-Path -LiteralPath (Join-Path $sdkPath $file) -PathType Leaf)) {
                throw "OCI SDK file not found: $sdkPath\$file"
            }
        }
        $options.names | ForEach-Object { '"--with-{0}={1},shared"' -f $_, $sdkPath }
    }
}
