Function Invoke-Build {
    <#
    .SYNOPSIS
        Build the extension
    .PARAMETER Config
        Extension Configuration
    #>
    [OutputType()]
    param(
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Extension Configuration')]
        [PSCustomObject] $Config
    )
    begin {
    }
    process {
        Add-StepLog "Building $($Config.name) extension"
        try {
            Set-GAGroup start
            Update-CurlDependencyConfig -PhpVersion $Config.php_version | Out-Null

            $task = [System.IO.Path]::Combine($PSScriptRoot, '..\config\task.bat')
            $options = $Config.options
            if ($Config.debug_symbols) {
                $options += " --enable-debug-pack"
            }
            Set-Content -Path task.bat -Value (Get-Content -Path $task -Raw).Replace("OPTIONS", $options)
            $starterCommand = Get-PhpSdkStarterCommand -SdkDirectory "php-sdk" `
                                                       -VsVersion $Config.vs_version `
                                                       -VsToolset $Config.vs_toolset `
                                                       -Arch $Config.Arch `
                                                       -Task 'task.bat'

            $ref = $Config.ref
            if($env:ARTIFACT_NAMING_SCHEME -eq 'pecl') {
                $ref = $Config.ref.ToLower()
            }
            $suffix = "php_" + (@(
                $Config.name,
                $ref,
                $Config.php_version,
                $Config.ts,
                    $Config.vs_version,
                    $Config.arch
                ) -join "-")
            & $starterCommand.Path @($starterCommand.Arguments) | Tee-Object -FilePath "build-$suffix.txt"
            Set-GAGroup end
            if(-not(Test-Path "$((Get-Location).Path)\$($Config.build_directory)\php_$($Config.name).dll")) {
                throw "Failed to build the extension"
            }
            Add-BuildLog tick $Config.name "Extension $($Config.name) built successfully"
        } catch {
            Add-BuildLog cross $Config.name "Failed to build the extension"
            throw
        }
    }
    end {
    }
}
