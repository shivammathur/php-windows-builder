function Add-VS {
    <#
    .SYNOPSIS
        Add the required Visual Studio components.
    .PARAMETER VsConfig
        Visual Studio Configuration
    .PARAMETER VsVersion
        Visual Studio Version
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Visual Studio Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $VsVersion,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Visual Studio Configuration')]
        [PSCustomObject] $VsConfig
    )
    begin {
        $vsWhereUrl = 'https://github.com/microsoft/vswhere/releases/latest/download/vswhere.exe'
    }
    process {
        if ($VsVersion -eq 'vc11') {
            $iso = Join-Path $env:TEMP 'VS2012_WDX_ENU.iso'
            Get-File -Url 'https://download.microsoft.com/download/1/F/5/1F519CC5-0B90-4EA3-8159-33BFB97EF4D9/VS2012_WDX_ENU.iso' -OutFile $iso
            $media = Join-Path $env:TEMP 'vs2012-express'
            & 7z x $iso "-o$media" -y | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Extracting VS 2012 failed' }
            $installer = Join-Path $media 'wdexpress_full.exe'
            $result = Start-Process $installer -ArgumentList '/quiet', '/norestart', '/log', "$env:TEMP\vs2012-install.log" -Wait -PassThru
            if ($result.ExitCode -notin @(0, 3010)) {
                throw "VS 2012 installation failed: $($result.ExitCode)"
            }
            # The web bootstrapper references retired download URLs. Use the
            # complete offline media so all update payloads resolve locally.
            $updateIso = Join-Path $env:TEMP 'VS2012.5.iso'
            Get-File -Url 'https://download.microsoft.com/download/1/7/A/17A8493D-BB25-4811-8242-CCCB74EF982E/VS2012.5.iso' -OutFile $updateIso
            $updateMedia = Join-Path $env:TEMP 'vs2012-update'
            & 7z x $updateIso "-o$updateMedia" -y | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Extracting VS 2012 Update 5 failed' }
            $update = Join-Path $updateMedia 'VS2012.5.exe'
            $result = Start-Process $update -ArgumentList '/quiet', '/norestart', '/log', "$env:TEMP\vs2012-update.log" -Wait -PassThru
            if ($result.ExitCode -notin @(0, 3010)) {
                throw "VS 2012 Update 5 installation failed: $($result.ExitCode)"
            }
            Remove-Item $iso, $updateIso -Force
            Remove-Item $media, $updateMedia -Recurse -Force
            return
        }

        $Config = $VsConfig.vs.$VsVersion

        $installerDir = Join-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio" 'Installer'
        $vswherePath = Join-Path $installerDir 'vswhere.exe'
        if (-not (Test-Path $vswherePath)) {
            if (-not (Test-Path $installerDir)) {
                New-Item -Path $installerDir -ItemType Directory -Force | Out-Null
            }
            Get-File -Url $vsWhereUrl -OutFile $vswherePath
        }

        $requiredChannel = [int]($VsVersion -replace '\D', '')
        $instances = & $vswherePath -latest -products '*' -format json 2> $null | ConvertFrom-Json
        $vsInst = $instances | Select-Object -First 1
        if ($vsInst -and [int]$vsInst.installationVersion.Split('.')[0] -lt $requiredChannel) {
            $vsInst = $null
        }

        $componentArgs = $Config.components | ForEach-Object { '--add'; $_ }

        if ($vsInst) {
            [int]$channel = $vsInst.installationVersion.Split('.')[0]
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

            $releaseChannel = if ($channel -ge 18) { 'stable' } else { 'release' }
            $installerUrl = "https://aka.ms/vs/$channel/$releaseChannel/$exe"
            $installerPath = Join-Path $env:TEMP $exe

            Get-File -Url $installerUrl -OutFile $installerPath

            & $installerPath modify `
                --installPath $vsInst.installationPath `
                --quiet --wait --norestart --nocache `
                @componentArgs 2>&1 | ForEach-Object { Write-Host $_ }
        } else {
            $channel = $requiredChannel
            $exe = 'vs_buildtools.exe'
            $releaseChannel = if ($channel -ge 18) { 'stable' } else { 'release' }
            $installerUrl = "https://aka.ms/vs/$channel/$releaseChannel/$exe"
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
