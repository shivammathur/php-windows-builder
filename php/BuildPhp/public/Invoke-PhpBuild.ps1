function Invoke-PhpBuild {
    <#
    .SYNOPSIS
        Build PHP.
    .PARAMETER PhpVersion
        PHP Version
    .PARAMETER Arch
        PHP Architecture
    .PARAMETER Ts
        PHP Build Type
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $false, Position=0, HelpMessage='PHP Version')]
        [string] $PhpVersion = '',
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='PHP Build Type')]
        [ValidateNotNull()]
        [ValidateSet('nts', 'ts')]
        [string] $Ts
    )
    begin {
    }
    process {
        Set-NetSecurityProtocolType
        $fetchSrc = $True
        if($null -eq $PhpVersion -or $PhpVersion -eq '') {
            $fetchSrc = $False
            $PhpVersion = Get-SourcePhpVersion
        }
        $VsConfig = (Get-VsVersion -PhpVersion $PhpVersion)
        if($null -eq $VsConfig.vs) {
            throw "PHP version $PhpVersion is not supported."
        }
        $majorMinor = if($PhpVersion -eq 'master') { 'master' } else { $PhpVersion.Substring(0, 3) }
        $withSbom = (Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\config\sbom.json') | ConvertFrom-Json).php.$majorMinor

        $currentDirectory = (Get-Location).Path

        $tempDirectory = [System.IO.Path]::GetTempPath()

        $buildDirectory = [System.IO.Path]::Combine($tempDirectory, ("php-" + [System.Guid]::NewGuid().ToString()))

        New-Item "$buildDirectory" -ItemType "directory" -Force > $null 2>&1

        try {
            Set-Location "$buildDirectory"

            Add-BuildRequirements -PhpVersion $PhpVersion -Arch $Arch -FetchSrc:$fetchSrc

            $configDirectory = Join-Path $PSScriptRoot "..\config\$($VsConfig.vs)\$Arch"
            $configName = if($withSbom) { "config.$Ts.sbom.bat" } else { "config.$Ts.bat" }
            $configBatch = Join-Path $configDirectory $configName

            if($fetchSrc) {
                Copy-Item -Path $PSScriptRoot\..\config -Destination . -Recurse
                $buildPath = "$buildDirectory\config\$($VsConfig.vs)\$Arch\php-$PhpVersion"
                $sourcePath = "$buildDirectory\php-$PhpVersion-src"
                Move-Item $sourcePath $buildPath
            } else {
                $buildPath = $currentDirectory
            }

            $buildParent = Split-Path -Path $buildPath -Parent
            $artifactsDirectory = Join-Path $currentDirectory 'artifacts'

            Set-Location "$buildPath"
            New-Item (Join-Path $buildParent 'obj') -ItemType "directory" -Force > $null 2>&1
            Copy-Item -Path $configBatch -Destination (Join-Path $buildPath "config.$Ts.bat") -Force
            Add-PhpDeps -PhpVersion $PhpVersion -VsVersion $VsConfig.vs -Arch $Arch -Destination (Join-Path $buildParent 'deps')
            $taskTemplate = Join-Path $PSScriptRoot "..\runner\task-$Ts.bat"

            $task = [System.IO.Path]::GetFileName($taskTemplate)
            Copy-Item -Path $taskTemplate -Destination $task -Force

            Invoke-PhpSdkStarter -BuildDirectory $buildDirectory -VsConfig $VsConfig -Arch $Arch -Task $task

            $artifacts = if ($Ts -eq "ts") {"..\obj\Release_TS\php-*.zip"} else {"..\obj\Release\php-*.zip"}
            New-Item "$artifactsDirectory" -ItemType "directory" -Force > $null 2>&1
            xcopy $artifacts "$artifactsDirectory\*"

            if($withSbom) {
                foreach($artifact in Get-ChildItem -Path $artifacts -File | Where-Object { $_.Name -notmatch '^php-(debug|devel|test)-pack-' }) {
                    $artifactPath = Join-Path $artifactsDirectory $artifact.Name
                    & "$buildDirectory\php-sdk\bin\phpsdk_sbom.bat" --export "$artifactPath"
                    if($LASTEXITCODE -ne 0) {
                        throw "SBOM export failed for $($artifact.Name) with errorlevel $LASTEXITCODE"
                    }
                }
            }
            if($fetchSrc) {
                Move-Item "$buildDirectory\php-$PhpVersion-src.zip" "$artifactsDirectory\"
            }
        } finally {
            Set-Location "$currentDirectory"
        }
    }
    end {
    }
}
