function Invoke-ExtensionSbomGenerator {
    <#
    .SYNOPSIS
        Generate CycloneDX and SPDX documents from a build artifact with Syft.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,
        [Parameter(Mandatory = $true)]
        [string] $CycloneDxPath,
        [string] $SpdxPath = '',
        [string] $Catalogers = 'sbom-cataloger',
        [string] $SourceName = '',
        [string] $SourceVersion = '',
        [PSCustomObject] $Metadata = $null,
        [string] $ArchiveName = '',
        [string] $SyftPath = ''
    )

    if(-not($SyftPath)) { $SyftPath = Get-SbomTool -Name syft }
    if(-not(Test-Path -LiteralPath $SourcePath)) {
        throw "SBOM source '$SourcePath' was not found."
    }
    New-Item -Path (Split-Path -Path $CycloneDxPath -Parent) -ItemType Directory -Force | Out-Null
    if($SpdxPath) {
        New-Item -Path (Split-Path -Path $SpdxPath -Parent) -ItemType Directory -Force | Out-Null
    }

    $source = (Resolve-Path -LiteralPath $SourcePath).Path
    if(-not($SourceName)) { $SourceName = [IO.Path]::GetFileName($source) }
    $configuration = Join-Path $PSScriptRoot '..\config\sbom\syft.yaml'
    $arguments = @(
        $source
        '--source-name', $SourceName
        '--config', $configuration
        '--override-default-catalogers', $Catalogers
        '--quiet'
        '--output', "cyclonedx-json@1.6=$CycloneDxPath"
    )
    if($SpdxPath) {
        $arguments += @('--output', "spdx-json@2.3=$SpdxPath")
    }
    if($SourceVersion) {
        $arguments += @('--source-version', $SourceVersion)
    }
    & $SyftPath @arguments
    $succeeded = $?
    $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
    if(-not($succeeded) -or ($null -ne $exitCode -and $exitCode -ne 0)) {
        throw "Syft failed with exit code $exitCode."
    }
    ConvertFrom-SyftSbom -CycloneDxPath $CycloneDxPath -SpdxPath $SpdxPath
    if($null -ne $Metadata) {
        Add-ExtensionSbomMetadata -Metadata $Metadata `
                                  -CycloneDxPath $CycloneDxPath `
                                  -SpdxPath $SpdxPath `
                                  -ArchiveName $ArchiveName
    }
}
