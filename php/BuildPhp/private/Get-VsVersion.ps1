function Get-VsVersion {
    <#
    .SYNOPSIS
        Get the Visual Studio version.
    .PARAMETER PhpVersion
        PHP Version
    .PARAMETER Arch
        Target architecture.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $false, Position=1, HelpMessage='Target architecture')]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch = 'x64'
    )
    begin {
        $jsonPath = [System.IO.Path]::Combine($PSScriptRoot, '..\config\vs.json')
    }
    process {
        $jsonContent = Get-Content -Path $jsonPath -Raw
        $VsConfig = ConvertFrom-Json -InputObject $jsonContent
        if($PhpVersion -eq 'master') { $majorMinor = 'master'; } else { $majorMinor = $PhpVersion.Substring(0, 3); }
        $VsVersion = $($VsConfig.php.$majorMinor)
        if ($Arch -eq 'arm64' -and $VsVersion -notin @('vs16', 'vs17', 'vs18')) {
            throw "ARM64 builds are supported only for PHP versions that use the VS2019, VS2022 or VS2026 toolchains. PHP version $PhpVersion resolves to $VsVersion."
        }
        $selectedToolset = $null
        try {
            $selectedToolset = Get-VsVersionHelper -VsVersion $VsVersion -VsConfig $VsConfig -Arch $Arch
        } catch {
            Add-VS -VsVersion $VsVersion -VsConfig $VsConfig -Arch $Arch
            $selectedToolset = Get-VsVersionHelper -VsVersion $VsVersion -VsConfig $VsConfig -Arch $Arch
        }
        return [PSCustomObject]@{
            vs = $VsVersion
            toolset = $selectedToolset
        }
    }
    end {
    }
}
