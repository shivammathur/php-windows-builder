function Invoke-PhpStaticEmbedArtifactTests {
    <#
    .SYNOPSIS
        Validate Windows static embed artifacts.
    .PARAMETER ArtifactsDirectory
        Directory containing PHP build zip artifacts.
    .PARAMETER Arch
        PHP architecture filter.
    .PARAMETER Ts
        PHP thread safety filter.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Artifacts directory')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $ArtifactsDirectory,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP Architecture')]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='PHP Build Type')]
        [ValidateSet('nts', 'ts')]
        [string] $Ts
    )
    begin {
    }
    process {
        $artifactsPath = (Resolve-Path $ArtifactsDirectory).Path
        $tempRoot = Join-Path $env:TEMP ("php-static-embed-" + [System.Guid]::NewGuid().ToString())
        New-Item -Path $tempRoot -ItemType Directory -Force > $null 2>&1

        $runtimeZipRegex = "^php-(.+?)(-nts)?-Win32-v[sc]\d+-${Arch}\.zip$"
        $runtimeZip = @(
            Get-ChildItem -Path $artifactsPath -Filter "php-*-$Arch.zip" -File |
                Where-Object {
                    $zipMatch = [regex]::Match($_.Name, $runtimeZipRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    $_.Name -notmatch '^php-(devel-pack|debug-pack|test-pack)-' -and
                    $_.Name -notmatch '-src\.zip$' -and
                    $zipMatch.Success -and
                    (($Ts -eq 'nts') -eq $zipMatch.Groups[2].Success)
                } |
                Sort-Object Name
        )
        if($runtimeZip.Count -ne 1) {
            throw "Expected exactly one runtime archive for arch=$Arch ts=$Ts, found $($runtimeZip.Count): $($runtimeZip.Name -join ', ')"
        }
        $runtimeZip = $runtimeZip[0]
        $phpVersion = [regex]::Match($runtimeZip.Name, $runtimeZipRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Groups[1].Value
        $phpMajor = $phpVersion.Split('.')[0]

        $tsPart = if($Ts -eq 'nts') { '-nts' } else { '' }
        $develZipRegex = "^php-devel-pack-$([regex]::Escape($phpVersion))${tsPart}-Win32-v[sc]\d+-${Arch}\.zip$"
        $develZip = @(
            Get-ChildItem -Path $artifactsPath -Filter "php-devel-pack-*-$Arch.zip" -File |
                Where-Object { $_.Name -match $develZipRegex } |
                Sort-Object Name
        )
        if($develZip.Count -ne 1) {
            throw "Expected exactly one devel archive matching '$develZipRegex', found $($develZip.Count): $($develZip.Name -join ', ')"
        }
        $develZip = $develZip[0]

        $runtimePath = Join-Path $tempRoot 'runtime'
        $develPath = Join-Path $tempRoot 'devel'
        New-Item -Path $runtimePath, $develPath -ItemType Directory -Force > $null 2>&1
        try {
            Expand-Archive -Path $runtimeZip.FullName -DestinationPath $runtimePath -Force
            Expand-Archive -Path $develZip.FullName -DestinationPath $develPath -Force
        } catch {
            7z x $runtimeZip.FullName "-o$runtimePath" -y | Out-Null
            7z x $develZip.FullName "-o$develPath" -y | Out-Null
        }

        $develRoot = Get-ChildItem -Path $develPath -Directory |
            Where-Object { (Test-Path (Join-Path $_.FullName 'include')) -and (Test-Path (Join-Path $_.FullName 'lib')) } |
            Select-Object -First 1
        if($null -eq $develRoot) {
            throw "Unable to find devel root with include and lib directories in $($develZip.Name)"
        }

        $embedLibName = "php${phpMajor}embed.lib"
        $failures = New-Object System.Collections.Generic.List[string]

        $runtimeEmbedLib = Join-Path $runtimePath $embedLibName
        if(Test-Path $runtimeEmbedLib) {
            $failures.Add("$embedLibName is packaged in the runtime archive root; static SDK libraries should be shipped from the devel archive.")
        }

        $develEmbedLib = Join-Path $develRoot.FullName "lib\$embedLibName"
        if(-not(Test-Path $develEmbedLib)) {
            $failures.Add("$embedLibName is missing from $($develZip.Name) under lib.")
        }

        $embedLib = if(Test-Path $develEmbedLib) { $develEmbedLib } elseif(Test-Path $runtimeEmbedLib) { $runtimeEmbedLib } else { $null }
        if($null -eq $embedLib) {
            $failures.Add("$embedLibName was not found in either runtime or devel artifacts; unable to run consumer link checks.")
        } else {
            $vswherePath = Join-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer" 'vswhere.exe'
            if(-not(Test-Path $vswherePath)) {
                throw "vswhere.exe is not available at $vswherePath"
            }
            $vsInstallPath = & $vswherePath -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if(-not $vsInstallPath) {
                throw "Unable to locate a Visual Studio installation with VC tools"
            }
            $vsDevCmd = Join-Path $vsInstallPath 'Common7\Tools\VsDevCmd.bat'
            if(-not(Test-Path $vsDevCmd)) {
                throw "VsDevCmd.bat not found at $vsDevCmd"
            }

            $testSource = Join-Path $tempRoot 'embed_smoke.c'
            Set-Content -Path $testSource -Encoding ascii -Value @'
#include <sapi/embed/php_embed.h>

int main(int argc, char **argv)
{
    PHP_EMBED_START_BLOCK(argc, argv)
    php_printf("embed-ok\n");
    PHP_EMBED_END_BLOCK()
    return 0;
}
'@

            $includeRoot = Join-Path $develRoot.FullName 'include'
            $includeFlags = @(
                "/I`"$includeRoot`"",
                "/I`"$(Join-Path $includeRoot 'main')`"",
                "/I`"$(Join-Path $includeRoot 'Zend')`"",
                "/I`"$(Join-Path $includeRoot 'TSRM')`"",
                "/I`"$(Join-Path $includeRoot 'ext')`"",
                "/I`"$(Join-Path $includeRoot 'sapi\embed')`""
            )
            $commonDefines = @('/D PHP_WIN32=1', '/D ZEND_WIN32=1', '/D WIN32', '/D _WINDOWS', '/D _MBCS', '/D ZEND_ENABLE_STATIC_TSRMLS_CACHE=1')
            if($Ts -eq 'ts') {
                $commonDefines += '/D ZTS=1'
            }
            $exportDefines = @('/D PHP_EXPORTS', '/D LIBZEND_EXPORTS', '/D SAPI_EXPORTS', '/D TSRM_EXPORTS')

            $archArg = if($Arch -eq 'x64') { '-arch=amd64' } else { '-arch=x86' }
            $linkTests = @(
                [PSCustomObject]@{
                    Name = 'consumer headers without export macros'
                    Defines = $commonDefines
                    Expected = 'P1'
                },
                [PSCustomObject]@{
                    Name = 'consumer link with export macro workaround'
                    Defines = $commonDefines + $exportDefines
                    Expected = 'P2'
                }
            )

            foreach($linkTest in $linkTests) {
                $exe = Join-Path $tempRoot ("embed-smoke-$($linkTest.Expected.ToLowerInvariant()).exe")
                $log = Join-Path $tempRoot ("embed-smoke-$($linkTest.Expected.ToLowerInvariant()).log")
                $clArgs = @('/nologo', '/W3', '/MD') + $includeFlags + $linkTest.Defines + @(
                    "`"$testSource`"",
                    "`"$embedLib`"",
                    '/link',
                    "/out:`"$exe`""
                )
                $linkBat = Join-Path $tempRoot ("embed-smoke-$($linkTest.Expected.ToLowerInvariant()).bat")
                Set-Content -Path $linkBat -Encoding ascii -Value @(
                    '@echo on',
                    "call `"$vsDevCmd`" $archArg -host_arch=amd64",
                    'if errorlevel 1 exit /b %ERRORLEVEL%',
                    "cl $($clArgs -join ' ')",
                    'exit /b %ERRORLEVEL%'
                )
                Write-Host "Running static embed link test: $($linkTest.Name)"
                $output = cmd /d /c "`"$linkBat`"" 2>&1
                $output | Set-Content -Path $log -Encoding utf8
                $output | ForEach-Object { Write-Host $_ }
                if($LASTEXITCODE -ne 0) {
                    $failures.Add("$($linkTest.Expected): $($linkTest.Name) failed to link with $embedLibName. See $log")
                } elseif($linkTest.Expected -eq 'P2') {
                    $dumpbinBat = Join-Path $tempRoot 'embed-smoke-dumpbin.bat'
                    Set-Content -Path $dumpbinBat -Encoding ascii -Value @(
                        '@echo on',
                        "call `"$vsDevCmd`" $archArg -host_arch=amd64",
                        'if errorlevel 1 exit /b %ERRORLEVEL%',
                        "dumpbin /dependents `"$exe`"",
                        'exit /b %ERRORLEVEL%'
                    )
                    $dumpbinOutput = cmd /d /c "`"$dumpbinBat`"" 2>&1
                    $dumpbinOutput | ForEach-Object { Write-Host $_ }
                    if(($dumpbinOutput -join "`n") -match "php${phpMajor}(ts)?(_debug)?\.dll") {
                        $failures.Add("P2: linked static embed smoke executable still depends on php${phpMajor}.dll.")
                    }

                    $runOutput = & $exe 2>&1
                    $runOutput | ForEach-Object { Write-Host $_ }
                    if($LASTEXITCODE -ne 0 -or ($runOutput -join "`n") -notmatch 'embed-ok') {
                        $failures.Add("P2: linked static embed smoke executable did not run successfully.")
                    }
                }
            }
        }

        if($failures.Count -gt 0) {
            throw "Static embed artifact validation failed for arch=$Arch ts=${Ts}:`n - $($failures -join "`n - ")"
        }
    }
    end {
    }
}
