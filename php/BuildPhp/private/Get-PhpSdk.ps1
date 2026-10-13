function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param ([ValidateSet('x86','x64','arm64')] [string] $Arch = 'x64')
    begin {
        $sdkVersion = "php-sdk-2.8.4"
        $url = "https://github.com/php/php-sdk-binary-tools/archive/$sdkVersion.zip"
        if ($Arch -eq 'arm64') {
            $sdkVersion = 'b9c2ad91e73e88195011b48c59d81865f147b7f1'
            $url = "https://github.com/shivammathur/php-sdk-binary-tools/archive/$sdkVersion.zip"
        }
    }
    process {
        Get-File -Url $url -OutFile php-sdk.zip
        Expand-Archive -Path php-sdk.zip -DestinationPath .
        Get-ChildItem -Directory -Filter "php-sdk-binary-tools-*" | Rename-Item -NewName php-sdk
    }
    end {
    }
}
