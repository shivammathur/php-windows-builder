function Add-PgoRequirements {
    <#
    .SYNOPSIS
        Install Visual Studio components required for PGO-enabled PHP builds.
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
        [Parameter(Mandatory = $false, Position=1, HelpMessage='Target architecture')]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string] $Arch = 'x64'
    )
    begin {
        $jsonPath = [System.IO.Path]::Combine($PSScriptRoot, '..\config\vs.json')
        $vsWhereUrl = 'https://github.com/microsoft/vswhere/releases/latest/download/vswhere.exe'
    }
    process {
        if ($Arch -ne 'arm64') {
            return
        }

        $jsonContent = Get-Content -Path $jsonPath -Raw
        $VsConfig = ConvertFrom-Json -InputObject $jsonContent
        $Config = $VsConfig.vs.$VsVersion
        if ($null -eq $Config -or $Config.PSObject.Properties.Name -notcontains 'pgo_components') {
            return
        }

        [string[]] $components = @(@($Config.pgo_components) | Select-Object -Unique)
        if ($components.Length -eq 0) {
            return
        }

        $installerDir = Join-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio" 'Installer'
        $vswherePath = Join-Path $installerDir 'vswhere.exe'
        if (-not (Test-Path $vswherePath)) {
            if (-not (Test-Path $installerDir)) {
                New-Item -Path $installerDir -ItemType Directory -Force | Out-Null
            }
            Get-File -Url $vsWhereUrl -OutFile $vswherePath
        }

        $installedPath = & $vswherePath -latest -products * -requires $components -property installationPath 2> $null | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($installedPath)) {
            return
        }

        Write-Host "Installing Visual Studio PGO components for $VsVersion ($Arch)"

        $instances = & $vswherePath -latest -products '*' -format json 2> $null | ConvertFrom-Json
        $vsInst = $instances | Select-Object -First 1
        if (-not $vsInst) {
            throw "Visual Studio installation not found for PGO components"
        }

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
        $componentArgs = $components | ForEach-Object { '--add'; $_ }

        Get-File -Url $installerUrl -OutFile $installerPath
        & $installerPath modify `
            --installPath $vsInst.installationPath `
            --quiet --wait --norestart --nocache `
            @componentArgs 2>&1 | ForEach-Object { Write-Host $_ }

        $installedPath = & $vswherePath -latest -products * -requires $components -property installationPath 2> $null | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($installedPath)) {
            throw "PGO Visual Studio components are not available for $VsVersion ($Arch)"
        }
    }
    end {
    }
}
