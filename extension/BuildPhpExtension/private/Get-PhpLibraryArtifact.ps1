function Get-PhpLibraryArtifact {
    <#
    .SYNOPSIS
        Get a PHP dependency artifact from local artifact directories.
    .PARAMETER Config
        Extension configuration.
    .PARAMETER Library
        PHP dependency library name.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Configuration for the extension')]
        [PSCustomObject] $Config,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP dependency library name')]
        [string] $Library
    )
    begin {
    }
    process {
        $artifactPaths = @()
        foreach ($path in @($env:PHP_LIBS_ARTIFACT_PATH, $env:PHP_BUILD_ARTIFACT_PATH)) {
            if (-not [string]::IsNullOrWhiteSpace($path) -and $artifactPaths -notcontains $path) {
                $artifactPaths += $path
            }
        }

        if ($artifactPaths.Count -eq 0) {
            return $null
        }

        $libraryName = ($Library -split '-')[0].ToLowerInvariant()
        $namePattern = "^$([regex]::Escape($libraryName))(?:[-_].*)?-$([regex]::Escape($Config.vs_version))-$([regex]::Escape($Config.arch))(?:\.zip)?$"

        foreach ($artifactPath in $artifactPaths) {
            if (-not (Test-Path -LiteralPath $artifactPath)) {
                throw "PHP library artifact path does not exist: $artifactPath"
            }

            $zipMatches = @(Get-ChildItem -LiteralPath $artifactPath -Recurse -File -Filter "$libraryName*.zip" | Where-Object {
                $_.Name.ToLowerInvariant() -match $namePattern
            })
            if ($zipMatches.Count -gt 1) {
                $found = ($zipMatches | ForEach-Object FullName) -join ', '
                throw "Expected one $Library artifact zip matching $namePattern, found $($zipMatches.Count): $found"
            }
            if ($zipMatches.Count -eq 1) {
                return [PSCustomObject]@{
                    Type = 'zip'
                    Path = $zipMatches[0].FullName
                    Name = $zipMatches[0].Name -replace '\.zip$', ''
                }
            }

            $directoryMatches = @(Get-ChildItem -LiteralPath $artifactPath -Recurse -Directory | Where-Object {
                $_.Name.ToLowerInvariant() -match $namePattern -and (Test-Path -LiteralPath (Join-Path $_.FullName 'include')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'lib'))
            })
            if ($directoryMatches.Count -gt 1) {
                $found = ($directoryMatches | ForEach-Object FullName) -join ', '
                throw "Expected one $Library artifact directory matching $namePattern, found $($directoryMatches.Count): $found"
            }
            if ($directoryMatches.Count -eq 1) {
                return [PSCustomObject]@{
                    Type = 'directory'
                    Path = $directoryMatches[0].FullName
                    Name = $directoryMatches[0].Name
                }
            }

            if ((Test-Path -LiteralPath (Join-Path $artifactPath 'include')) -and (Test-Path -LiteralPath (Join-Path $artifactPath 'lib'))) {
                $libraryFile = Get-ChildItem -LiteralPath (Join-Path $artifactPath 'lib') -File -Filter '*.lib' | Where-Object {
                    $_.Name.ToLowerInvariant() -match "^$([regex]::Escape($libraryName))(_a)?\.lib$" -or
                    ($libraryName -eq 'zlib' -and $_.Name.ToLowerInvariant() -match '^zlib(_a)?\.lib$')
                } | Select-Object -First 1
                if ($null -ne $libraryFile) {
                    return [PSCustomObject]@{
                        Type = 'directory'
                        Path = $artifactPath
                        Name = (Split-Path -Leaf $artifactPath)
                    }
                }
            }
        }

        return $null
    }
    end {
    }
}
