function Invoke-PhpSdkStarter {
    <#
    .SYNOPSIS
        Invoke phpsdk-starter.bat with the provided build configuration.
    .PARAMETER BuildDirectory
        Build directory containing the PHP SDK.
    .PARAMETER VsConfig
        Visual Studio configuration for the build.
    .PARAMETER Arch
        PHP Architecture
    .PARAMETER Task
        Task script to run through the PHP SDK starter.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Build directory')]
        [string] $BuildDirectory,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Visual Studio configuration')]
        [PSCustomObject] $VsConfig,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=3, HelpMessage='Task script')]
        [string] $Task
    )
    begin {
    }
    process {
        $starterCommand = Get-PhpSdkStarterCommand -SdkDirectory "$BuildDirectory\php-sdk" -VsConfig $VsConfig -Arch $Arch -Task $Task
        & $starterCommand.Path @($starterCommand.Arguments)
        if ($LASTEXITCODE -ne 0) {
            throw "build failed with errorlevel $LASTEXITCODE"
        }
    }
    end {
    }
}
