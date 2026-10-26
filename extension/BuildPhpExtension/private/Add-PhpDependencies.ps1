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
        $phpBaseUrl = 'https://downloads.php.net/~windows/php-sdk/deps'
        $phpTrunkBaseUrl = "https://downloads.php.net/~windows/php-sdk/deps/$($Config.vs_version)/$($Config.arch)"
        $phpSeries = Get-File -Url "$phpBaseUrl/series/packages-$($Config.php_version)-$($Config.vs_version)-$($Config.arch)-stable.txt"
        $phpTrunk = Get-File -Url $phpTrunkBaseUrl
        foreach ($library in $Config.php_libraries) {
            try {
                $matchesFound = $phpSeries.Content | Select-String -Pattern "(^|\n)$library.*"
                if ($matchesFound.Count -eq 0) {
                    $libraryPattern = '^' + [regex]::Escape($library) + '-\d.*-(?:' + $Config.vs_version + '|nocrt)-' + $Config.arch + '\.zip$'
                    $matchesFound = $phpTrunk.Links.Href |
                        Where-Object { $_ -match $libraryPattern } |
                        Sort-Object -Property {
                            $version = $_ -replace '^.*?-(?=\d)', '' -replace '-(?:vc\d+|vs\d+|nocrt)-[^-]+\.zip$', ''
                            # Compare numeric version and rebuild components without losing letter or patch suffixes.
                            [regex]::Replace($version, '\d+', { param($number) $number.Value.PadLeft(20, '0') })
                        } -Descending |
                        Select-Object -First 1 |
                        Select-String -Pattern '.*'
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
