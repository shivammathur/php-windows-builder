function Read-SbomJson {
    <#
    .SYNOPSIS
        Read and validate a JSON document.
    #>
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "SBOM document '$Path' was not found."
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "SBOM document '$Path' is not valid JSON: $($_.Exception.Message)"
    }
}
