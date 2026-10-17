function Invoke-PhpSdkStarter {
    <#
    .SYNOPSIS
        Invoke phpsdk-starter.bat with the provided build configuration.
    .PARAMETER BuildDirectory
        Build directory containing the PHP SDK.
    .PARAMETER VsConfig
        Visual Studio configuration for the build.
    .PARAMETER Arch
        PHP Architecture
    .PARAMETER Task
        Task script to run through the PHP SDK starter.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Build directory')]
        [string] $BuildDirectory,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Visual Studio configuration')]
        [PSCustomObject] $VsConfig,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=3, HelpMessage='Task script')]
        [string] $Task
    )
    begin {
    }
    process {
        $env:PGO_EVIDENCE_SCRIPT = Join-Path $PSScriptRoot '..\..\..\scripts\Save-PgoProfile.ps1'
        $env:PGO_RESERVATION_SCRIPT = Join-Path $PSScriptRoot '..\..\..\scripts\Limit-PgoReservation.ps1'
        $toolsetArgs = if ($VsConfig.vs -eq 'vs18') { @() } else { @('-s', $VsConfig.toolset) }
        $resources = Join-Path $env:RUNNER_TEMP 'pgo-resources.jsonl'
        $monitor = Start-Job -ArgumentList $resources -ScriptBlock {
            param($destination)
            $sample = 0
            while ($true) {
                $memory = Get-CimInstance Win32_OperatingSystem
                $processes = @(Get-Process -Name php-cgi,mysqld,cl,link -ErrorAction SilentlyContinue |
                    Select-Object Id,ProcessName,WorkingSet64,PrivateMemorySize64,VirtualMemorySize64,HandleCount)
                $tcp = if (($sample++ % 5) -eq 0) {
                    @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Group-Object State | Select-Object Name,Count)
                } else { @() }
                [ordered]@{
                    time = [DateTime]::UtcNow.ToString('o')
                    free_physical_kib = $memory.FreePhysicalMemory
                    free_virtual_kib = $memory.FreeVirtualMemory
                    total_virtual_kib = $memory.TotalVirtualMemorySize
                    processes = $processes
                    tcp_states = $tcp
                } | ConvertTo-Json -Compress -Depth 5 | Add-Content $destination
                Start-Sleep -Seconds 2
            }
        }
        try {
            & "$BuildDirectory\php-sdk\phpsdk-starter.bat" -c $VsConfig.vs -a $Arch @toolsetArgs -t $Task 2>&1 |
                Tee-Object -FilePath (Join-Path $env:RUNNER_TEMP 'php-sdk-build.log')
            if ($LASTEXITCODE -ne 0) {
                throw "build failed with errorlevel $LASTEXITCODE"
            }
        } finally {
            Stop-Job $monitor
            Remove-Job $monitor
        }
    }
    end {
    }
}
