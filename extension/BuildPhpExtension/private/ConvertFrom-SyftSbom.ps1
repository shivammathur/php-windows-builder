function ConvertFrom-SyftSbom {
    <#
    .SYNOPSIS
        Keep scanner details in generator metadata and use standard evidence fields.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $CycloneDxPath,
        [string] $SpdxPath = ''
    )

    $cycloneDx = Read-SbomJson -Path $CycloneDxPath
    $components = @()
    if($null -ne $cycloneDx.PSObject.Properties['components']) {
        $components = @($cycloneDx.components)
    }
    foreach($component in $components) {
        if($null -eq $component.PSObject.Properties['properties']) { continue }

        $locations = @($component.properties | Where-Object {
            $_.name -match '^syft:location:\d+:path$'
        } | ForEach-Object {
            ([string]$_.value).Replace('\', '/').TrimStart('/')
        } | Where-Object { $_ })
        $properties = @($component.properties | Where-Object {
            -not(([string]$_.name).StartsWith('syft:', [StringComparison]::OrdinalIgnoreCase))
        })
        if($properties.Count -eq 0) {
            $component.PSObject.Properties.Remove('properties')
        } else {
            $component.properties = $properties
        }
        if($locations.Count -eq 0) { continue }

        if($null -eq $component.PSObject.Properties['evidence']) {
            $component | Add-Member -NotePropertyName evidence -NotePropertyValue ([PSCustomObject][ordered]@{
                occurrences = @()
            })
        } elseif($null -eq $component.evidence.PSObject.Properties['occurrences']) {
            $component.evidence | Add-Member -NotePropertyName occurrences -NotePropertyValue @()
        }
        $occurrences = @($component.evidence.occurrences)
        foreach($location in $locations) {
            if(@($occurrences | Where-Object { $_.location -eq $location }).Count -gt 0) { continue }
            $occurrences += [PSCustomObject][ordered]@{ location = $location }
        }
        $component.evidence.occurrences = $occurrences
    }
    $rootRef = $cycloneDx.metadata.component.'bom-ref'
    $componentRefs = @($components | ForEach-Object { $_.'bom-ref' } | Where-Object { $_ })
    if($rootRef -and $componentRefs.Count -gt 0) {
        if($null -eq $cycloneDx.PSObject.Properties['dependencies']) {
            $cycloneDx | Add-Member -NotePropertyName dependencies -NotePropertyValue @()
        }
        $dependencies = @($cycloneDx.dependencies)
        $rootDependency = $dependencies | Where-Object { $_.ref -eq $rootRef } | Select-Object -First 1
        if($null -eq $rootDependency) {
            $rootDependency = [PSCustomObject][ordered]@{ ref = $rootRef; dependsOn = @() }
            $dependencies += $rootDependency
        } elseif($null -eq $rootDependency.PSObject.Properties['dependsOn']) {
            $rootDependency | Add-Member -NotePropertyName dependsOn -NotePropertyValue @()
        }
        $rootDependency.dependsOn = @($rootDependency.dependsOn + $componentRefs | Select-Object -Unique)
        $cycloneDx.dependencies = $dependencies
    }
    Write-SbomJson -InputObject $cycloneDx -Path $CycloneDxPath

    if(-not($SpdxPath)) { return }
    $spdx = Read-SbomJson -Path $SpdxPath
    if($null -ne $spdx.PSObject.Properties['documentNamespace'] -and
       $spdx.documentNamespace -like 'https://anchore.com/syft/*') {
        $namespaceId = [regex]::Match([string]$spdx.documentNamespace, '(?i)[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
        if($namespaceId.Success) {
            $spdx.documentNamespace = "urn:uuid:$($namespaceId.Value)"
        } else {
            $spdx.documentNamespace = "urn:uuid:$([Guid]::NewGuid())"
        }
    }
    if($null -ne $spdx.PSObject.Properties['creationInfo'] -and
       $null -ne $spdx.creationInfo.PSObject.Properties['creators'] -and
       $spdx.creationInfo.creators -like 'Tool: syft-*') {
        $spdx.creationInfo.creators = @($spdx.creationInfo.creators | Where-Object {
            $_ -ne 'Organization: Anchore, Inc'
        })
    }
    if($null -ne $spdx.PSObject.Properties['packages']) {
        foreach($package in $spdx.packages) {
            if($null -eq $package.PSObject.Properties['sourceInfo']) { continue }
            $package.sourceInfo = $package.sourceInfo -replace '(?i)(acquired package info from SBOM: )[\\/]+', '$1'
        }
    }

    if($null -ne $spdx.PSObject.Properties['files']) {
        $placeholderIds = @($spdx.files | Where-Object {
            $checksums = @($_.checksums)
            $checksums.Count -gt 0 -and @($checksums | Where-Object {
                $_.checksumValue -notmatch '^0+$'
            }).Count -eq 0
        } | ForEach-Object { $_.SPDXID })
        if($placeholderIds.Count -gt 0) {
            $files = @($spdx.files | Where-Object { $_.SPDXID -notin $placeholderIds })
            if($files.Count -eq 0) {
                $spdx.PSObject.Properties.Remove('files')
            } else {
                $spdx.files = $files
            }
            if($null -ne $spdx.PSObject.Properties['relationships']) {
                $spdx.relationships = @($spdx.relationships | Where-Object {
                    $_.spdxElementId -notin $placeholderIds -and $_.relatedSpdxElement -notin $placeholderIds
                })
            }
        }
    }
    if($null -ne $spdx.PSObject.Properties['relationships']) {
        $rootRelationship = $spdx.relationships | Where-Object {
            $_.spdxElementId -eq 'SPDXRef-DOCUMENT' -and $_.relationshipType -eq 'DESCRIBES'
        } | Select-Object -First 1
        if($null -ne $rootRelationship) {
            foreach($relationship in $spdx.relationships) {
                if($relationship.spdxElementId -eq $rootRelationship.relatedSpdxElement -and
                   $relationship.relationshipType -eq 'CONTAINS') {
                    $relationship.relationshipType = 'DEPENDS_ON'
                }
            }
        }
    }
    Write-SbomJson -InputObject $spdx -Path $SpdxPath
}
