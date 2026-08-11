function Get-ExtensionSbomDependencies {
    <#
    .SYNOPSIS
        Discover SBOM and OpenVEX documents produced by extension dependency builds.
    #>
    [OutputType([PSCustomObject])]
    param ()

    $directory = Join-Path (Get-Location).Path '..\deps\share\sbom'
    if(-not(Test-Path -LiteralPath $directory -PathType Container)) {
        return [PSCustomObject][ordered]@{
            sbomFiles = @()
            openVexFiles = @()
        }
    }
    $cycloneDxFiles = @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.cdx.json' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)
    $spdxFiles = @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.spdx.json' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)
    $openVexFiles = @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.openvex.json' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)

    $cycloneDxFiles = @($cycloneDxFiles | Sort-Object -Unique)
    $cycloneDxNames = @{}
    foreach($file in $cycloneDxFiles) {
        $cycloneDxNames[([IO.Path]::GetFileName($file) -replace '\.cdx\.json$', '').ToLowerInvariant()] = $true
    }
    $spdxOnlyFiles = @($spdxFiles | Sort-Object -Unique | Where-Object {
        $name = ([IO.Path]::GetFileName($_) -replace '\.spdx\.json$', '').ToLowerInvariant()
        -not($cycloneDxNames.ContainsKey($name))
    })

    return [PSCustomObject][ordered]@{
        sbomFiles = @($cycloneDxFiles) + @($spdxOnlyFiles)
        openVexFiles = @($openVexFiles | Sort-Object -Unique)
    }
}
