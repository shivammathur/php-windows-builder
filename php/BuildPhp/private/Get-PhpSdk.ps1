function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
    )
    begin {
        $sdkVersion = "9153ac9355bb12a1cac6751fec7cedd9bcf8d187"
        $url = "https://github.com/php/php-sdk-binary-tools/archive/$sdkVersion.zip"
    }
    process {
        Get-File -Url $url -OutFile php-sdk.zip
        Expand-Archive -Path php-sdk.zip -DestinationPath .
        Rename-Item -Path php-sdk-binary-tools-$sdkVersion php-sdk
    }
    end {
    }
}
