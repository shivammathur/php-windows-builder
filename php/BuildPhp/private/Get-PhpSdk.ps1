function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
    )
    begin {
        $sdkVersion = "54c490593e663e10a46dd8c0bec63b22e0239d09"
        $url = "https://github.com/shivammathur/php-sdk-binary-tools/archive/$sdkVersion.zip"
    }
    process {
        Get-File -Url $url -OutFile php-sdk.zip
        Expand-Archive -Path php-sdk.zip -DestinationPath .
        Rename-Item -Path php-sdk-binary-tools-$sdkVersion php-sdk
    }
    end {
    }
}
