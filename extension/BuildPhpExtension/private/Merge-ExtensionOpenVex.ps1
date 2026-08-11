function Merge-ExtensionOpenVex {
    <#
    .SYNOPSIS
        Merge dependency OpenVEX documents with vexctl.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Files,
        [Parameter(Mandatory = $true)]
        [string] $OutputPath,
        [string] $VexctlPath = ''
    )

    $Files = @($Files | Where-Object { $_ })
    if($Files.Count -eq 0) { return }
    if(-not($VexctlPath)) { $VexctlPath = Get-SbomTool -Name vexctl }
    $arguments = @('--log-level', 'error', 'merge') + $Files
    $output = & $VexctlPath @arguments
    $succeeded = $?
    $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
    if(-not($succeeded) -or ($null -ne $exitCode -and $exitCode -ne 0)) {
        throw "vexctl failed with exit code $exitCode."
    }
    Write-SbomJson -InputObject (($output -join [Environment]::NewLine) | ConvertFrom-Json) -Path $OutputPath
}
