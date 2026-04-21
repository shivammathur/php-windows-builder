function Invoke-SaveVsToolsetCache {
    <#
    .SYNOPSIS
        Stage the selected Visual Studio toolset for GitHub Actions caching.
    .PARAMETER PhpVersion
        PHP Version.
    .PARAMETER CachePath
        Cache staging path.
    .PARAMETER Arch
        Target architecture.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Cache staging path')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $CachePath,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='Target architecture')]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch
    )
    begin {
    }
    process {
        $vsInstallPath = Get-VsInstallPath
        if ([string]::IsNullOrWhiteSpace($vsInstallPath)) {
            throw "Visual Studio installation path is not available."
        }

        $vsData = Get-VsVersion -PhpVersion $PhpVersion -Arch $Arch
        Sync-VsToolsetCache -VsInstallPath $vsInstallPath -CachePath $CachePath -Toolset $vsData.toolset
    }
    end {
    }
}
