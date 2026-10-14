param([Parameter(Mandatory)][ValidateSet('14.50','14.52')][string]$Toolset)
$ErrorActionPreference = 'Stop'
$evidence = Join-Path $env:GITHUB_WORKSPACE 'toolset-evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$instance = @(& $vswhere -products '*' -version '[18,19)' -format json | ConvertFrom-Json) | Select-Object -First 1
if (!$instance) { throw 'VS18 is required for this diagnostic' }
$instance | ConvertTo-Json -Depth 20 | Set-Content "$evidence/vs-before.json"
$components = if ($Toolset -eq '14.50') {
    @('Microsoft.VisualStudio.Component.VC.14.50.18.0.ARM64', 'Microsoft.VisualStudio.Component.VC.14.50.18.0.ATL.ARM64')
} else {
    @('Microsoft.VisualStudio.Component.VC.Preview.ARM64', 'Microsoft.VisualStudio.Component.VC.Preview.ATL.ARM64')
}
$edition = switch -Regex ($instance.productId) {
    'Enterprise$' { 'enterprise'; break }
    'Professional$' { 'professional'; break }
    'Community$' { 'community'; break }
    default { 'buildtools' }
}
$installer = Join-Path $env:TEMP "vs_$edition.exe"
Invoke-WebRequest "https://aka.ms/vs/18/stable/vs_$edition.exe" -OutFile $installer
$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Invalid VS installer signature' }
$updateArguments = @('update', '--installPath', ('"{0}"' -f $instance.installationPath), '--channelUri', 'https://aka.ms/vs/18/stable/channel', '--quiet', '--wait', '--norestart', '--nocache')
$update = Start-Process $installer -ArgumentList $updateArguments -PassThru -Wait
if ($update.ExitCode -notin @(0,3010)) { throw "VS update failed: $($update.ExitCode)" }
@(& $vswhere -products '*' -version '[18,19)' -format json | ConvertFrom-Json) |
    ConvertTo-Json -Depth 20 | Set-Content "$evidence/vs-updated.json"
$arguments = @('modify', '--installPath', ('"{0}"' -f $instance.installationPath), '--quiet', '--wait', '--norestart', '--nocache')
foreach ($component in $components) { $arguments += @('--add', $component) }
$process = Start-Process $installer -ArgumentList $arguments -PassThru -Wait
if ($process.ExitCode -notin @(0,3010)) { throw "VS installer failed: $($process.ExitCode)" }
$folder = Get-ChildItem (Join-Path $instance.installationPath 'VC/Tools/MSVC') -Directory |
    Where-Object { $_.Name.StartsWith("$Toolset.") -and (Test-Path "$($_.FullName)/bin/Hostarm64/arm64/cl.exe") } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$folder) { throw "Requested native ARM64 toolset $Toolset was not installed" }
$compilerVersion = [version](Get-Item "$($folder.FullName)/bin/Hostarm64/arm64/cl.exe").VersionInfo.FileVersion
$minimum = if ($Toolset -eq '14.50') { [version]'19.50.35739.0' } else { [version]'19.52.36815.0' }
if ($compilerVersion -lt $minimum) { throw "Installed compiler $compilerVersion predates the reviewed current catalog ($minimum)" }
$inventory = Get-ChildItem "$($folder.FullName)/bin/Hostarm64/arm64" -File |
    Where-Object Name -Match '^(cl|link|c1|c1xx|c2|pgomgr|pgort|mspdb|msobj)' |
    ForEach-Object { @{path=$_.FullName; fileVersion=$_.VersionInfo.FileVersion; sha256=(Get-FileHash $_.FullName).Hash} }
@{requested=$Toolset; folder=$folder.FullName; components=$components; updateExit=$update.ExitCode; installerExit=$process.ExitCode; files=@($inventory)} |
    ConvertTo-Json -Depth 10 | Set-Content "$evidence/installation.json"
Add-Content $env:GITHUB_ENV "DIAGNOSTIC_TOOLSET=$($folder.Name)"
Add-Content $env:GITHUB_ENV "DIAGNOSTIC_TOOLSET_PATH=$($folder.FullName)"
Write-Host "Installed requested toolset $($folder.FullName)"
