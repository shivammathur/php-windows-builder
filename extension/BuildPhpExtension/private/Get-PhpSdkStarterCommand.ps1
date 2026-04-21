function Get-PhpSdkStarterCommand {
    <#
    .SYNOPSIS
        Get the appropriate PHP SDK starter command for the target architecture.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP SDK directory')]
        [string] $SdkDirectory,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Visual Studio version')]
        [string] $VsVersion,
        [Parameter(Mandatory = $false, Position=2, HelpMessage='Visual Studio toolset')]
        [string] $VsToolset = '',
        [Parameter(Mandatory = $true, Position=3, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=4, HelpMessage='Task script')]
        [string] $Task
    )
    begin {
    }
    process {
        $starterPath = Join-Path $SdkDirectory 'phpsdk-starter.bat'
        $arguments = @('-c', $VsVersion, '-a', $Arch)

        if ($Arch -eq 'arm64') {
            $starterPath = Join-Path $SdkDirectory ("phpsdk-{0}-arm64.bat" -f $VsVersion)
            if (-not (Test-Path -Path $starterPath)) {
                throw "ARM64 PHP SDK starter script not found at $starterPath"
            }
            $arguments = @()
        }

        if ($VsToolset) {
            $arguments += @('-s', $VsToolset)
        }

        $arguments += @('-t', $Task)

        return [PSCustomObject]@{
            Path = $starterPath
            Arguments = $arguments
        }
    }
    end {
    }
}
