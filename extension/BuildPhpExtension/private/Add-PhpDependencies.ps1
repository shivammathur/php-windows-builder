Function Add-PhpDependencies {
    <#
    .SYNOPSIS
        Add PHP dependencies.
    .PARAMETER Config
        Configuration for the extension.
    #>
    [OutputType()]
    param(
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Configuration for the extension')]
        [PSCustomObject] $Config
    )
    begin {
    }
    process {
        if($Config.php_libraries.Count -ne 0) {
            Add-StepLog "Adding libraries (core)"
        }
        $stability = if ([string]::IsNullOrWhiteSpace($env:PHP_LIBS_STABILITY)) { 'stable' } else { $env:PHP_LIBS_STABILITY }
        $phpBaseUrl = 'https://downloads.php.net/~windows/php-sdk/deps'
        $phpTrunkBaseUrl = "https://downloads.php.net/~windows/php-sdk/deps/$($Config.vs_version)/$($Config.arch)"
        $phpSeries = $null
        $phpTrunk = $null
        New-Item -ItemType Directory -Force -Path "../deps" | Out-Null
        foreach ($library in $Config.php_libraries) {
            try {
                $artifact = Get-PhpLibraryArtifact -Config $Config -Library $library
                if ($null -ne $artifact) {
                    if ($artifact.Type -eq 'zip') {
                        $artifactExtract = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
                        try {
                            Expand-Archive -LiteralPath $artifact.Path -DestinationPath $artifactExtract -Force
                            $artifactRoot = $artifactExtract
                            if (-not ((Test-Path -LiteralPath (Join-Path $artifactRoot 'include')) -and (Test-Path -LiteralPath (Join-Path $artifactRoot 'lib')))) {
                                $candidateRoots = @(Get-ChildItem -LiteralPath $artifactExtract -Directory | Where-Object {
                                    (Test-Path -LiteralPath (Join-Path $_.FullName 'include')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'lib'))
                                })
                                if ($candidateRoots.Count -eq 1) {
                                    $artifactRoot = $candidateRoots[0].FullName
                                }
                            }
                            if (-not ((Test-Path -LiteralPath (Join-Path $artifactRoot 'include')) -and (Test-Path -LiteralPath (Join-Path $artifactRoot 'lib')))) {
                                throw "PHP dependency artifact $($artifact.Name) does not contain include and lib directories"
                            }
                            Copy-Item -Path (Join-Path $artifactRoot '*') -Destination "../deps" -Recurse -Force
                        } finally {
                            Remove-Item -LiteralPath $artifactExtract -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        Copy-Item -Path (Join-Path $artifact.Path '*') -Destination "../deps" -Recurse -Force
                    }
                    Add-BuildLog tick "$library" "Added $($artifact.Name) from artifacts"
                    continue
                }

                if ($null -eq $phpSeries) {
                    $phpSeries = Get-File -Url "$phpBaseUrl/series/packages-$($Config.php_version)-$($Config.vs_version)-$($Config.arch)-$stability.txt"
                }
                if ($null -eq $phpTrunk) {
                    $phpTrunk = Get-File -Url $phpTrunkBaseUrl
                }
                $matchesFound = $phpSeries.Content | Select-String -Pattern "(^|\n)$library.*"
                if ($matchesFound.Count -eq 0) {
                    foreach ($file in $phpTrunk.Links.Href) {
                        if ($file -match "^$library") {
                            $matchesFound = $file | Select-String -Pattern '.*'
                            break
                        }
                    }
                }
                if ($matchesFound.Count -eq 0) {
                    throw "Failed to find $library"
                }
                $file = $matchesFound.Matches[0].Value.Trim()
                $archive = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + '.zip')
                try {
                    Get-File -Url "$phpBaseUrl/$($Config.vs_version)/$($Config.arch)/$file" -OutFile $archive
                    Expand-Archive -LiteralPath $archive -DestinationPath "../deps" -Force
                } finally {
                    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
                }
                Add-BuildLog tick "$library" "Added $($file -replace '\.zip$')"
            } catch {
                Add-BuildLog cross "$library" "Failed to download $library"
                throw
            }
        }
    }
    end {
    }
}
