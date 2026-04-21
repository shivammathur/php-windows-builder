function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $false, Position=0, HelpMessage='PHP Architecture')]
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
        $existingDirectories = @(Get-ChildItem -Directory | Select-Object -ExpandProperty Name)
        Get-File -Url $url -OutFile php-sdk.zip
        Expand-Archive -Path php-sdk.zip -DestinationPath .
        $sdkDirectory = Get-ChildItem -Directory -Filter 'php-sdk-binary-tools-*' |
            Where-Object { $existingDirectories -notcontains $_.Name } |
            Select-Object -First 1

        if ($null -eq $sdkDirectory) {
            throw "Failed to locate the extracted PHP SDK directory for $sdkRepository@$sdkRef"
        }

        Rename-Item -Path $sdkDirectory.FullName -NewName php-sdk
    }
    end {
    }
}
