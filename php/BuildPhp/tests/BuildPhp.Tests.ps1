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
            $status = $ExportedFunctions.Count -eq $PS1Functions.Count
            $status | Should Be $true
        }

        It "Compare the missing function" {
            If ($ExportedFunctions.count -ne $PS1Functions.count) {
                $Compare = Compare-Object -ReferenceObject $ExportedFunctions -DifferenceObject $PS1Functions.Basename
                $Compare.InputObject -Join ',' | Should BeNullOrEmpty
            }
        }
    }
}

Describe "$ModuleName Module - PHP source patches" {
    Context "Patch file discovery" {
        It "Finds configured series patches for patch releases" {
            $patches = @(Get-PhpSourcePatchFiles -PhpVersion '7.2.34')

            $patches.Count | Should Be 1
            $patches[0].Name | Should Be '0001-fix-mkdist-string-offsets.patch'
        }

        It "Finds configured curl patch for PHP 8.4" {
            $patches = @(Get-PhpSourcePatchFiles -PhpVersion '8.4.11')

            $patches.Count | Should Be 1
            $patches[0].Name | Should Be '0001-curl-add-brotli-and-zstd-on-windows.patch'
        }

        It "Finds configured curl patch for PHP 8.5" {
            $patches = @(Get-PhpSourcePatchFiles -PhpVersion '8.5.5')

            $patches.Count | Should Be 1
            $patches[0].Name | Should Be '0001-curl-add-brotli-and-zstd-on-windows.patch'
        }

        It "Returns no patch files when a series has no configured patches" {
            @(Get-PhpSourcePatchFiles -PhpVersion '8.3.23').Count | Should Be 0
        }
    }
}

Get-Module -Name $ModuleName | Remove-Module
