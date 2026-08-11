$modulePath = Join-Path $PSScriptRoot '..\BuildPhpExtension.psd1'
Import-Module $modulePath -Force

Describe 'Get-ExtensionSbomDependencies' {
    It 'uses extension dependency documents without importing the PHP aggregate' {
        $workspace = Join-Path $TestDrive 'workspace'
        $buildDirectory = Join-Path $workspace 'build'
        $phpSbomDirectory = Join-Path $buildDirectory 'php-bin\extras\sbom'
        $librarySbomDirectory = Join-Path $workspace 'deps\share\sbom'
        New-Item -Path $phpSbomDirectory -ItemType Directory -Force | Out-Null
        New-Item -Path $librarySbomDirectory -ItemType Directory -Force | Out-Null

        '{}' | Set-Content -LiteralPath (Join-Path $phpSbomDirectory 'php.cdx.json')
        '{}' | Set-Content -LiteralPath (Join-Path $phpSbomDirectory 'php.spdx.json')
        '{}' | Set-Content -LiteralPath (Join-Path $phpSbomDirectory 'php.openvex.json')
        '{}' | Set-Content -LiteralPath (Join-Path $librarySbomDirectory 'zlib.cdx.json')
        '{}' | Set-Content -LiteralPath (Join-Path $librarySbomDirectory 'zlib.spdx.json')
        '{}' | Set-Content -LiteralPath (Join-Path $librarySbomDirectory 'zlib.openvex.json')
        '{}' | Set-Content -LiteralPath (Join-Path $librarySbomDirectory 'legacy.spdx.json')

        Push-Location $buildDirectory
        try {
            $documents = Get-ExtensionSbomDependencies
        } finally {
            Pop-Location
        }

        @($documents.sbomFiles | ForEach-Object { Split-Path -Path $_ -Leaf }) |
            Should -Be @('zlib.cdx.json', 'legacy.spdx.json')
        @($documents.openVexFiles | ForEach-Object { Split-Path -Path $_ -Leaf }) |
            Should -Be @('zlib.openvex.json')
    }
}

