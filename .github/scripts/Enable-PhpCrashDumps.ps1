[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $DumpDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64')]
    [string] $Arch,

    [Parameter(Mandatory = $true)]
    [ValidateSet('nts', 'ts')]
    [string] $Ts
)

$ErrorActionPreference = 'Stop'

$dumpDirectoryPath = [System.IO.Path]::GetFullPath($DumpDirectory)
New-Item -Path $dumpDirectoryPath -ItemType Directory -Force | Out-Null

$werRoot = 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting'
New-Item -Path $werRoot -Force | Out-Null
New-ItemProperty -Path $werRoot -Name DontShowUI -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $werRoot -Name Disabled -PropertyType DWord -Value 0 -Force | Out-Null

foreach ($executable in @('php.exe', 'php-cgi.exe', 'phpdbg.exe', 'php-win.exe')) {
    $dumpKey = Join-Path $werRoot "LocalDumps\$executable"
    New-Item -Path $dumpKey -Force | Out-Null
    New-ItemProperty -Path $dumpKey -Name DumpFolder -PropertyType ExpandString -Value $dumpDirectoryPath -Force | Out-Null
    New-ItemProperty -Path $dumpKey -Name DumpCount -PropertyType DWord -Value 100 -Force | Out-Null
    New-ItemProperty -Path $dumpKey -Name DumpType -PropertyType DWord -Value 2 -Force | Out-Null
}

Write-Host "Enabled full Windows Error Reporting dumps in $dumpDirectoryPath"
Get-ChildItem -Path (Join-Path $werRoot 'LocalDumps') | ForEach-Object {
    Get-ItemProperty -Path $_.PSPath | Format-List PSChildName, DumpFolder, DumpCount, DumpType
}

$debuggerArch = if ($Arch -eq 'x86') { 'x86' } else { 'x64' }
$cdbCandidates = @(
    "$env:ProgramFiles\Windows Kits\10\Debuggers\$debuggerArch\cdb.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\$debuggerArch\cdb.exe"
)
$cdb = $cdbCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $cdb) {
    $sdkInstaller = Join-Path $env:RUNNER_TEMP 'winsdksetup.exe'
    Write-Host 'cdb.exe was not found; installing the Windows SDK debugging tools.'
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2243390' -OutFile $sdkInstaller -UseBasicParsing
    $sdkProcess = Start-Process -FilePath $sdkInstaller `
                                -ArgumentList '/features OptionId.WindowsDesktopDebuggers /quiet /norestart /ceip off' `
                                -Wait `
                                -PassThru
    if ($sdkProcess.ExitCode -notin @(0, 3010)) {
        throw "Windows SDK debugging tools installation failed with exit code $($sdkProcess.ExitCode)."
    }
    $cdb = @(
        $cdbCandidates
        Get-ChildItem -Path $env:ProgramFiles, ${env:ProgramFiles(x86)} `
                      -Filter 'cdb.exe' `
                      -File `
                      -Recurse `
                      -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match "Debuggers\\$debuggerArch$" } |
            Select-Object -ExpandProperty FullName
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $cdb) {
    throw 'cdb.exe was not found after installing the Windows SDK debugging tools.'
}

$debuggerCommandFile = Join-Path $dumpDirectoryPath 'cdb-commands.txt'
$debuggerLogFile = Join-Path $dumpDirectoryPath 'cdb-process-tree.log'
$dumpFile = Join-Path $dumpDirectoryPath 'php-crash.dmp'
$cdbDumpFile = $dumpFile.Replace('\', '/')
$symbolDirectory = Join-Path $dumpDirectoryPath 'symbols'
$symbolCache = Join-Path $dumpDirectoryPath 'symbol-cache'
New-Item -Path $symbolDirectory, $symbolCache -ItemType Directory -Force | Out-Null

$debugPacks = @(
    Get-ChildItem -Path $env:GITHUB_WORKSPACE -File -Recurse -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object {
            $isMatchingThreadSafety = if ($Ts -eq 'nts') {
                $_.Name -match '-nts-Win32-'
            } else {
                $_.Name -match '-Win32-' -and $_.Name -notmatch '-nts-Win32-'
            }
            $_.Name -match 'debug.*pack|debug_pack' `
                -and $_.Name -match [regex]::Escape($Arch) `
                -and $isMatchingThreadSafety
        }
)
foreach ($debugPack in $debugPacks) {
    Write-Host "Preloading debugger symbols from $($debugPack.Name)"
    Expand-Archive -Path $debugPack.FullName -DestinationPath $symbolDirectory -Force
}

$symbolPath = "$symbolDirectory;srv*$symbolCache*https://msdl.microsoft.com/download/symbols"
$phpModule = if ($Ts -eq 'ts') { 'php8ts' } else { 'php8' }
$sharedGlobalsCommands = "x $phpModule!*smm_shared_globals*; x $phpModule!*accel_shared_globals*; dq $phpModule!smm_shared_globals L1; dq poi($phpModule!smm_shared_globals) L20; dq $phpModule!accel_shared_globals L1; dq poi($phpModule!accel_shared_globals) L40; dt $phpModule!_zend_smm_shared_globals poi($phpModule!smm_shared_globals); dt $phpModule!_zend_accel_shared_globals poi($phpModule!accel_shared_globals)"
@(
    '.lines -e',
    "sxd -c2 `".dump /ma /u $cdbDumpFile; .lastevent; !analyze -v; .ecxr; r; ln @rip; u @rip-40 @rip+40; kv 100; dv /t /v; dps @rsp L100; $sharedGlobalsCommands; !address @rcx; !address @rax; ~* kv 100; lmv; !peb; !address -summary; q`" av",
    'g'
) | Set-Content -Path $debuggerCommandFile -Encoding ascii

$debuggerEnvironment = @{
    PHP_CDB_COMMAND_FILE = $debuggerCommandFile
    PHP_CDB_LOG = $debuggerLogFile
    PHP_CDB_PATH = $cdb
    PHP_CDB_SYMBOL_PATH = $symbolPath
    PHP_CRASH_DEBUGGER = '1'
    PHP_CRASH_DUMP_DIR = $dumpDirectoryPath
}
foreach ($entry in $debuggerEnvironment.GetEnumerator()) {
    Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
    if ($env:GITHUB_ENV) {
        "$($entry.Key)=$($entry.Value)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    }
}

Write-Host "Enabled cdb process-tree debugging with $cdb"
Get-Content -Path $debuggerCommandFile | ForEach-Object { Write-Host "cdb> $_" }
