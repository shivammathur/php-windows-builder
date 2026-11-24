function Add-VC11 {
    [CmdletBinding()]
    param()

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
}
