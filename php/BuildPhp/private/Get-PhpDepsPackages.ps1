function Get-PhpDepsPackages {
    <#
    .SYNOPSIS
        Get PHP dependency packages, applying configured library overrides when required.
    .PARAMETER PhpVersion
        PHP version (e.g., 8.4.18, 8.4, or master).
    .PARAMETER VsVersion
        Visual Studio toolset version (e.g., vs16, vs17).
    .PARAMETER Arch
        Target architecture: x86, x64, or arm64.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $PhpVersion,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $VsVersion,
        [Parameter(Mandatory=$true)]
        [ValidateSet('x86','x64','arm64')]
        [string] $Arch
    )

    begin {
        $baseurl = 'https://downloads.php.net/~windows/php-sdk/deps'
        $configPath = Join-Path $PSScriptRoot '..\config\deps-overrides.json'
    }

    process {
        $depsPhpVersion = $PhpVersion
        if ($PhpVersion -ne 'master') {
            $versionParts = $PhpVersion.Split('.')
            if ($versionParts.Count -ge 2) {
                $depsPhpVersion = $versionParts[0..1] -join '.'
            }
        }

        $downloadArch = $Arch
        $series = $null
        $packages = @()
        $candidateArchs = @($Arch)
        if ($Arch -eq 'arm64') {
            $candidateArchs += 'x64'
        }

        foreach ($candidateArch in ($candidateArchs | Select-Object -Unique)) {
            $seriesUrl = "$baseurl/series/packages-$depsPhpVersion-$VsVersion-$candidateArch-staging.txt"
            Write-Host "Fetching series listing: $seriesUrl"
            try {
                $candidateSeries = Invoke-WebRequest -Uri $seriesUrl -UseBasicParsing -ErrorAction Stop
                $candidatePackages = @()
                if ($candidateSeries -and $candidateSeries.Content) {
                    $candidatePackages = $candidateSeries.Content -split "[\r\n]+" | Where-Object { $_ -and $_.Trim().Length -gt 0 }
                }

                if ($candidatePackages.Count -eq 0) {
                    continue
                }

                $downloadArch = $candidateArch
                $series = $candidateSeries
                $packages = $candidatePackages
                break
            } catch {
                if ($candidateArch -eq $candidateArchs[-1]) {
                    throw
                }
            }
        }

        if (-not $series) {
            throw "Failed to fetch dependency series for PHP $depsPhpVersion ($VsVersion, $Arch)."
        }

        $overrideLibraries = @()
        if ((Test-Path -LiteralPath $configPath) -and $PhpVersion -match '^\d+\.\d+\.\d+$') {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $seriesConfigProperty = $config.PSObject.Properties[$depsPhpVersion]
            if ($null -ne $seriesConfigProperty) {
                $seriesConfig = $seriesConfigProperty.Value
                if ([version]$PhpVersion -le [version]$seriesConfig.maxVersion) {
                    foreach ($libraryProperty in $seriesConfig.libraries.PSObject.Properties) {
                        $libraryName = $libraryProperty.Name
                        $overrideConfig = $libraryProperty.Value
                        $package = $null
                        if ($overrideConfig -is [string]) {
                            $package = "$libraryName-$overrideConfig-$VsVersion-$downloadArch.zip"
                        } elseif ($overrideConfig.PSObject.Properties.Name -contains 'package') {
                            $package = $overrideConfig.package
                        } elseif ($overrideConfig.PSObject.Properties.Name -contains 'version') {
                            $package = "$libraryName-$($overrideConfig.version)-$VsVersion-$downloadArch.zip"
                        }

                        if ([string]::IsNullOrWhiteSpace($package)) {
                            continue
                        }

                        $overrideLibraries += $libraryName
                        $packagePattern = '^' + [regex]::Escape($libraryName) + '-\d'
                        $packages = $packages | ForEach-Object {
                            if ($_ -match $packagePattern) {
                                $package
                            } else {
                                $_
                            }
                        }

                        if (-not ($packages -contains $package)) {
                            $packages += $package
                        }
                    }
                }
            }
        }

        return [PSCustomObject]@{
            Packages = @($packages)
            OverrideLibraries = @($overrideLibraries | Select-Object -Unique)
            DownloadArch = $downloadArch
        }
    }
}
