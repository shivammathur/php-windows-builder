function ConvertTo-SbomSlug {
    <#
    .SYNOPSIS
        Convert source metadata to an identifier-safe token.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $slug = ($Value.Trim() -replace '[^A-Za-z0-9.-]+', '-') -replace '^-+|-+$', ''
    if([string]::IsNullOrWhiteSpace($slug)) {
        return 'unknown'
    }
    return $slug
}
