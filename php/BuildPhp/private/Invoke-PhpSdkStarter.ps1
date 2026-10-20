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
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=3, HelpMessage='Task script')]
        [string] $Task
    )
    begin {
    }
    process {
        if ($VsConfig.vs -in @('vc11', 'vc14')) {
            $version = if ($VsConfig.vs -eq 'vc11') { '11.0' } else { '14.0' }
            $vcvars = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio $version\VC\vcvarsall.bat"
            $targetArch = if ($Arch -eq 'x64') { 'amd64' } else { 'x86' }
            $launcher = Join-Path (Get-Location) 'legacy-sdk.bat'
            $commands = @(
                '@echo off'
                "call `"$vcvars`" $targetArch"
                'if errorlevel 1 exit /b 1'
                "set PHP_SDK_VS=$($VsConfig.vs)"
                "set PHP_SDK_ARCH=$Arch"
                "call `"$BuildDirectory\php-sdk\bin\phpsdk_setvars.bat`""
                'if errorlevel 1 exit /b 1'
            )
            if ($VsConfig.vs -eq 'vc11') {
                $commands += "set PATH=$BuildDirectory\legacy-tools\bin;%PATH%"
                $commands += "set BISON_SIMPLE=$BuildDirectory\legacy-tools\bin\bison.simple"
                $commands += "set BISON_PKGDATADIR=$BuildDirectory\legacy-tools\share\bison"
            }
            $commands += @('cl 2>&1', "call `"$Task`"", 'exit /b %errorlevel%')
            Set-Content -Path $launcher -Value $commands -Encoding ascii
            & $env:ComSpec /d /c $launcher
            if ($LASTEXITCODE -ne 0) { throw "build failed with errorlevel $LASTEXITCODE" }
            return
        }

        $toolsetArgs = if ($VsConfig.vs -eq 'vs18') { @() } else { @('-s', $VsConfig.toolset) }
        & "$BuildDirectory\php-sdk\phpsdk-starter.bat" -c $VsConfig.vs -a $Arch @toolsetArgs -t $Task
        if ($LASTEXITCODE -ne 0) {
            throw "build failed with errorlevel $LASTEXITCODE"
        }
    }
    end {
    }
}
