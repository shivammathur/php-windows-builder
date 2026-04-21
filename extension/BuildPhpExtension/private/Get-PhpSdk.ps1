function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $false, Position=0, HelpMessage='Extension Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch = 'x64'
    )
    begin {
        $sdkRef = "refs/heads/arm64-support"
        $sdkRepository = "shivammathur/php-sdk-binary-tools"
        $url = "https://github.com/$sdkRepository/archive/$sdkRef.zip"
    }
    process {
        Add-StepLog "Adding PHP SDK"
        try
        {
            Add-Type -Assembly "System.IO.Compression.Filesystem"
            $existingDirectories = @(Get-ChildItem -Directory | Select-Object -ExpandProperty Name)

            Get-File -Url $url -OutFile php-sdk.zip
            $currentDirectory = (Get-Location).Path
            $sdkZipFilePath = Join-Path $currentDirectory php-sdk.zip
            [System.IO.Compression.ZipFile]::ExtractToDirectory($sdkZipFilePath, $currentDirectory)
            $sdkDirectory = Get-ChildItem -Directory -Filter 'php-sdk-binary-tools-*' |
                Where-Object { $existingDirectories -notcontains $_.Name } |
                Select-Object -First 1

            if ($null -eq $sdkDirectory) {
                throw "Failed to locate the extracted PHP SDK directory for $sdkRepository@$sdkRef"
            }

            Rename-Item -Path $sdkDirectory.FullName -NewName php-sdk

            $sdkDirectoryPath = Join-Path $currentDirectory php-sdk
            $sdkBinDirectoryPath = Join-Path $sdkDirectoryPath bin
            $sdkMsys2DirectoryPath = Join-Path $sdkDirectoryPath msys2
            Add-Path -PathItem $sdkBinDirectoryPath
            Add-Path -PathItem $sdkMsys2DirectoryPath
            Add-BuildLog tick "PHP SDK" "PHP SDK Added"
        } catch {
            Add-BuildLog cross "PHP SDK" "Failed to fetch PHP SDK"
            throw
        }
    }
    end {
    }
}
