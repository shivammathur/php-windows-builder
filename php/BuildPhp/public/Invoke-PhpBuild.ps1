function Export-PhpSbomArtifacts {
    param (
        [Parameter(Mandatory = $true)] [string] $ArtifactPath,
        [Parameter(Mandatory = $true)] [string] $ArtifactsDirectory,
        [string[]] $ExpectedDependencies = @(),
        [switch] $RequireSbom
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArtifactPath)
    try {
        $entries = @{}
        foreach($entry in $archive.Entries) {
            $entries[$entry.FullName.Replace('\', '/')] = $entry
        }

        $artifactName = Split-Path -Path $ArtifactPath -Leaf
        $cycloneDxEntry = $entries['extras/sbom/php.cdx.json']
        $spdxEntry = $entries['extras/sbom/php.spdx.json']
        if($null -eq $cycloneDxEntry -and $null -eq $spdxEntry) {
            if($RequireSbom) {
                throw "PHP archive $artifactName does not contain an SBOM"
            }
            return
        }
        if($null -eq $cycloneDxEntry -or $null -eq $spdxEntry) {
            throw "PHP archive $artifactName must contain both CycloneDX and SPDX SBOMs"
        }

        $cycloneDxReader = [System.IO.StreamReader]::new($cycloneDxEntry.Open())
        try {
            $cycloneDx = $cycloneDxReader.ReadToEnd() | ConvertFrom-Json
        } finally {
            $cycloneDxReader.Dispose()
        }
        if($cycloneDx.bomFormat -ne 'CycloneDX' -or $cycloneDx.metadata.component.name -ne 'php') {
            throw "PHP archive $artifactName contains an invalid CycloneDX SBOM"
        }

        $spdxReader = [System.IO.StreamReader]::new($spdxEntry.Open())
        try {
            $spdx = $spdxReader.ReadToEnd() | ConvertFrom-Json
        } finally {
            $spdxReader.Dispose()
        }
        if($spdx.spdxVersion -ne 'SPDX-2.3' -or 'SPDXRef-PHP' -notin $spdx.documentDescribes) {
            throw "PHP archive $artifactName contains an invalid SPDX SBOM"
        }

        $openVexEntry = $entries['extras/sbom/php.openvex.json']
        if($null -ne $openVexEntry) {
            $openVexReader = [System.IO.StreamReader]::new($openVexEntry.Open())
            try {
                $openVex = $openVexReader.ReadToEnd() | ConvertFrom-Json
            } finally {
                $openVexReader.Dispose()
            }
            if($openVex.'@context' -ne 'https://openvex.dev/ns/v0.2.0' -or $null -eq $openVex.statements) {
                throw "PHP archive $artifactName contains an invalid OpenVEX document"
            }
        }

        $dependencyFormats = @{}
        foreach($entryName in $entries.Keys) {
            if($entryName -match '^extras/sbom/dependencies/(.+)\.(cdx|spdx)\.json$') {
                if(-not $dependencyFormats.ContainsKey($Matches[1])) {
                    $dependencyFormats[$Matches[1]] = [System.Collections.Generic.HashSet[string]]::new()
                }
                $dependencyFormats[$Matches[1]].Add($Matches[2]) | Out-Null
            }
        }
        foreach($dependency in $dependencyFormats.GetEnumerator()) {
            if($dependency.Value.Count -ne 2) {
                throw "PHP archive $artifactName has incomplete SBOM formats for dependency $($dependency.Key)"
            }
        }
        foreach($dependency in $ExpectedDependencies) {
            if($null -eq $entries["extras/sbom/dependencies/$dependency.cdx.json"] -or
                $null -eq $entries["extras/sbom/dependencies/$dependency.spdx.json"]) {
                throw "PHP archive $artifactName does not contain both SBOM formats for expected dependency $dependency"
            }
        }

        foreach($sidecar in @{
            'extras/sbom/php.cdx.json' = '.cdx.json'
            'extras/sbom/php.spdx.json' = '.spdx.json'
            'extras/sbom/php.openvex.json' = '.openvex.json'
        }.GetEnumerator()) {
            $entry = $entries[$sidecar.Key]
            if($null -eq $entry) {
                continue
            }
            $sidecarPath = Join-Path $ArtifactsDirectory ($artifactName + $sidecar.Value)
            $inputStream = $entry.Open()
            $outputStream = [System.IO.File]::Create($sidecarPath)
            try {
                $inputStream.CopyTo($outputStream)
            } finally {
                $outputStream.Dispose()
                $inputStream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}

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
    .PARAMETER RequireSbom
        Require and validate dependency SBOMs in the PHP binary archive.
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
        [Parameter(Mandatory = $false, HelpMessage='Require SBOM files in the PHP binary archive')]
        [switch] $RequireSbom
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

        $currentDirectory = (Get-Location).Path

        $tempDirectory = [System.IO.Path]::GetTempPath()

        $buildDirectory = [System.IO.Path]::Combine($tempDirectory, ("php-" + [System.Guid]::NewGuid().ToString()))

        New-Item "$buildDirectory" -ItemType "directory" -Force > $null 2>&1

        try {
            Set-Location "$buildDirectory"

            Add-BuildRequirements -PhpVersion $PhpVersion -Arch $Arch -FetchSrc:$fetchSrc

            $configDirectory = Join-Path $PSScriptRoot "..\config\$($VsConfig.vs)\$Arch"
            $configBatch = Join-Path $configDirectory "config.$Ts.bat"

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
            $depsInfo = Add-PhpDeps -PhpVersion $PhpVersion -VsVersion $VsConfig.vs -Arch $Arch -Destination (Join-Path $buildParent 'deps')
            if($RequireSbom -and $depsInfo.Libraries.Count -eq 0) {
                throw 'Strict SBOM validation requires a non-empty PHP dependency list'
            }
            $taskTemplate = Join-Path $PSScriptRoot "..\runner\task-$Ts.bat"

            $task = [System.IO.Path]::GetFileName($taskTemplate)
            Copy-Item -Path $taskTemplate -Destination $task -Force

            Invoke-PhpSdkStarter -BuildDirectory $buildDirectory -VsConfig $VsConfig -Arch $Arch -Task $task

            $artifacts = if ($Ts -eq "ts") {"..\obj\Release_TS\php-*.zip"} else {"..\obj\Release\php-*.zip"}
            New-Item "$artifactsDirectory" -ItemType "directory" -Force > $null 2>&1
            $builtArtifacts = @(Get-ChildItem -Path $artifacts -File)
            if($builtArtifacts.Count -eq 0) {
                throw "No PHP binary archives were produced at $artifacts"
            }
            Copy-Item -Path $builtArtifacts.FullName -Destination $artifactsDirectory -Force

            foreach($artifact in $builtArtifacts) {
                $artifactPath = Join-Path $artifactsDirectory $artifact.Name
                $expectedDependencies = if($RequireSbom) { $depsInfo.Libraries } else { @() }
                Export-PhpSbomArtifacts -ArtifactPath $artifactPath -ArtifactsDirectory $artifactsDirectory `
                    -ExpectedDependencies $expectedDependencies -RequireSbom:$RequireSbom
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
