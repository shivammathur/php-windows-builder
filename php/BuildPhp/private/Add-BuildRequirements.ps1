function Add-BuildRequirements {
    <#
    .SYNOPSIS
        Get the PHP source code.
    .PARAMETER PhpVersion
        PHP Version
    .PARAMETER Arch
        PHP Architecture
    .PARAMETER FetchSrc
        Fetch PHP source code
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='Visual Studio Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $VsVersion,
        [Parameter(Mandatory = $true, Position=3, HelpMessage='MSVC toolset version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $Toolset,
        [Parameter(Mandatory = $false, Position=4, HelpMessage='Fetch PHP source code')]
        [ValidateNotNull()]
        [bool] $FetchSrc = $True
    )
    begin {
    }
    process {
        Add-PgoRequirements -VsVersion $VsVersion -Toolset $Toolset -Arch $Arch
        Get-OciSdk -Arch $Arch
        Get-PhpSdk -Arch $Arch
        if($FetchSrc) {
            Get-PhpSrc -PhpVersion $PhpVersion
        }
    }
    end {
    }
}
