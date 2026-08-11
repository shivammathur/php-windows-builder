function Write-SbomJson {
    <#
    .SYNOPSIS
        Write a JSON document as UTF-8 without a byte-order mark.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $directory = Split-Path -Path $Path -Parent
    if(-not(Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    $json = $InputObject | ConvertTo-Json -Depth 100
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $encoding)
}
