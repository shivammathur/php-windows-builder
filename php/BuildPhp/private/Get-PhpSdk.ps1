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
            $sdkVersion = '6c58890e6979eec6443642039029817f70f14620'
            $url = "https://github.com/shivammathur/php-sdk-binary-tools/archive/$sdkVersion.zip"
        }
    }
    process {
        Get-File -Url $url -OutFile php-sdk.zip
        Expand-Archive -Path php-sdk.zip -DestinationPath .
        Rename-Item -Path php-sdk-binary-tools-$sdkVersion php-sdk
    }
    end {
    }
}
