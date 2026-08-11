function Add-ExtensionSbom {
    <#
    .SYNOPSIS
        Generate embedded extension SBOMs or final archive sidecars.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Config,
        [PSCustomObject] $Metadata = $null,
        [Parameter(Mandatory = $true)]
        [string] $OutputDirectory,
        [string] $ArchiveName = '',
        [string] $Artifact = ''
    )

    $baseName = (ConvertTo-SbomSlug -Value $Config.name).ToLowerInvariant()
    $documentDirectory = Join-Path $OutputDirectory 'extras\sbom'
    New-Item -Path $documentDirectory -ItemType Directory -Force | Out-Null

    if($Artifact) {
        Export-ExtensionSbom -DocumentDirectory $documentDirectory `
                             -BaseName $baseName `
                             -Artifact $Artifact
        $openVexPath = Join-Path $documentDirectory "$baseName.openvex.json"
        if(Test-Path -LiteralPath $openVexPath -PathType Leaf) {
            Copy-Item -LiteralPath $openVexPath -Destination "$Artifact.openvex.json" -Force
        }
        return
    }
    if(-not($ArchiveName)) { throw 'ArchiveName is required when generating embedded SBOMs.' }
    if($null -eq $Metadata) {
        throw 'Extension source metadata was not collected before the build.'
    }

    $dependencies = Get-ExtensionSbomDependencies
    $dependencyDirectory = Join-Path $documentDirectory 'dependencies'
    New-Item -Path $dependencyDirectory -ItemType Directory -Force | Out-Null
    $index = 0
    foreach($file in $dependencies.sbomFiles) {
        $index++
        Copy-Item -LiteralPath $file `
                  -Destination (Join-Path $dependencyDirectory "$index-$([IO.Path]::GetFileName($file))") `
                  -Force
    }
    $phpBinary = Join-Path (Get-Location).Path 'php-bin\php.exe'
    if(Test-Path -LiteralPath $phpBinary -PathType Leaf) {
        Invoke-ExtensionSbomGenerator -SourcePath $phpBinary `
                                      -CycloneDxPath (Join-Path $dependencyDirectory 'php.cdx.json') `
                                      -Catalogers 'pe-binary-package-cataloger'
    }
    Merge-ExtensionOpenVex -Files $dependencies.openVexFiles `
                           -OutputPath (Join-Path $documentDirectory "$baseName.openvex.json")

    $workingDirectory = Join-Path ([IO.Path]::GetTempPath()) "extension-sbom-$([Guid]::NewGuid())"
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    try {
        $cycloneDxPath = Join-Path $workingDirectory "$baseName.cdx.json"
        $spdxPath = Join-Path $workingDirectory "$baseName.spdx.json"
        Invoke-ExtensionSbomGenerator -SourcePath $OutputDirectory `
                                      -SourceName $Metadata.name `
                                      -SourceVersion $Metadata.version `
                                      -CycloneDxPath $cycloneDxPath `
                                      -SpdxPath $spdxPath `
                                      -Metadata $Metadata `
                                      -ArchiveName $ArchiveName
        Move-Item -LiteralPath $cycloneDxPath -Destination $documentDirectory -Force
        Move-Item -LiteralPath $spdxPath -Destination $documentDirectory -Force
    } finally {
        if(Test-Path -LiteralPath $workingDirectory -PathType Container) {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force
        }
    }
}
