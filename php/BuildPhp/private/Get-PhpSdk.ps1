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
        $currentDirectory = (Get-Location).Path
        $extractDirectory = Join-Path $currentDirectory 'php-sdk-src'

        Invoke-WebRequest -Uri $url -Headers $headers -OutFile php-sdk.zip -UseBasicParsing
        Expand-Archive -Path php-sdk.zip -DestinationPath $extractDirectory

        $sdkRoot = Get-ChildItem -Path $extractDirectory -Directory | Select-Object -First 1
        if($null -eq $sdkRoot) {
            throw "Failed to extract PHP SDK from $sdkRepository@$sdkRef."
        }

        Move-Item -Path $sdkRoot.FullName -Destination (Join-Path $currentDirectory 'php-sdk')
        Remove-Item -Path $extractDirectory -Recurse -Force
    }
    end {
    }
}
