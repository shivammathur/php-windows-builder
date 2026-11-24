function Add-VC9 {
    [CmdletBinding()]
    param()

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
    New-Item "$vsRoot\VC", "$vsRoot\Common7" -ItemType Directory -Force | Out-Null
    # The administrative image uses the source name Vc7 for VC.
    Copy-Item "$($vc.FullName)\*" "$vsRoot\VC" -Recurse -Force
    Copy-Item "$($vc.Parent.FullName)\Common7\*" "$vsRoot\Common7" -Recurse -Force
    $sdkRoot = Join-Path $vsRoot 'Windows SDK'
    foreach ($part in @(@{Root='sdk'; File='Windows.h'; Dir='Include'}, @{Root='sdk'; File='kernel32.lib'; Dir='Lib'}, @{Root='tools'; File='rc.exe'; Dir='Bin'})) {
        $file = Get-ChildItem "$media\$($part.Root)-extracted" -Recurse -Filter $part.File | Select-Object -First 1
        if (-not $file) { throw "VC9 SDK file missing: $($part.File)" }
        New-Item "$sdkRoot\$($part.Dir)" -ItemType Directory -Force | Out-Null
        Copy-Item "$($file.Directory.FullName)\*" "$sdkRoot\$($part.Dir)" -Recurse -Force
    }
    Install-VcRedist -VsVersion vc9 -Arch x86 -Directory $media
    Remove-Item $iso -Force
    Remove-Item $media -Recurse -Force
}
