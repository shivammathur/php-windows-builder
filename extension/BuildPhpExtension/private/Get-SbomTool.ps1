function Get-SbomTool {
    <#
    .SYNOPSIS
        Resolve or securely download a pinned SBOM command-line tool.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('scancode', 'syft', 'vexctl')]
        [string] $Name,
        [PSCustomObject] $Configuration = (Get-SbomConfiguration -Name settings)
    )

    $overrideName = "SBOM_$($Name.ToUpperInvariant())_PATH"
    $override = [Environment]::GetEnvironmentVariable($overrideName)
    if($override) {
        if(-not(Test-Path -LiteralPath $override -PathType Leaf)) {
            throw "$overrideName points to missing file '$override'."
        }
        return (Resolve-Path -LiteralPath $override).Path
    }

    $toolProperty = $Configuration.tools.PSObject.Properties[$Name]
    if($null -eq $toolProperty) {
        throw "SBOM tool '$Name' is not configured."
    }
    $tool = $toolProperty.Value
    $toolDirectory = Join-Path ([IO.Path]::GetTempPath()) "pwbs-sbom\$Name-$($tool.version)"
    $executable = Join-Path $toolDirectory $tool.executable
    if(Test-Path -LiteralPath $executable -PathType Leaf) {
        return $executable
    }

    New-Item -Path $toolDirectory -ItemType Directory -Force | Out-Null
    $download = Join-Path $toolDirectory 'download'
    Get-File -Url $tool.url -OutFile $download
    $actualHash = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actualHash -ne ([string]$tool.sha256).ToLowerInvariant()) {
        Remove-Item -LiteralPath $download -Force
        throw "Checksum verification failed for $Name $($tool.version)."
    }

    if($tool.archive -eq 'zip') {
        Expand-Archive -LiteralPath $download -DestinationPath $toolDirectory -Force
        Remove-Item -LiteralPath $download -Force
    } else {
        Move-Item -LiteralPath $download -Destination $executable -Force
    }
    if(-not(Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "The $Name archive did not contain '$($tool.executable)'."
    }
    Unblock-File -LiteralPath $executable -ErrorAction SilentlyContinue
    return $executable
}
