function Install-VcRedist {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('vc9', 'vc11')]
        [string] $VsVersion,
        [Parameter(Mandatory = $true)]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    $config = Get-Content (Join-Path $PSScriptRoot '..\config\vs.json') -Raw | ConvertFrom-Json
    $installer = Join-Path $Directory 'vcredist.exe'
    Get-File -Url ($config.redistributables.$VsVersion -f $Arch) -OutFile $installer
    $result = Start-Process $installer -ArgumentList '/q', '/norestart' -Wait -PassThru
    if ($result.ExitCode -notin @(0, 1638, 3010)) { throw "$VsVersion runtime installation failed: $($result.ExitCode)" }
}
