function Get-PhpArtifactZip {
    <#
    .SYNOPSIS
        Get a PHP runtime or devel zip from a local artifact directory.
    .PARAMETER Config
        Extension Configuration
    .PARAMETER Kind
        PHP artifact kind.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Configuration for the extension')]
        [PSCustomObject] $Config,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP artifact kind')]
        [ValidateSet('runtime', 'devel')]
        [string] $Kind
    )
    begin {
    }
    process {
        $artifactPath = $env:PHP_BUILD_ARTIFACT_PATH
        if ([string]::IsNullOrWhiteSpace($artifactPath)) {
            return $null
        }
        if (-not(Test-Path -LiteralPath $artifactPath)) {
            throw "PHP build artifact path does not exist: $artifactPath"
        }

        $tsPart = if ($Config.ts -eq "nts") { "nts-Win32" } else { "Win32" }
        $prefix = if ($Kind -eq 'devel') { "php-devel-pack-" } else { "php-" }
        $namePattern = "^$([regex]::Escape("$prefix$($Config.php_version)"))(?:[\.-].*)?-$([regex]::Escape($tsPart))-$([regex]::Escape($Config.vs_version))-$([regex]::Escape($Config.arch))\.zip$"
        $zips = @(Get-ChildItem -LiteralPath $artifactPath -Recurse -File -Filter "$prefix*.zip" | Where-Object {
            $_.Name -match $namePattern -and ($Config.ts -eq "nts" -or $_.Name -notmatch "-nts-Win32-")
        })

        if ($zips.Count -eq 0) {
            $found = (Get-ChildItem -LiteralPath $artifactPath -Recurse -File -Filter '*.zip' | ForEach-Object Name) -join ', '
            throw "Could not find PHP $Kind artifact matching $namePattern in $artifactPath. Found: $found"
        }
        if ($zips.Count -gt 1) {
            $found = ($zips | ForEach-Object Name) -join ', '
            throw "Expected one PHP $Kind artifact matching $namePattern, found $($zips.Count): $found"
        }

        Write-Host "Using PHP $Kind artifact: $($zips[0].Name)"
        return $zips[0].FullName
    }
    end {
    }
}
