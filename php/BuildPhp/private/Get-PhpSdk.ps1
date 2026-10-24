function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
        [string] $PhpVersion = ''
    )
    begin {
        $sdkVersion = "php-sdk-2.8.4"
        $url = "https://github.com/php/php-sdk-binary-tools/archive/$sdkVersion.zip"
        if ($PhpVersion -match '^5\.[3-6](\.|$)') {
            $sdkVersion = 'a05a0b4713671f0939dde9759659f76e808f6578'
            $url = "https://github.com/php/php-sdk-binary-tools/archive/$sdkVersion.zip"
        } elseif ($PhpVersion -match '^7\.[01](\.|$)') {
            $sdkVersion = 'php-sdk-2.1.10'
            $url = "https://github.com/php/php-sdk-binary-tools/archive/$sdkVersion.zip"
        } elseif ($PhpVersion -match '^7\.2(\.|$)') {
            # Keep PHP 7.2's mkdist.php on the compatible SDK packaging interpreter.
            $sdkVersion = 'ef0f77253e50beee3e83195d42fb2b89e0c5147e'
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
