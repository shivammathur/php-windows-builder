function Get-PhpSdk {
    <#
    .SYNOPSIS
        Get the PHP SDK.
    #>
    [OutputType()]
    param (
    )
    begin {
        $sdkVersion = "php-sdk-2.8.4"
        $url = "https://github.com/php/php-sdk-binary-tools/archive/$sdkVersion.zip"
        if ($env:PGO_SDK_REF) {
            $sdkVersion = $env:PGO_SDK_REF
            $url = "https://github.com/$($env:PGO_SDK_REPOSITORY)/archive/$sdkVersion.zip"
        }
    }
    process {
        Get-File -Url $url -OutFile php-sdk.zip
        Expand-Archive -Path php-sdk.zip -DestinationPath .
        Rename-Item -Path php-sdk-binary-tools-$sdkVersion php-sdk
        # Validation-only diagnostics in the downloaded SDK copy. Preserve all
        # sweep/merge operations, weighting and profile cleanup behavior.
        $profileTool = Join-Path (Resolve-Path php-sdk).Path 'lib/php/libsdk/SDK/Build/PGO/Tool/PGO.php'
        $profileSource = [IO.File]::ReadAllText($profileTool)
        $mergeCall = 'shell_exec("pgomgr /merge:$weight $pgc $pgd");'
        if (($profileSource.Split($mergeCall).Count - 1) -ne 1) { throw 'Expected one profile merge call' }
        $mergeDiagnostics = @'
$mergeOutput = (string) shell_exec("pgomgr /merge:$weight $pgc $pgd 2>&1");
                echo $mergeOutput;
                file_put_contents(getenv("RUNNER_TEMP") . DIRECTORY_SEPARATOR . "pgo-merge.log", $mergeOutput, FILE_APPEND);
'@
        [IO.File]::WriteAllText($profileTool, $profileSource.Replace($mergeCall, $mergeDiagnostics))
        if ($env:GITHUB_ENV) {
            "PHP_SDK_TEST_DIR=$((Resolve-Path php-sdk).Path)" >> $env:GITHUB_ENV
        }
    }
    end {
    }
}
