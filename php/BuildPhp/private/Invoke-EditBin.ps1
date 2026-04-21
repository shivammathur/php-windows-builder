function Invoke-EditBin {
    <#
    .SYNOPSIS
        Run editbin.exe to set the stack size on an executable.
    .PARAMETER Exe
        Path to the target executable.
    .PARAMETER StackSize
        Stack size in bytes.
    .PARAMETER Target
        Target architecture subfolder under Hostx64 (x64 or x86)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage='Path to target executable')]
        [ValidateNotNullOrEmpty()]
        [string] $Exe,
        [Parameter(Mandatory=$true, Position=1, HelpMessage='Stack reserve size in bytes')]
        [int] $StackSize,
        [Parameter(Mandatory=$true, Position=2, HelpMessage='Architecture')]
        [ValidateSet('x64','x86','arm64')]
        [string] $Arch
    )

    process {
        if (-not (Test-Path -LiteralPath $Exe)) {
            throw "Target executable not found: $Exe"
        }

        $hostArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } elseif ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'AMD64' }
        $hostFolder = if ($hostArch -match 'ARM64') { 'Hostarm64' } else { 'Hostx64' }
        $pattern = "C:\\Program Files\\Microsoft Visual Studio\\2022\\*\\VC\\Tools\\MSVC\\*\\bin\\$hostFolder\\$Arch\\editbin.exe"
        $editbin = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
                   Sort-Object { Split-Path $_.DirectoryName -Leaf } -Descending |
                   Select-Object -First 1

        if (-not $editbin) {
            throw "editbin.exe not found under VS2022 paths."
        }

        & $editbin.FullName "/STACK:$StackSize" $Exe
        if ($LASTEXITCODE) {
            throw "editbin failed with exit code $LASTEXITCODE"
        }
    }
}
