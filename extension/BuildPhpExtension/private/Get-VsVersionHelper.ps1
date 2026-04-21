function Get-VsVersionHelper {
    <#
    .SYNOPSIS
        Helper to get the Visual Studio version and toolset.
    .PARAMETER VsConfig
        Visual Studio Configuration
    .PARAMETER VsVersion
        Visual Studio Version
    .PARAMETER Arch
        Target architecture.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Visual Studio Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $VsVersion,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Visual Studio Configuration')]
        [PSCustomObject] $VsConfig,
        [Parameter(Mandatory = $false, Position=2, HelpMessage='Target architecture')]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch = 'x64'
    )
    begin {
    }
    process {
        $installerDir = Join-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio" 'Installer'
        $vswherePath = Join-Path $installerDir 'vswhere.exe'
        if (-not (Test-Path $vswherePath)) {
            throw "vswhere is not available"
        }
        $MSVCDirectory = & $vswherePath -latest -products * -find "VC\Tools\MSVC"
        $selectedToolset = $null
        $selectedToolsetPath = $null
        $minor = $null
        foreach ($toolset in (Get-ChildItem $MSVCDirectory)) {
            $toolsetMajorVersion, $toolsetMinorVersion = $toolset.Name.split(".")[0,1]
            $requiredVs = $VsConfig.vs.$VsVersion
            $majorVersionCheck = [int]$requiredVs.major -eq [int]$toolsetMajorVersion
            $minorLowerBoundCheck = [int]$toolsetMinorVersion -ge [int]$requiredVs.minorMin
            $minorUpperBoundCheck = ($null -eq $requiredVs.minorMax) -or ([int]$toolsetMinorVersion -le [int]$requiredVs.minorMax)
            if ($majorVersionCheck -and $minorLowerBoundCheck -and $minorUpperBoundCheck) {
                if($null -eq $minor -or [int]$toolsetMinorVersion -gt [int]$minor) {
                    $selectedToolset = $toolset.Name.Trim()
                    $selectedToolsetPath = $toolset.FullName
                    $minor = $toolsetMinorVersion
                }
            }
        }

        if (-not $selectedToolset) {
            throw "toolset not available"
        }

        if ($Arch -eq 'arm64') {
            $arm64CompilerPaths = @(
                (Join-Path $selectedToolsetPath 'bin\Hostx64\arm64\cl.exe'),
                (Join-Path $selectedToolsetPath 'bin\Hostarm64\arm64\cl.exe')
            )
            if (-not ($arm64CompilerPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)) {
                throw "ARM64 compiler support is not available for toolset $selectedToolset"
            }
        }

        return $selectedToolset
    }
    end {
    }
}
