$ModulePath = Split-Path -Path $PSScriptRoot -Parent
$ModuleName = Split-Path -Path $ModulePath -Leaf

# Make sure one or multiple versions of the module are not loaded
Get-Module -Name $ModuleName | Remove-Module

# Import the module and store the information about the module
$ModuleInformation = Import-Module -Name "$ModulePath\$ModuleName.psd1" -PassThru
$ModuleInformation | Format-List

# Get the functions present in the Manifest
$ExportedFunctions = $ModuleInformation.ExportedFunctions.Values.Name

# Get the functions present in the Public folder
$PS1Functions = Get-ChildItem -Path "$ModulePath\Public\*.ps1"
$ExportedPublicFunctions = $ExportedFunctions | Where-Object { $_ -in $PS1Functions.Basename }

Describe "$ModuleName Module - Testing Manifest File (.psd1)" {
    Context "Manifest" {
        It "Should contain RootModule" {
            $ModuleInformation.RootModule | Should Not BeNullOrEmpty
        }

        It "Should contain ModuleVersion" {
            $ModuleInformation.Version | Should Not BeNullOrEmpty
        }

        It "Should contain GUID" {
            $ModuleInformation.Guid | Should Not BeNullOrEmpty
        }

        It "Should contain Author" {
            $ModuleInformation.Author | Should Not BeNullOrEmpty
        }

        It "Should contain Description" {
            $ModuleInformation.Description | Should Not BeNullOrEmpty
        }

        It "Compare the count of Function Exported and the PS1 files found" {
            $status = $ExportedPublicFunctions.Count -eq $PS1Functions.Count
            $status | Should Be $true
        }

        It "Compare the missing function" {
            If ($ExportedPublicFunctions.count -ne $PS1Functions.count) {
                $Compare = Compare-Object -ReferenceObject $ExportedPublicFunctions -DifferenceObject $PS1Functions.Basename
                $Compare.InputObject -Join ',' | Should BeNullOrEmpty
            }
        }
    }
}

Describe 'PHP SBOM sidecar export' {
    InModuleScope BuildPhp {
        It 'records the exact PHP archive identity' {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $payload = Join-Path $TestDrive 'payload'
            $sbomDirectory = Join-Path $payload 'extras/sbom'
            $dependencySbomDirectory = Join-Path $sbomDirectory 'dependencies'
            $artifacts = Join-Path $TestDrive 'artifacts'
            New-Item -Path $sbomDirectory, $dependencySbomDirectory, $artifacts -ItemType Directory -Force | Out-Null

            @{
                bomFormat = 'CycloneDX'
                metadata = @{
                    component = @{
                        type = 'application'
                        name = 'php'
                        version = '8.2.33-dev'
                        properties = @()
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $sbomDirectory 'php.cdx.json')
            @{
                spdxVersion = 'SPDX-2.3'
                documentNamespace = 'https://php.net/sbom/test'
                documentDescribes = @('SPDXRef-PHP')
                packages = @(@{
                    name = 'php'
                    SPDXID = 'SPDXRef-PHP'
                    versionInfo = '8.2.33-dev'
                    downloadLocation = 'NOASSERTION'
                })
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $sbomDirectory 'php.spdx.json')
            @{
                bomFormat = 'CycloneDX'
                metadata = @{
                    component = @{
                        name = 'c-client'
                        properties = @(@{ name = 'php:library'; value = 'imap' })
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dependencySbomDirectory 'c-client.cdx.json')
            @{
                spdxVersion = 'SPDX-2.3'
                packages = @(@{ name = 'c-client'; SPDXID = 'SPDXRef-Package-c-client' })
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dependencySbomDirectory 'c-client.spdx.json')

            $artifactName = 'php-8.2.33-dev-nts-Win32-vs16-x64.zip'
            $artifactPath = Join-Path $artifacts $artifactName
            [System.IO.Compression.ZipFile]::CreateFromDirectory($payload, $artifactPath)
            $expectedHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()

            Export-PhpSbomArtifacts -ArtifactPath $artifactPath -ArtifactsDirectory $artifacts `
                -ExpectedDependencies @('imap') -RequireSbom

            $cycloneDx = Get-Content -Raw "$artifactPath.cdx.json" | ConvertFrom-Json
            $spdx = Get-Content -Raw "$artifactPath.spdx.json" | ConvertFrom-Json
            $phpPackage = $spdx.packages | Where-Object SPDXID -eq 'SPDXRef-PHP'
            $cycloneDx.metadata.component.hashes[0].content | Should Be $expectedHash
            $phpPackage.checksums[0].checksumValue | Should Be $expectedHash
            $phpPackage.packageFileName | Should Be $artifactName
            $phpPackage.downloadLocation | Should Be "https://downloads.php.net/~windows/qa/$artifactName"
        }

        It 'ignores non-runtime PHP archives' {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $payload = Join-Path $TestDrive 'debug-payload'
            $artifacts = Join-Path $TestDrive 'debug-artifacts'
            New-Item -Path $payload, $artifacts -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $payload 'php.pdb') -Value 'symbols'
            $artifactPath = Join-Path $artifacts 'php-debug-pack-8.2.33-dev-Win32-vs16-x64.zip'
            [System.IO.Compression.ZipFile]::CreateFromDirectory($payload, $artifactPath)

            Export-PhpSbomArtifacts -ArtifactPath $artifactPath -ArtifactsDirectory $artifacts -RequireSbom

            Test-Path "$artifactPath.spdx.json" | Should Be $false
        }
    }
}

Get-Module -Name $ModuleName | Remove-Module
