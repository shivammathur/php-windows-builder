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
        [string] $Task,
        [string] $PhpVersion = ''
    )
    begin {
    }
    process {
        if ($VsConfig.vs -in @('vc9', 'vc11', 'vc14')) {
            $version = if ($VsConfig.vs -eq 'vc9') { '9.0' } elseif ($VsConfig.vs -eq 'vc11') { '11.0' } else { '14.0' }
            $vcvars = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio $version\VC\vcvarsall.bat"
            # Express 2012 includes the x86-hosted x64 cross compiler.
            $targetArch = if ($Arch -eq 'x64') { 'x86_amd64' } else { 'x86' }
            $launcher = Join-Path (Get-Location) 'legacy-sdk.bat'
            $commands = @(
                '@echo off'
                "call `"$vcvars`" $targetArch"
                'if errorlevel 1 exit /b 1'
            )
            if ($VsConfig.vs -eq 'vc9') {
                $vs = Split-Path (Split-Path $vcvars -Parent) -Parent
                $sdk = Join-Path $vs 'Windows SDK'
                # The Express SDK has rc/mt but no message compiler. The
                # current SDK's mc generates compatible resource source files.
                $mc = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x86\mc.exe" | Sort-Object FullName -Descending | Select-Object -First 1
                if (-not $mc) { throw 'Windows SDK message compiler is missing' }
                $commands = @(
                    '@echo off'
                    "set VCINSTALLDIR=$vs\VC\"
                    "set VSINSTALLDIR=$vs\"
                    "set WindowsSdkDir=$sdk\"
                    "set PATH=$vs\VC\bin;$vs\Common7\IDE;$sdk\Bin;$($mc.Directory.FullName);%PATH%"
                    "set INCLUDE=$vs\VC\include;$sdk\Include"
                    "set LIB=$vs\VC\lib;$sdk\Lib"
                )
            }
            if ($VsConfig.vs -eq 'vc14') {
                # VS 2015 expects unversioned SDK bin directories. Current
                # Windows SDKs keep mc/mt/rc in a versioned bin directory.
                $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
                $sdkVersion = '10.0.19041.0'
                if (-not (Test-Path "$sdk\bin\$sdkVersion\x86\mc.exe")) {
                    throw "Windows SDK $sdkVersion tools are not installed"
                }
                $commands += @(
                    "set PATH=$sdk\bin\$sdkVersion\x86;%PATH%"
                    "set INCLUDE=$sdk\Include\$sdkVersion\ucrt;$sdk\Include\$sdkVersion\shared;$sdk\Include\$sdkVersion\um;$sdk\Include\$sdkVersion\winrt;%INCLUDE%"
                    "set LIB=$sdk\Lib\$sdkVersion\ucrt\$Arch;$sdk\Lib\$sdkVersion\um\$Arch;%LIB%"
                )
            }
            $commands += @(
                "set PHP_SDK_VS=$($VsConfig.vs)"
                "set PHP_SDK_ARCH=$Arch"
                "set PHP_SDK_OCI_DIR=$BuildDirectory\instantclient\sdk"
                "call `"$BuildDirectory\php-sdk\bin\phpsdk_setvars.bat`""
                'if errorlevel 1 exit /b 1'
            )
            $ociFlags = if ($PhpVersion -match '^5\.[3-5](\.|$)') {
                "`"--with-oci8=$BuildDirectory\instantclient\sdk,shared`" `"--with-oci8-11g=$BuildDirectory\instantclient\sdk,shared`""
            } else {
                "`"--with-oci8-12c=$BuildDirectory\instantclient\sdk,shared`""
            }
            $commands += "set PHP_SDK_OCI_FLAGS=$ociFlags"
            if ($VsConfig.vs -in @('vc9', 'vc11')) {
                $commands += "set PATH=$BuildDirectory\php-sdk\bin;%PATH%"
                $commands += "set BISON_PKGDATADIR=$BuildDirectory\php-sdk\share\bison"
            }
            $commands += @(
                'where cl link nmake mc mt rc bison re2c'
                'if errorlevel 1 exit /b 1'
                'cl 2>&1'
                "call `"$Task`""
                'exit /b %errorlevel%'
            )
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
