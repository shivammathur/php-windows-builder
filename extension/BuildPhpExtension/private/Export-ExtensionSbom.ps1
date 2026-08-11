function Export-ExtensionSbom {
    <#
    .SYNOPSIS
        Export Syft documents as sidecars for the final extension archive.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $DocumentDirectory,
        [Parameter(Mandatory = $true)]
        [string] $BaseName,
        [Parameter(Mandatory = $true)]
        [string] $Artifact
    )

    if(-not(Test-Path -LiteralPath $Artifact -PathType Leaf)) {
        throw "Extension archive '$Artifact' was not found."
    }
    $archiveHash = (Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash.ToLowerInvariant()

    $cycloneDx = Read-SbomJson -Path (Join-Path $DocumentDirectory "$BaseName.cdx.json")
    if($null -eq $cycloneDx.metadata.component.PSObject.Properties['hashes']) {
        $cycloneDx.metadata.component | Add-Member -NotePropertyName hashes -NotePropertyValue @()
    }
    $cycloneDx.metadata.component.hashes = @([PSCustomObject][ordered]@{
        alg = 'SHA-256'
        content = $archiveHash
    })
    Write-SbomJson -InputObject $cycloneDx -Path "$Artifact.cdx.json"

    $spdx = Read-SbomJson -Path (Join-Path $DocumentDirectory "$BaseName.spdx.json")
    $describes = @($spdx.relationships | Where-Object {
        $_.spdxElementId -eq 'SPDXRef-DOCUMENT' -and $_.relationshipType -eq 'DESCRIBES'
    })[0]
    $root = @($spdx.packages | Where-Object { $_.SPDXID -eq $describes.relatedSpdxElement })[0]
    if($null -eq $root) {
        throw 'The Syft SPDX document does not describe a root package.'
    }
    if($null -eq $root.PSObject.Properties['checksums']) {
        $root | Add-Member -NotePropertyName checksums -NotePropertyValue @()
    }
    $root.checksums = @([PSCustomObject][ordered]@{
        algorithm = 'SHA256'
        checksumValue = $archiveHash
    })
    Write-SbomJson -InputObject $spdx -Path "$Artifact.spdx.json"
}
