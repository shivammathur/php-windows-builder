function Export-PhpSbomArtifacts {
    <#
    .SYNOPSIS
        Validate and export SBOM sidecars from a PHP binary archive.
    .PARAMETER ArtifactPath
        Path to the PHP binary archive.
    .PARAMETER ArtifactsDirectory
        Directory where the SBOM sidecars are written.
    .PARAMETER ExpectedDependencies
        Dependencies that must have both CycloneDX and SPDX fragments.
    .PARAMETER RequireSbom
        Require the PHP binary archive to contain SBOMs.
    #>
    [CmdletBinding()]
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
        $artifactMatch = [regex]::Match(
            $artifactName,
            '^php-([0-9].+?)(-nts)?-Win32-(v[sc]\d+)-(x86|x64|arm64)\.zip$',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if(-not $artifactMatch.Success) {
            return
        }
        $artifactVersion = $artifactMatch.Groups[1].Value
        $threadSafety = if($artifactMatch.Groups[2].Success) { 'nts' } else { 'ts' }
        $vsVersion = $artifactMatch.Groups[3].Value
        $architecture = $artifactMatch.Groups[4].Value
        $releaseDirectory = if($artifactVersion -match '^\d+\.\d+\.\d+$') { 'releases' } else { 'qa' }
        $downloadLocation = "https://downloads.php.net/~windows/$releaseDirectory/$artifactName"
        $artifactSha256 = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
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
        $cycloneDx.metadata.component | Add-Member -NotePropertyName hashes -NotePropertyValue @(
            [ordered]@{ alg = 'SHA-256'; content = $artifactSha256 }
        ) -Force
        $existingExternalReferences = if($null -eq $cycloneDx.metadata.component.PSObject.Properties['externalReferences']) {
            @()
        } else {
            @($cycloneDx.metadata.component.externalReferences)
        }
        $cycloneDx.metadata.component | Add-Member -NotePropertyName externalReferences -NotePropertyValue @(
            $existingExternalReferences | Where-Object { $_.type -ne 'distribution' }
            [ordered]@{ type = 'distribution'; url = $downloadLocation }
        ) -Force
        $cycloneDx.metadata.component.properties = @(
            @($cycloneDx.metadata.component.properties) | Where-Object {
                $_.name -notin @(
                    'php:artifact-file-name',
                    'php:artifact-download-location',
                    'php:artifact-architecture',
                    'php:artifact-thread-safety',
                    'php:artifact-compiler'
                )
            }
        ) + @(
            [ordered]@{ name = 'php:artifact-file-name'; value = $artifactName }
            [ordered]@{ name = 'php:artifact-download-location'; value = $downloadLocation }
            [ordered]@{ name = 'php:artifact-architecture'; value = $architecture }
            [ordered]@{ name = 'php:artifact-thread-safety'; value = $threadSafety }
            [ordered]@{ name = 'php:artifact-compiler'; value = $vsVersion }
        )

        $spdxReader = [System.IO.StreamReader]::new($spdxEntry.Open())
        try {
            $spdx = $spdxReader.ReadToEnd() | ConvertFrom-Json
        } finally {
            $spdxReader.Dispose()
        }
        if($spdx.spdxVersion -ne 'SPDX-2.3' -or 'SPDXRef-PHP' -notin $spdx.documentDescribes) {
            throw "PHP archive $artifactName contains an invalid SPDX SBOM"
        }
        $spdx.documentNamespace = "$downloadLocation.spdx.json"
        $phpPackage = $spdx.packages | Where-Object { $_.SPDXID -eq 'SPDXRef-PHP' } | Select-Object -First 1
        if($null -eq $phpPackage) {
            throw "PHP archive $artifactName does not describe SPDXRef-PHP"
        }
        $phpPackage | Add-Member -NotePropertyName packageFileName -NotePropertyValue $artifactName -Force
        $phpPackage.downloadLocation = $downloadLocation
        $phpPackage | Add-Member -NotePropertyName checksums -NotePropertyValue @(
            [ordered]@{ algorithm = 'SHA256'; checksumValue = $artifactSha256 }
        ) -Force
        $phpPackage | Add-Member -NotePropertyName supplier -NotePropertyValue 'Organization: PHP Group' -Force
        $phpPackage | Add-Member -NotePropertyName originator -NotePropertyValue 'Organization: PHP Group' -Force
        $phpPackage | Add-Member -NotePropertyName primaryPackagePurpose -NotePropertyValue 'APPLICATION' -Force

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

        $cycloneDx | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (
            Join-Path $ArtifactsDirectory ($artifactName + '.cdx.json')
        ) -Encoding utf8
        $spdx | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (
            Join-Path $ArtifactsDirectory ($artifactName + '.spdx.json')
        ) -Encoding utf8
        if($null -ne $openVexEntry) {
            $openVex | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (
                Join-Path $ArtifactsDirectory ($artifactName + '.openvex.json')
            ) -Encoding utf8
        }
    } finally {
        $archive.Dispose()
    }
}
