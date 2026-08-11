function Add-ExtensionSbomMetadata {
    <#
    .SYNOPSIS
        Apply detected extension metadata to generated CycloneDX and SPDX documents.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Metadata,
        [Parameter(Mandatory = $true)]
        [string] $CycloneDxPath,
        [Parameter(Mandatory = $true)]
        [string] $SpdxPath,
        [string] $ArchiveName = ''
    )

    $cycloneDx = Read-SbomJson -Path $CycloneDxPath
    $component = $cycloneDx.metadata.component
    $component | Add-Member -NotePropertyName type -NotePropertyValue 'library' -Force
    $component | Add-Member -NotePropertyName name -NotePropertyValue $Metadata.name -Force
    $component | Add-Member -NotePropertyName version -NotePropertyValue $Metadata.version -Force
    $component | Add-Member -NotePropertyName purl -NotePropertyValue $Metadata.purl -Force
    if($Metadata.description) {
        $component | Add-Member -NotePropertyName description -NotePropertyValue $Metadata.description -Force
    }
    if($Metadata.license) {
        $component | Add-Member -NotePropertyName licenses -NotePropertyValue @(
            [PSCustomObject][ordered]@{ expression = $Metadata.license }
        ) -Force
    }
    if($Metadata.copyright) {
        $component | Add-Member -NotePropertyName copyright -NotePropertyValue $Metadata.copyright -Force
    }

    $cycloneDxAuthors = @($Metadata.authors | ForEach-Object {
        $author = [ordered]@{ name = $_.name }
        if($_.email) { $author.email = $_.email }
        [PSCustomObject]$author
    })
    if($cycloneDxAuthors.Count -gt 0) {
        $component | Add-Member -NotePropertyName authors -NotePropertyValue $cycloneDxAuthors -Force
    }

    $externalReferences = @()
    if($Metadata.homepage) {
        $externalReferences += [PSCustomObject][ordered]@{ type = 'website'; url = $Metadata.homepage }
    }
    if($Metadata.vcs_url) {
        $externalReferences += [PSCustomObject][ordered]@{ type = 'vcs'; url = $Metadata.vcs_url }
    } elseif($Metadata.source_url -and $Metadata.source_url -ne $Metadata.homepage) {
        $externalReferences += [PSCustomObject][ordered]@{ type = 'distribution'; url = $Metadata.source_url }
    }
    if($externalReferences.Count -gt 0) {
        $component | Add-Member -NotePropertyName externalReferences -NotePropertyValue $externalReferences -Force
    }

    if(@($Metadata.license_evidence).Count -gt 0) {
        $evidence = if($null -ne $component.PSObject.Properties['evidence']) {
            $component.evidence
        } else {
            [PSCustomObject][ordered]@{}
        }
        $occurrences = @($Metadata.license_evidence | ForEach-Object {
            [PSCustomObject][ordered]@{ location = ([string]$_).Replace('\', '/').TrimStart('/') }
        })
        $evidence | Add-Member -NotePropertyName occurrences -NotePropertyValue $occurrences -Force
        $component | Add-Member -NotePropertyName evidence -NotePropertyValue $evidence -Force
    }

    if($null -eq $cycloneDx.metadata.PSObject.Properties['tools']) {
        $cycloneDx.metadata | Add-Member -NotePropertyName tools -NotePropertyValue ([PSCustomObject][ordered]@{
            components = @()
        })
    } elseif($null -eq $cycloneDx.metadata.tools.PSObject.Properties['components']) {
        $cycloneDx.metadata.tools | Add-Member -NotePropertyName components -NotePropertyValue @()
    }
    $tools = @($cycloneDx.metadata.tools.components)
    if(@($tools | Where-Object { $_.name -eq $Metadata.scanner.name }).Count -eq 0) {
        $tools += [PSCustomObject][ordered]@{
            type = 'application'
            author = 'AboutCode.org'
            name = $Metadata.scanner.name
            version = $Metadata.scanner.version
        }
    }
    $cycloneDx.metadata.tools.components = $tools
    Write-SbomJson -InputObject $cycloneDx -Path $CycloneDxPath

    $spdx = Read-SbomJson -Path $SpdxPath
    $rootRelationship = @($spdx.relationships | Where-Object {
        $_.spdxElementId -eq 'SPDXRef-DOCUMENT' -and $_.relationshipType -eq 'DESCRIBES'
    }) | Select-Object -First 1
    if($null -eq $rootRelationship) {
        throw 'The SPDX document does not identify its root package.'
    }
    $package = @($spdx.packages | Where-Object {
        $_.SPDXID -eq $rootRelationship.relatedSpdxElement
    }) | Select-Object -First 1
    if($null -eq $package) {
        throw 'The SPDX root package was not found.'
    }

    $spdx.name = "$($Metadata.name)-$($Metadata.version)"
    $package | Add-Member -NotePropertyName name -NotePropertyValue $Metadata.name -Force
    $package | Add-Member -NotePropertyName versionInfo -NotePropertyValue $Metadata.version -Force
    $package | Add-Member -NotePropertyName primaryPackagePurpose -NotePropertyValue 'LIBRARY' -Force
    if($ArchiveName) {
        $package | Add-Member -NotePropertyName packageFileName -NotePropertyValue $ArchiveName -Force
    }
    if($Metadata.description) {
        $package | Add-Member -NotePropertyName summary -NotePropertyValue $Metadata.description -Force
    }
    if($Metadata.homepage) {
        $package | Add-Member -NotePropertyName homepage -NotePropertyValue $Metadata.homepage -Force
    }
    $declaredLicense = if($Metadata.license) { $Metadata.license } else { 'NOASSERTION' }
    $copyrightText = if($Metadata.copyright) { $Metadata.copyright } else { 'NOASSERTION' }
    $package | Add-Member -NotePropertyName licenseDeclared -NotePropertyValue $declaredLicense -Force
    $package | Add-Member -NotePropertyName licenseConcluded -NotePropertyValue $declaredLicense -Force
    $package | Add-Member -NotePropertyName copyrightText -NotePropertyValue $copyrightText -Force

    $sourceEvidence = @()
    if($Metadata.metadata_evidence) { $sourceEvidence += "metadata: $($Metadata.metadata_evidence)" }
    if(@($Metadata.license_evidence).Count -gt 0) {
        $sourceEvidence += "license: $(@($Metadata.license_evidence) -join ', ')"
    }
    if($sourceEvidence.Count -gt 0) {
        $package | Add-Member -NotePropertyName sourceInfo `
                              -NotePropertyValue ("Extension source evidence (" + ($sourceEvidence -join '; ') + ').') `
                              -Force
    }

    if(@($Metadata.authors).Count -eq 1) {
        $author = $Metadata.authors[0]
        $agentType = if($author.type -eq 'organization') { 'Organization' } else { 'Person' }
        $originator = "$agentType`: $($author.name)"
        if($author.email) { $originator += " ($($author.email))" }
        $package | Add-Member -NotePropertyName originator -NotePropertyValue $originator -Force
    } elseif(@($Metadata.authors).Count -gt 1) {
        $authorText = @($Metadata.authors | ForEach-Object {
            if($_.email) { "$($_.name) <$($_.email)>" } else { $_.name }
        }) -join '; '
        $package | Add-Member -NotePropertyName comment -NotePropertyValue "Authors: $authorText" -Force
    }

    $externalRefs = @()
    if($null -ne $package.PSObject.Properties['externalRefs']) {
        $externalRefs = @($package.externalRefs)
    }
    if($Metadata.purl -and @($externalRefs | Where-Object {
        $_.referenceType -eq 'purl' -and $_.referenceLocator -eq $Metadata.purl
    }).Count -eq 0) {
        $externalRefs += [PSCustomObject][ordered]@{
            referenceCategory = 'PACKAGE-MANAGER'
            referenceType = 'purl'
            referenceLocator = $Metadata.purl
        }
    }
    if($externalRefs.Count -gt 0) {
        $package | Add-Member -NotePropertyName externalRefs -NotePropertyValue $externalRefs -Force
    }

    $scannerCreator = "Tool: $($Metadata.scanner.name)-$($Metadata.scanner.version)"
    if($spdx.creationInfo.creators -notcontains $scannerCreator) {
        $spdx.creationInfo.creators = @($spdx.creationInfo.creators) + $scannerCreator
    }
    $licenseRefs = @()
    if($null -ne $Metadata.PSObject.Properties['license_refs']) {
        $licenseRefs = @($Metadata.license_refs)
    }
    if($licenseRefs.Count -gt 0) {
        $extractedLicenses = @()
        if($null -ne $spdx.PSObject.Properties['hasExtractedLicensingInfos']) {
            $extractedLicenses = @($spdx.hasExtractedLicensingInfos)
        }
        foreach($licenseRef in $licenseRefs) {
            if(@($extractedLicenses | Where-Object { $_.licenseId -eq $licenseRef.id }).Count -gt 0) {
                continue
            }
            $extractedLicenses += [PSCustomObject][ordered]@{
                licenseId = $licenseRef.id
                extractedText = $licenseRef.text
            }
        }
        $spdx | Add-Member -NotePropertyName hasExtractedLicensingInfos `
                          -NotePropertyValue $extractedLicenses `
                          -Force
    }
    Write-SbomJson -InputObject $spdx -Path $SpdxPath
}
