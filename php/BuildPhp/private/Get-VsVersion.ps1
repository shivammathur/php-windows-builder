function Get-VsVersion {
    <#
    .SYNOPSIS
        Get the Visual Studio version.
    .PARAMETER PhpVersion
        PHP Version
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion
    )
    begin {
        $jsonPath = [System.IO.Path]::Combine($PSScriptRoot, '..\config\vs.json')
    }
    process {
        $jsonContent = Get-Content -Path $jsonPath -Raw
        $VsConfig = ConvertFrom-Json -InputObject $jsonContent
        if($PhpVersion -eq 'master') { $majorMinor = 'master'; } else { $majorMinor = $PhpVersion.Substring(0, 3); }
        $VsVersion = $($VsConfig.php.$majorMinor)
        if (-not [string]::IsNullOrWhiteSpace($env:PHP_VS_VERSION_OVERRIDE)) {
            $VsVersion = $env:PHP_VS_VERSION_OVERRIDE
            if ($VsConfig.vs.PSObject.Properties.Name -notcontains $VsVersion) {
                throw "Unsupported Visual Studio version override: $VsVersion"
            }
        }

        if ($env:PHP_SKIP_VS_TOOLSET_CHECK -eq '1') {
            return [PSCustomObject]@{
                vs = $VsVersion
                toolset = $null
            }
        }

        $selectedToolset = $null
        try {
            $selectedToolset = Get-VsVersionHelper -VsVersion $VsVersion -VsConfig $VsConfig
        } catch {
            Add-VS -VsVersion $VsVersion -VsConfig $VsConfig
            $selectedToolset = Get-VsVersionHelper -VsVersion $VsVersion -VsConfig $VsConfig
        }
        return [PSCustomObject]@{
            vs = $VsVersion
            toolset = $selectedToolset
        }
    }
    end {
    }
}
