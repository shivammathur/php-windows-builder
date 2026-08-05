function Set-HMailServerTestEnvironment {
    <#
    .SYNOPSIS
        Install and configure hMailServer for the Windows mail tests.
    .PARAMETER PhpBinDirectory
        Directory containing php.exe and the ext directory.
    .PARAMETER TestsDirectoryPath
        Root path of the extracted php-src test tree.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP bin directory')]
        [ValidateNotNullOrEmpty()]
        [string] $PhpBinDirectory,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP tests directory path')]
        [ValidateNotNullOrEmpty()]
        [string] $TestsDirectoryPath
    )
    process {
        $setupScript = Join-Path $TestsDirectoryPath 'appveyor\setup_hmailserver.php'
        if (-not (Test-Path -LiteralPath $setupScript)) {
            $setupScript = Join-Path $TestsDirectoryPath '.github\setup_hmailserver.php'
        }
        if (-not (Test-Path -LiteralPath $setupScript)) {
            return
        }

        Get-File -Url 'https://downloads.php.net/~windows/php-sdk/deps/vs18/x64/hmailserver-5.7.0-vs18-x64.zip' -OutFile hMailServer.zip
        Expand-Archive -Path hMailServer.zip -DestinationPath hMailServer -Force
        Start-Process -FilePath 'hMailServer\bin\hMailServer.exe' -ArgumentList '/verysilent' -Wait

        $phpExe = Join-Path $PhpBinDirectory 'php.exe'
        $extensionDirectory = Join-Path $PhpBinDirectory 'ext'
        & $phpExe -n "-dextension_dir=$extensionDirectory" '-dextension=com_dotnet' $setupScript
    }
}
