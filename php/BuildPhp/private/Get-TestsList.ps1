function Get-TestsList {
    <#
    .SYNOPSIS
        Get the PHP test list.
    .PARAMETER OutputFile
        Output file
    .PARAMETER Type
        Test type
    .PARAMETER TestDirectories
        Optional test directories to run instead of the configured test list
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Output file')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $OutputFile,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Test type')]
        [ValidateNotNull()]
        [ValidateSet('php', 'ext')]
        [string] $Type,
        [Parameter(Mandatory = $false, Position=2, HelpMessage='Optional test directories')]
        [string[]] $TestDirectories = @()
    )
    begin {
    }
    process {
        Remove-Item $OutputFile -ErrorAction "Ignore"
        $directories = $TestDirectories
        if ($null -eq $directories -or $directories.Count -eq 0) {
            $directories = Get-Content "$PSScriptRoot\..\config\${Type}_test_directories"
        }

        $testsFound = 0
        $outputFilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
        $writer = [System.IO.StreamWriter]::new($outputFilePath, $false)
        try {
            foreach ($line in $directories) {
                $path = "$line".Trim()
                if ([string]::IsNullOrWhiteSpace($path)) {
                    continue
                }

                if (Test-Path -Path $path -PathType Leaf) {
                    if ([System.IO.Path]::GetExtension($path) -ne '.phpt') {
                        Write-Host "Skipping non-PHPT test file: $path"
                        continue
                    }
                    $testsFound++
                    $writer.WriteLine((Resolve-Path -Path $path).Path)
                    continue
                }

                if (-not (Test-Path -Path $path -PathType Container)) {
                    Write-Host "Skipping missing test path: $path"
                    continue
                }

                Get-ChildItem -Path $path -Filter "*.phpt" -Recurse | ForEach-Object {
                    $testsFound++
                    $writer.WriteLine($_.FullName)
                }
            }
        } finally {
            $writer.Dispose()
        }

        if ($testsFound -eq 0) {
            throw "No tests were found in the configured $Type test directories."
        }
    }
    end {
    }
}
