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
        $phpSeries = Get-File -Url "$phpBaseUrl/series/packages-$($Config.php_version)-$($Config.vs_version)-$($Config.arch)-$stability.txt"
        $phpTrunk = Get-File -Url $phpTrunkBaseUrl
        foreach ($library in $Config.php_libraries) {
            try {
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