Describe 'Invoke-ExtensionSbomGenerator' {
    It 'scans the staging directory under the logical archive name' {
        $source = Join-Path $TestDrive 'staging'
        $cycloneDxPath = Join-Path $TestDrive 'out\extension.cdx.json'
        $spdxPath = Join-Path $TestDrive 'out\extension.spdx.json'
        $argumentsPath = Join-Path $TestDrive 'syft-arguments.txt'
        $syftPath = Join-Path $TestDrive 'syft.ps1'
        New-Item -Path $source -ItemType Directory -Force | Out-Null
        $env:SBOM_TEST_ARGUMENTS = $argumentsPath
        @'
$args | Set-Content -LiteralPath $env:SBOM_TEST_ARGUMENTS
for($index = 0; $index -lt $args.Count; $index++) {
    if($args[$index] -ne '--output') { continue }
    $output = $args[$index + 1]
    $path = ($output -split '=', 2)[1]
    if($output -like 'cyclonedx-json*') {
        '{"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"component":{"bom-ref":"extension","name":"extension.zip"}},"components":[{"bom-ref":"zlib","type":"library","name":"zlib","properties":[{"name":"syft:package:foundBy","value":"sbom-cataloger"},{"name":"syft:location:0:path","value":"/extras/sbom/dependencies/zlib.cdx.json"}]}]}' |
            Set-Content -LiteralPath $path
    } elseif($output -like 'spdx-json*') {
        '{"spdxVersion":"SPDX-2.3","name":"extension.zip","documentNamespace":"https://anchore.com/syft/dir/extension.zip-11111111-2222-3333-4444-555555555555","creationInfo":{"creators":["Organization: Anchore, Inc","Tool: syft-1.51.0"]},"packages":[{"SPDXID":"SPDXRef-Root"},{"SPDXID":"SPDXRef-Package-zlib","sourceInfo":"acquired package info from SBOM: /extras/sbom/dependencies/zlib.cdx.json"}],"files":[{"SPDXID":"SPDXRef-File-evidence","checksums":[{"algorithm":"SHA1","checksumValue":"0000000000000000000000000000000000000000"}]}],"relationships":[{"spdxElementId":"SPDXRef-Package-zlib","relatedSpdxElement":"SPDXRef-File-evidence","relationshipType":"OTHER"},{"spdxElementId":"SPDXRef-Root","relatedSpdxElement":"SPDXRef-Package-zlib","relationshipType":"CONTAINS"},{"spdxElementId":"SPDXRef-DOCUMENT","relatedSpdxElement":"SPDXRef-Root","relationshipType":"DESCRIBES"}]}' |
            Set-Content -LiteralPath $path
    }
}
'@ | Set-Content -LiteralPath $syftPath

        $metadata = [PSCustomObject]@{
            name = 'xdebug'
            version = '3.5.3'
            description = 'A debugging and productivity extension for PHP'
            authors = @([PSCustomObject]@{ type = 'person'; name = 'Derick Rethans'; email = 'derick@xdebug.org' })
            homepage = 'https://xdebug.org'
            vcs_url = 'https://github.com/xdebug/xdebug'
            source_url = 'https://github.com/xdebug/xdebug'
            purl = 'pkg:generic/xdebug@3.5.3'
            license = 'Xdebug-1.03'
            license_refs = @()
            copyright = 'Copyright (c) 2003-2026 Derick Rethans'
            metadata_evidence = 'composer.json'
            license_evidence = @('LICENSE')
            scanner = [PSCustomObject]@{ name = 'scancode-toolkit'; version = '32.5.0' }
        }

        Invoke-ExtensionSbomGenerator -SourcePath $source `
                                      -SourceName 'xdebug' `
                                      -SourceVersion '3.5.3' `
                                      -CycloneDxPath $cycloneDxPath `
                                      -SpdxPath $spdxPath `
                                      -Metadata $metadata `
                                      -ArchiveName 'extension.zip' `
                                      -SyftPath $syftPath

        $cycloneDx = Get-Content -LiteralPath $cycloneDxPath -Raw | ConvertFrom-Json
        $spdx = Get-Content -LiteralPath $spdxPath -Raw | ConvertFrom-Json
        $cycloneDx.specVersion | Should -Be '1.6'
        $cycloneDx.metadata.component.type | Should -Be 'library'
        $cycloneDx.metadata.component.name | Should -Be 'xdebug'
        $cycloneDx.metadata.component.version | Should -Be '3.5.3'
        $cycloneDx.metadata.component.authors[0].name | Should -Be 'Derick Rethans'
        $cycloneDx.metadata.component.licenses[0].expression | Should -Be 'Xdebug-1.03'
        $cycloneDx.metadata.component.copyright | Should -Be 'Copyright (c) 2003-2026 Derick Rethans'
        $cycloneDx.metadata.component.evidence.occurrences[0].location | Should -Be 'LICENSE'
        $cycloneDx.metadata.tools.components[0].name | Should -Be 'scancode-toolkit'
        $cycloneDx.components[0].PSObject.Properties['properties'] | Should -BeNullOrEmpty
        $cycloneDx.components[0].evidence.occurrences[0].location |
            Should -Be 'extras/sbom/dependencies/zlib.cdx.json'
        ($cycloneDx.dependencies | Where-Object { $_.ref -eq 'extension' }).dependsOn |
            Should -Be @('zlib')
        $spdx.spdxVersion | Should -Be 'SPDX-2.3'
        $spdx.documentNamespace | Should -Be 'urn:uuid:11111111-2222-3333-4444-555555555555'
        @($spdx.creationInfo.creators) | Should -Be @('Tool: syft-1.51.0', 'Tool: scancode-toolkit-32.5.0')
        $spdx.packages[0].name | Should -Be 'xdebug'
        $spdx.packages[0].versionInfo | Should -Be '3.5.3'
        $spdx.packages[0].originator | Should -Be 'Person: Derick Rethans (derick@xdebug.org)'
        $spdx.packages[0].licenseDeclared | Should -Be 'Xdebug-1.03'
        $spdx.packages[0].primaryPackagePurpose | Should -Be 'LIBRARY'
        $spdx.packages[0].packageFileName | Should -Be 'extension.zip'
        $spdx.packages[1].sourceInfo | Should -Be 'acquired package info from SBOM: extras/sbom/dependencies/zlib.cdx.json'
        $spdx.PSObject.Properties['files'] | Should -BeNullOrEmpty
        ($spdx.relationships | Where-Object { $_.spdxElementId -eq 'SPDXRef-Root' }).relationshipType |
            Should -Be 'DEPENDS_ON'
        $arguments = @(Get-Content -LiteralPath $argumentsPath)
        $arguments | Should -Contain 'sbom-cataloger'
        $arguments | Should -Contain $source
        $sourceNameIndex = [Array]::IndexOf($arguments, '--source-name')
        $sourceNameIndex | Should -BeGreaterThan -1
        $arguments[$sourceNameIndex + 1] | Should -Be 'xdebug'
        $sourceVersionIndex = [Array]::IndexOf($arguments, '--source-version')
        $sourceVersionIndex | Should -BeGreaterThan -1
        $arguments[$sourceVersionIndex + 1] | Should -Be '3.5.3'
        $arguments | Should -Contain ('cyclonedx-json@1.6=' + $cycloneDxPath)
        $arguments | Should -Contain ('spdx-json@2.3=' + $spdxPath)
        ($arguments -join ' ') | Should -Not -Match 'pe-binary|source-supplier'
    }
}

Describe 'Get-ExtensionSbomMetadata' {
    It 'uses ScanCode license evidence and optional PECL authors without trusting its license label' {
        $source = Join-Path $TestDrive 'pecl-source'
        $scanCodePath = Join-Path $TestDrive 'scancode-pecl.ps1'
        $argumentsPath = Join-Path $TestDrive 'scancode-pecl-arguments.txt'
        New-Item -Path $source -ItemType Directory -Force | Out-Null
        @'
<package>
  <summary>An extension from PECL</summary>
  <lead><name>Alice Maintainer</name><email>alice@example.com</email><active>yes</active></lead>
  <developer><name>Former Maintainer</name><email>former@example.com</email><active>no</active></developer>
  <license>Incorrect hardcoded label</license>
</package>
'@ | Set-Content -LiteralPath (Join-Path $source 'package.xml')
        'Custom extension license text' | Set-Content -LiteralPath (Join-Path $source 'LICENSE')
        $env:SBOM_TEST_ARGUMENTS = $argumentsPath
        @'
$args | Set-Content -LiteralPath $env:SBOM_TEST_ARGUMENTS
$outputIndex = [Array]::IndexOf($args, '--json')
@{
  headers = @(@{tool_name='scancode-toolkit'; tool_version='32.5.0'})
  packages = @()
  summary = @{declared_license_expression='custom-extension'}
  license_detections = @(@{license_expression='custom-extension'; license_expression_spdx='LicenseRef-scancode-custom-extension'})
  files = @(@{
    path='LICENSE'; is_top_level=$true; is_legal=$true
    detected_license_expression_spdx='LicenseRef-scancode-custom-extension'
    copyrights=@(@{copyright='Copyright (c) Alice Maintainer'})
  })
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $args[$outputIndex + 1]
'@ | Set-Content -LiteralPath $scanCodePath

        $metadata = Get-ExtensionSbomMetadata -SourcePath $source `
                                                     -Name example `
                                                     -Version 1.2.3 `
                                                     -SourceUrl https://pecl.php.net/package/example `
                                                     -ScanCodePath $scanCodePath

        $metadata.name | Should -Be 'example'
        $metadata.version | Should -Be '1.2.3'
        $metadata.description | Should -Be 'An extension from PECL'
        @($metadata.authors).Count | Should -Be 1
        $metadata.authors[0].name | Should -Be 'Alice Maintainer'
        $metadata.license | Should -Be 'LicenseRef-scancode-custom-extension'
        $metadata.license | Should -Not -Be 'Incorrect hardcoded label'
        $metadata.license_refs[0].text | Should -Be 'Custom extension license text'
        $metadata.copyright | Should -Be 'Copyright (c) Alice Maintainer'
        $metadata.purl | Should -Be 'pkg:generic/example@1.2.3'
        $arguments = @(Get-Content -LiteralPath $argumentsPath)
        $arguments | Should -Contain '--license'
        $arguments | Should -Contain '--package'
        $arguments | Should -Contain '--strip-root'
    }

    It 'gets identity details from Composer without package.xml' {
        $source = Join-Path $TestDrive 'composer-source'
        $scanCodePath = Join-Path $TestDrive 'scancode-composer.ps1'
        New-Item -Path $source -ItemType Directory -Force | Out-Null
        @'
$outputIndex = [Array]::IndexOf($args, '--json')
@{
  headers = @(@{tool_name='scancode-toolkit'; tool_version='32.5.0'})
  packages = @(@{
    datafile_paths=@('composer.json'); description='Composer extension'
    parties=@(@{type='person'; role='author'; name='Bob Author'; email='bob@example.com'})
    homepage_url='https://example.com'; repository_homepage_url=$null
    vcs_url='https://github.com/example/extension'; purl='pkg:composer/example/extension'
    declared_license_expression_spdx='MIT'
  })
  summary = @{declared_license_expression=$null}
  license_detections = @()
  files = @()
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $args[$outputIndex + 1]
'@ | Set-Content -LiteralPath $scanCodePath

        $metadata = Get-ExtensionSbomMetadata -SourcePath $source `
                                                     -Name example `
                                                     -Version 2.0.0 `
                                                     -ScanCodePath $scanCodePath

        Test-Path -LiteralPath (Join-Path $source 'package.xml') | Should -BeFalse
        $metadata.description | Should -Be 'Composer extension'
        $metadata.authors[0].name | Should -Be 'Bob Author'
        $metadata.homepage | Should -Be 'https://example.com'
        $metadata.vcs_url | Should -Be 'https://github.com/example/extension'
        $metadata.license | Should -Be 'MIT'
        $metadata.purl | Should -Be 'pkg:composer/example/extension@2.0.0'
        $metadata.metadata_evidence | Should -Be 'composer.json'
    }
}

Describe 'Merge-ExtensionOpenVex' {
    It 'passes only the dependency VEX documents to vexctl' {
        $first = Join-Path $TestDrive 'first.openvex.json'
        $second = Join-Path $TestDrive 'second.openvex.json'
        $outputPath = Join-Path $TestDrive 'merged.openvex.json'
        $argumentsPath = Join-Path $TestDrive 'vexctl-arguments.txt'
        $vexctlPath = Join-Path $TestDrive 'vexctl.ps1'
        '{}' | Set-Content -LiteralPath $first
        '{}' | Set-Content -LiteralPath $second
        $env:SBOM_TEST_ARGUMENTS = $argumentsPath
        @'
$args | Set-Content -LiteralPath $env:SBOM_TEST_ARGUMENTS
'{"@context":"https://openvex.dev/ns/v0.2.0","@id":"merged","author":"scanner","timestamp":"2026-01-01T00:00:00Z","version":1,"statements":[]}'
'@ | Set-Content -LiteralPath $vexctlPath

        Merge-ExtensionOpenVex -Files @($first, $second) `
                               -OutputPath $outputPath `
                               -VexctlPath $vexctlPath

        (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json).'@id' | Should -Be 'merged'
        $arguments = @(Get-Content -LiteralPath $argumentsPath)
        $arguments | Should -Contain 'merge'
        $arguments | Should -Contain $first
        $arguments | Should -Contain $second
        ($arguments -join ' ') | Should -Not -Match '--author|--id'
    }

    It 'does nothing when the build has no VEX documents' {
        $outputPath = Join-Path $TestDrive 'absent.openvex.json'
        Merge-ExtensionOpenVex -Files @() -OutputPath $outputPath
        Test-Path -LiteralPath $outputPath | Should -BeFalse
    }
}

Describe 'Export-ExtensionSbom' {
    It 'adds only the final archive hash to Syft documents' {
        $documentDirectory = Join-Path $TestDrive 'sbom'
        $artifact = Join-Path $TestDrive 'extension.zip'
        New-Item -Path $documentDirectory -ItemType Directory -Force | Out-Null
        [IO.File]::WriteAllBytes($artifact, [byte[]](1, 2, 3, 4))
        @'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "metadata": {"component": {"type": "file", "name": "extension.zip"}},
  "components": [{"type": "library", "name": "zlib", "version": "1.3.1"}]
}
'@ | Set-Content -LiteralPath (Join-Path $documentDirectory 'extension.cdx.json')
        @'
{
  "spdxVersion": "SPDX-2.3",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "extension.zip",
  "packages": [
    {"SPDXID": "SPDXRef-Root", "name": "extension.zip", "supplier": "NOASSERTION"},
    {"SPDXID": "SPDXRef-zlib", "name": "zlib", "versionInfo": "1.3.1"}
  ],
  "relationships": [
    {"spdxElementId": "SPDXRef-DOCUMENT", "relatedSpdxElement": "SPDXRef-Root", "relationshipType": "DESCRIBES"}
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $documentDirectory 'extension.spdx.json')

        Export-ExtensionSbom -DocumentDirectory $documentDirectory `
                             -BaseName extension `
                             -Artifact $artifact

        $expectedHash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        $cycloneDx = Get-Content -LiteralPath "$artifact.cdx.json" -Raw | ConvertFrom-Json
        $spdx = Get-Content -LiteralPath "$artifact.spdx.json" -Raw | ConvertFrom-Json
        $cycloneDx.metadata.component.hashes[0].content | Should -Be $expectedHash
        $cycloneDx.metadata.component.PSObject.Properties['version'] | Should -BeNullOrEmpty
        $cycloneDx.components.Count | Should -Be 1
        $spdxRoot = $spdx.packages | Where-Object { $_.SPDXID -eq 'SPDXRef-Root' }
        $spdxRoot.checksums[0].checksumValue | Should -Be $expectedHash
        $spdxRoot.PSObject.Properties['versionInfo'] | Should -BeNullOrEmpty
        $spdx.packages.Count | Should -Be 2
    }
}
