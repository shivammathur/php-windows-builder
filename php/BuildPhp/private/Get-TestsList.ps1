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

        foreach ($line in $directories) {
            $path = "$line".Trim()
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }

            $ttr = Get-ChildItem -Path $path -Filter "*.phpt" -Recurse
            foreach ($t in $ttr) {
                Add-Content $OutputFile $t.FullName
            }
        }
    }
    end {
    }
}
