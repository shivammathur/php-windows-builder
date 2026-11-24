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
    .PARAMETER BuildNumber
        Optional positive build number for rebuilding an existing source tag.
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
        [string] $Ts,
        [Parameter(Mandatory = $false, Position=3)]
        [ValidatePattern('^(?:[1-9][0-9]*)?$')]
        [string] $BuildNumber = ''
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
        $buildVersion = Get-PhpBuildVersion -PhpVersion $PhpVersion -BuildNumber $BuildNumber
        if ($buildVersion.PhpVersion -match '^5\.[34](\.|$)' -and $Arch -ne 'x86') {
            throw 'PHP 5.3 and 5.4 require x86.'
        }
        $VsConfig = (Get-VsVersion -PhpVersion $buildVersion.PhpVersion)
        if($null -eq $VsConfig.vs) {
            throw "PHP version $PhpVersion is not supported."
        }
        $legacy = $VsConfig.vs -in @('vc9', 'vc11', 'vc14')
        $sbom = $env:SBOM
        if ($sbom -eq 'auto') { $sbom = (-not $legacy).ToString() }
        if ($legacy -and $sbom -eq 'true') { throw 'The PHP 5.3-7.1 SDKs do not support SBOM generation.' }
        $currentDirectory = (Get-Location).Path

        $tempDirectory = [System.IO.Path]::GetTempPath()

        $buildDirectory = [System.IO.Path]::Combine($tempDirectory, ("php-" + [System.Guid]::NewGuid().ToString()))

        New-Item "$buildDirectory" -ItemType "directory" -Force > $null 2>&1

        try {
            Set-Location "$buildDirectory"

            Add-BuildRequirements -PhpVersion $PhpVersion -Arch $Arch -FetchSrc:$fetchSrc

            $configName = if ($legacy) { 'php' + $PhpVersion.Split('.')[0] } else { "$($VsConfig.vs)\$Arch" }
            $configDirectory = Join-Path $PSScriptRoot "..\config\$configName"

            if($fetchSrc) {
                Copy-Item -Path $PSScriptRoot\..\config -Destination . -Recurse
                $buildPath = "$buildDirectory\config\$configName\php-$PhpVersion"
                $sourcePath = "$buildDirectory\php-$PhpVersion-src"
                Move-Item $sourcePath $buildPath
            } else {
                $buildPath = $currentDirectory
                Update-PhpPackagingScript -PhpVersion $buildVersion.PhpVersion -SourceDirectory $buildPath
            }

            $configBatch = Join-Path $configDirectory "config.$Ts.bat"

            $buildParent = Split-Path -Path $buildPath -Parent
            $depsDirectory = Join-Path $buildParent 'deps'
            $outputDirectory = Join-Path $currentDirectory 'artifacts'
            $artifactsDirectory = if ($buildVersion.BuildNumber) { Join-Path $buildDirectory 'artifacts' } else { $outputDirectory }

            Set-Location "$buildPath"
            New-Item (Join-Path $buildParent 'obj') -ItemType "directory" -Force > $null 2>&1
            $ociArguments = Get-OciBuildConfiguration -PhpVersion $buildVersion.PhpVersion `
                                                     -SdkDirectory (Join-Path $buildDirectory 'instantclient\sdk')
            $configContent = Get-Content -LiteralPath $configBatch -Raw
            $configContent.Replace('%*', (($ociArguments -join ' ') + ' %*')) |
                Set-Content -LiteralPath (Join-Path $buildPath "config.$Ts.bat") -Encoding ascii
            Add-PhpDeps -PhpVersion $buildVersion.PhpVersion -VsVersion $VsConfig.vs -Arch $Arch -Destination $depsDirectory

            $sbomMetadata = Get-PhpSbomMetadata -Sbom $sbom -PhpVersion $buildVersion.PhpVersion -BuildDirectory $buildDirectory
            if ($legacy) {
                & "$PSScriptRoot\..\runner\task-legacy.bat" "$buildDirectory\php-sdk" $VsConfig.toolset $Arch "config.$Ts.bat"
                if ($LASTEXITCODE -ne 0) { throw "Legacy PHP build failed with errorlevel $LASTEXITCODE" }
            } else {
                $task = "task-$Ts.bat"
                Copy-Item "$PSScriptRoot\..\runner\$task" -Destination $task -Force
                Invoke-PhpSdkStarter -BuildDirectory $buildDirectory -VsConfig $VsConfig -Arch $Arch -Task $task
            }

            $artifacts = if ($Ts -eq "ts") {"..\obj\Release_TS\php-*.zip"} else {"..\obj\Release\php-*.zip"}
            $binaryArtifacts = @(Get-ChildItem -Path $artifacts -File | Where-Object { $_.Name -notmatch '^php-(debug|devel|test)-pack-' })
            if ($legacy) {
                # Historical snap makefiles ignore ZIP command failures.
                if ($binaryArtifacts.Count -ne 1) { throw "Expected one PHP binary archive in $artifacts" }
                $binary = $binaryArtifacts[0]
                $suffix = $binary.Name.Substring(4)
                $testPack = $binary.Name -replace '^php-(.+?)(?:-nts)?-Win32-vc\d+-(?:x86|x64)\.zip$', 'php-test-pack-$1.zip'
                foreach ($pack in @("php-debug-pack-$suffix", "php-devel-pack-$suffix", $testPack)) {
                    if (-not (Test-Path -LiteralPath (Join-Path $binary.DirectoryName $pack) -PathType Leaf)) {
                        throw "Missing PHP build artifact: $pack"
                    }
                }
            } else {
                foreach($artifact in $binaryArtifacts) {
                    Add-PhpComplianceFiles -SdkDirectory (Join-Path $buildDirectory 'php-sdk') `
                                           -SourceDirectory $buildPath `
                                           -DepsDirectory $depsDirectory `
                                           -Artifact $artifact.FullName `
                                           -SbomMetadata $sbomMetadata
                }
            }

            New-Item "$artifactsDirectory" -ItemType "directory" -Force > $null 2>&1
            xcopy $artifacts "$artifactsDirectory\*"

            if($sbomMetadata) {
                foreach($artifact in $binaryArtifacts) {
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
            Set-PhpArtifactVersion -ArtifactsDirectory $artifactsDirectory -PackageVersion $buildVersion.PackageVersion
            if ($buildVersion.BuildNumber) {
                $null = New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop
                $packages = Get-ChildItem -LiteralPath $artifactsDirectory -File
                foreach ($package in $packages) {
                    $destination = Join-Path $outputDirectory $package.Name
                    if (Test-Path -LiteralPath $destination) {
                        throw "PHP artifact already exists: $destination"
                    }
                }
                $packages | Move-Item -Destination $outputDirectory -ErrorAction Stop
            }
        } finally {
            Set-Location "$currentDirectory"
        }
    }
    end {
    }
}
