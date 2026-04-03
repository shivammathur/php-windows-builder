function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
    )
    begin {
        $sdkRepository = $env:PHP_SDK_REPOSITORY
        if([string]::IsNullOrWhiteSpace($sdkRepository)) {
            $sdkRepository = 'php/php-sdk-binary-tools'
        }

        $sdkRef = $env:PHP_SDK_REF
        if([string]::IsNullOrWhiteSpace($sdkRef)) {
            $sdkRef = 'php-sdk-2.6.0'
        }

        $url = "https://api.github.com/repos/$sdkRepository/zipball/$([System.Uri]::EscapeDataString($sdkRef))"
        $headers = @{
            'User-Agent' = 'php-windows-builder'
        }

        if(-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
            $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN
        }
    }
    process {
        Add-StepLog "Adding PHP SDK"
        try
        {
            Add-Type -Assembly "System.IO.Compression.Filesystem"

            $currentDirectory = (Get-Location).Path
            $sdkZipFilePath = Join-Path $currentDirectory php-sdk.zip
            $extractDirectory = Join-Path $currentDirectory 'php-sdk-src'

            Invoke-WebRequest -Uri $url -Headers $headers -OutFile php-sdk.zip -UseBasicParsing
            [System.IO.Compression.ZipFile]::ExtractToDirectory($sdkZipFilePath, $extractDirectory)

            $sdkRoot = Get-ChildItem -Path $extractDirectory -Directory | Select-Object -First 1
            if($null -eq $sdkRoot) {
                throw "Failed to extract PHP SDK from $sdkRepository@$sdkRef."
            }

            Move-Item -Path $sdkRoot.FullName -Destination (Join-Path $currentDirectory 'php-sdk')
            Remove-Item -Path $extractDirectory -Recurse -Force

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
