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
        $toolsetArgs = @('-s', $VsConfig.toolset)
        if ($env:DIAGNOSTIC_TOOLSET) {
            $assert = Join-Path $env:GITHUB_WORKSPACE 'builder/diagnostics/Assert-Toolset.ps1'
            $wrapper = Join-Path (Get-Location).Path 'toolset-task.bat'
            @"
@echo off
pwsh -NoProfile -File "$assert"
if errorlevel 1 exit /b 1
call "$Task"
exit /b %errorlevel%
"@ | Set-Content $wrapper
            $Task = $wrapper
            Copy-Item "$BuildDirectory/php-sdk/lib/php/libsdk/SDK/Build/PGO/Tool/PGO.php" "$env:GITHUB_WORKSPACE/toolset-evidence/SDK-PGO.php"
        }
        & "$BuildDirectory\php-sdk\phpsdk-starter.bat" -c $VsConfig.vs -a $Arch @toolsetArgs -t $Task
        if ($LASTEXITCODE -ne 0) {
            throw "build failed with errorlevel $LASTEXITCODE"
        }
    }
    end {
    }
}
