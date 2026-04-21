function Add-Vs {
    <#
    .SYNOPSIS
        Add the required Visual Studio components.
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
        $vsWhereUrl = 'https://github.com/microsoft/vswhere/releases/latest/download/vswhere.exe'
    }
    process {
        $Config = $VsConfig.vs.$VsVersion

        $installerDir = Join-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio" 'Installer'
        $vswherePath = Join-Path $installerDir 'vswhere.exe'
        if (-not (Test-Path $vswherePath)) {
            if (-not (Test-Path $installerDir)) {
                New-Item -Path $installerDir -ItemType Directory -Force | Out-Null
            }
            Get-File -Url $vsWhereUrl -OutFile $vswherePath
        }

        $instances = & $vswherePath -products '*' -format json 2> $null | ConvertFrom-Json
        $vsInst = $instances | Select-Object -First 1

        $components = @($Config.components)
        if ($Arch -eq 'arm64' -and $Config.PSObject.Properties.Name -contains 'arm64_components') {
            $components += @($Config.arm64_components)
        }
        $componentArgs = $components | Select-Object -Unique | ForEach-Object { '--add'; $_ }

        if ($vsInst) {
            [string]$channel = $vsInst.installationVersion.Split('.')[0]
            $productId = $null
            if ($vsInst.catalog -and $vsInst.catalog.PSObject.Properties['productId']) {
                $productId = $vsInst.catalog.productId
            } elseif ($vsInst.PSObject.Properties['productId']) {
                $productId = $vsInst.productId
            }
            if ($productId -match '(Enterprise|Professional|Community)$' ) {
                $exe = "vs_$($Matches[1].ToLower()).exe"
            } else {
                $exe = 'vs_buildtools.exe'
            }

            $installerUrl = "https://aka.ms/vs/$channel/release/$exe"
            $installerPath = Join-Path $env:TEMP $exe

            Get-File -Url $installerUrl -OutFile $installerPath

            & $installerPath modify `
                --installPath $vsInst.installationPath `
                --quiet --wait --norestart --nocache `
                @componentArgs 2>&1 | ForEach-Object { Write-Host $_ }
        } else {
            $channel = $VsVersion -replace '\D', ''
            $exe = 'vs_buildtools.exe'
            $installerUrl = "https://aka.ms/vs/$channel/release/$exe"
            $installerPath = Join-Path $env:TEMP $exe

            Get-File -Url $installerUrl -OutFile $installerPath
            & $installerPath `
                --quiet --wait --norestart --nocache `
                @componentArgs 2>&1 | ForEach-Object { Write-Host $_ }
        }
    }
    end {
    }
}
