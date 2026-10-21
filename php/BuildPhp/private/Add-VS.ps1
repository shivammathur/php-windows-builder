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
        if ($VsVersion -eq 'vc9') {
            # Administrative extraction avoids the IDE's obsolete .NET/SQL
            # prerequisites. Use the compiler and SDK from the same SP1 media.
            $iso = Join-Path $env:TEMP 'VS2008ExpressWithSP1.iso'
            Get-File -Url 'https://download.microsoft.com/download/E/8/E/E8EEB394-7F42-4963-A2D8-29559B738298/VS2008ExpressWithSP1ENUX1504728.iso' -OutFile $iso
            $media = Join-Path $env:TEMP 'vs2008-express'
            & 7z x $iso "-o$media" 'VCExpress/*' -y | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Extracting VS 2008 SP1 failed' }
            $packages = @(
                @{Exe='Ixpvc.exe'; Msi='vs_setup.msi'; Name='compiler'},
                @{Exe='WCU\WinSDK\WinSDK_Build.exe'; Msi='VistaClientHeadersLibs-x86.msi'; Name='sdk'},
                @{Exe='WCU\WinSDK\WinSDK_Exp32Tools.exe'; Msi='VistaClientExpressTools-x86.msi'; Name='tools'}
            )
            foreach ($package in $packages) {
                $payload = Join-Path $media $package.Name
                & 7z x "$media\VCExpress\$($package.Exe)" "-o$payload" -y | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Extracting VC9 $($package.Name) failed" }
                if ($package.Name -eq 'compiler') {
                    # The MSI's uncompressed file resolves relative to its root,
                    # whereas the self-extractor stores it in WCU.
                    Copy-Item "$payload\WCU\vcredist_x86.exe" "$payload\vcredist_x86.exe"
                }
                $destination = Join-Path $media "$($package.Name)-extracted"
                $arguments = @('/a', "`"$payload\$($package.Msi)`"", '/qn', "TARGETDIR=`"$destination`"", '/L*v', "`"$env:TEMP\vs2008-$($package.Name).log`"")
                $result = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
                if ($result.ExitCode -notin @(0, 3010)) { throw "Extracting VC9 $($package.Name) MSI failed: $($result.ExitCode)" }
            }
            $vsRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio 9.0'
            $vc = (Get-ChildItem "$media\compiler-extracted" -Recurse -Filter vcvarsall.bat | Select-Object -First 1).Directory
            if (-not $vc) { throw 'VC9 compiler directory missing' }
            New-Item $vsRoot -ItemType Directory -Force | Out-Null
            # The administrative image uses the source name Vc7 for VC.
            Copy-Item $vc.FullName "$vsRoot\VC" -Recurse -Force
            Copy-Item "$($vc.Parent.FullName)\Common7" "$vsRoot\Common7" -Recurse -Force
            $sdkRoot = Join-Path $vsRoot 'Windows SDK'
            foreach ($part in @(@{Root='sdk'; File='Windows.h'; Dir='Include'}, @{Root='sdk'; File='kernel32.lib'; Dir='Lib'}, @{Root='tools'; File='rc.exe'; Dir='Bin'})) {
                $file = Get-ChildItem "$media\$($part.Root)-extracted" -Recurse -Filter $part.File | Select-Object -First 1
                if (-not $file) { throw "VC9 SDK file missing: $($part.File)" }
                New-Item "$sdkRoot\$($part.Dir)" -ItemType Directory -Force | Out-Null
                Copy-Item "$($file.Directory.FullName)\*" "$sdkRoot\$($part.Dir)" -Recurse -Force
            }
            $redist = Join-Path $media 'vcredist_x86.exe'
            Get-File -Url 'https://download.microsoft.com/download/5/d/8/5d8c65cb-c849-4025-8e95-c3966cafd8ae/vcredist_x86.exe' -OutFile $redist
            $result = Start-Process $redist -ArgumentList '/q', '/norestart' -Wait -PassThru
            if ($result.ExitCode -notin @(0, 1638, 3010)) { throw "VC9 runtime installation failed: $($result.ExitCode)" }
            Remove-Item $iso -Force
            Remove-Item $media -Recurse -Force
            return
        }
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
