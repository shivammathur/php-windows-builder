function Get-PhpSourcePatchFiles {
    <#
    .SYNOPSIS
        Get patch files for a PHP version series.
    .PARAMETER PhpVersion
        PHP version or branch name.
    #>
    [OutputType([System.IO.FileInfo[]])]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion
    )
    begin {
    }
    process {
        $patchSeries = [regex]::Match($PhpVersion, '^\d+\.\d+').Value
        if ([string]::IsNullOrWhiteSpace($patchSeries)) {
            $patchSeries = $PhpVersion
        }

        $patchDirectory = Join-Path $PSScriptRoot "..\config\patches\$patchSeries"

        if (-not (Test-Path -Path $patchDirectory -PathType Container)) {
            return @()
        }

        return @(
            Get-ChildItem -Path $patchDirectory -File |
                Where-Object { $_.Extension -in '.patch', '.diff' } |
                Sort-Object Name
        )
    }
    end {
    }
}
