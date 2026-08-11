function Get-SbomConfiguration {
    <#
    .SYNOPSIS
        Read an SBOM setting or document template.
    #>
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('settings')]
        [string] $Name
    )

    $path = Join-Path $PSScriptRoot "..\config\sbom\$Name.json"
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "SBOM configuration '$path' was not found."
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}
