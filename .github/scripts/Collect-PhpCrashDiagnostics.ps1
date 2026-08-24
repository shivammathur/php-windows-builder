[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $DumpDirectory,

    [Parameter(Mandatory = $true)]
    [string] $DiagnosticsDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64')]
    [string] $Arch,

    [Parameter(Mandatory = $true)]
    [ValidateSet('nts', 'ts')]
    [string] $Ts
)

$ErrorActionPreference = 'Stop'

$dumpSearchRoots = @($DumpDirectory, $env:RUNNER_TEMP, $env:GITHUB_WORKSPACE) |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -Unique
$dumps = @(
    Get-ChildItem -Path $dumpSearchRoots -Filter '*.dmp' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Unique
)
if ($dumps.Count -eq 0) {
    Write-Host 'No PHP crash dumps were generated.'
}

$diagnosticsPath = [System.IO.Path]::GetFullPath($DiagnosticsDirectory)
$dumpOutputPath = Join-Path $diagnosticsPath 'dumps'
$binaryOutputPath = Join-Path $diagnosticsPath 'binaries'
$symbolOutputPath = Join-Path $diagnosticsPath 'symbols'
$debuggerOutputPath = Join-Path $diagnosticsPath 'debugger'
$systemOutputPath = Join-Path $diagnosticsPath 'system'

foreach ($path in @($diagnosticsPath, $dumpOutputPath, $binaryOutputPath, $symbolOutputPath, $debuggerOutputPath, $systemOutputPath)) {
    New-Item -Path $path -ItemType Directory -Force | Out-Null
}

foreach ($dump in $dumps) {
    Copy-Item -Path $dump.FullName -Destination $dumpOutputPath -Force
}
Get-ChildItem -Path $DumpDirectory -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.log', '.txt') } |
    Copy-Item -Destination $debuggerOutputPath -Force

$buildDirectories = @(
    Get-ChildItem -Path "$($env:SystemDrive)\" -Directory -Filter 'php-*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'phpbin') }
)

foreach ($buildDirectory in $buildDirectories) {
    $buildOutputPath = Join-Path $binaryOutputPath $buildDirectory.Name
    New-Item -Path $buildOutputPath -ItemType Directory -Force | Out-Null

    Get-ChildItem -Path (Join-Path $buildDirectory.FullName 'phpbin') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.exe', '.dll', '.pdb') } |
        Copy-Item -Destination $buildOutputPath -Force

    Get-ChildItem -Path $buildDirectory.FullName -File -Filter 'test-*.log' -ErrorAction SilentlyContinue |
        Copy-Item -Destination $systemOutputPath -Force
    Get-ChildItem -Path $buildDirectory.FullName -File -Filter 'test-*.xml' -ErrorAction SilentlyContinue |
        Copy-Item -Destination $systemOutputPath -Force
}

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
    $debugPackOutputPath = Join-Path $symbolOutputPath $debugPack.BaseName
    New-Item -Path $debugPackOutputPath -ItemType Directory -Force | Out-Null
    Expand-Archive -Path $debugPack.FullName -DestinationPath $debugPackOutputPath -Force
}

$sourceDirectories = @(
    $buildDirectories |
        ForEach-Object { Join-Path $_.FullName 'tests' } |
        Where-Object { Test-Path $_ }
)
$sourceDirectories | Set-Content -Path (Join-Path $systemOutputPath 'source-directories.txt')

$binaryFiles = @(
    Get-ChildItem -Path $binaryOutputPath -File -Recurse -ErrorAction SilentlyContinue
)
$binaryFiles |
    Get-FileHash -Algorithm SHA256 |
    Format-Table -AutoSize |
    Out-String -Width 4096 |
    Set-Content -Path (Join-Path $systemOutputPath 'binary-sha256.txt')
$binaryFiles |
    Select-Object FullName, Length, LastWriteTime, VersionInfo |
    Format-List |
    Out-String -Width 4096 |
    Set-Content -Path (Join-Path $systemOutputPath 'binary-details.txt')

systeminfo.exe | Set-Content -Path (Join-Path $systemOutputPath 'systeminfo.txt')
@('Win32_OperatingSystem', 'Win32_ComputerSystem', 'Win32_Processor') |
    ForEach-Object { Get-CimInstance -ClassName $_ } |
    Format-List * |
    Out-String -Width 4096 |
    Set-Content -Path (Join-Path $systemOutputPath 'cim-system.txt')
Get-ChildItem Env: |
    ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            Value = if ($_.Name -match 'TOKEN|SECRET|PASSWORD|PASSWD|AUTH|COOKIE|PRIVATE|CREDENTIAL') {
                '<redacted>'
            } else {
                $_.Value
            }
        }
    } |
    Sort-Object Name |
    Format-Table -AutoSize |
    Out-String -Width 4096 |
    Set-Content -Path (Join-Path $systemOutputPath 'environment.txt')

reg.exe query 'HKCU\Software\Microsoft\Windows\Windows Error Reporting' /s 2>&1 |
    Set-Content -Path (Join-Path $systemOutputPath 'wer-registry.txt')

$eventStart = (Get-Date).AddHours(-6)
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $eventStart } -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -in @(1000, 1001, 1002) } |
    Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
    Format-List |
    Out-String -Width 4096 |
    Set-Content -Path (Join-Path $systemOutputPath 'application-crash-events.txt')

foreach ($werPath in @(
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"
)) {
    if (Test-Path $werPath) {
        $werOutputPath = Join-Path $systemOutputPath ((Split-Path $werPath -Leaf) + '-' + [guid]::NewGuid().ToString())
        Copy-Item -Path $werPath -Destination $werOutputPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$debuggerArch = if ($Arch -eq 'x86') { 'x86' } else { 'x64' }
$cdbCandidates = @(
    "$env:ProgramFiles\Windows Kits\10\Debuggers\$debuggerArch\cdb.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\$debuggerArch\cdb.exe"
)
$cdb = @($env:PHP_CDB_PATH) + $cdbCandidates |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -First 1

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

$localSymbolDirectories = @($binaryOutputPath, $symbolOutputPath) + @(
    Get-ChildItem -Path $binaryOutputPath, $symbolOutputPath -Directory -Recurse -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
)
$localSymbolDirectories = @($localSymbolDirectories | Select-Object -Unique)
$symbolCache = Join-Path $diagnosticsPath 'symbol-cache'
New-Item -Path $symbolCache -ItemType Directory -Force | Out-Null
$symbolPath = (@($localSymbolDirectories) + "srv*$symbolCache*https://msdl.microsoft.com/download/symbols") -join ';'
$sourcePath = $sourceDirectories -join ';'
$debuggerCommands = '.lines -e; .reload /f; .lastevent; !analyze -v; .ecxr; r; kv 100; dv /t /v; dps @rsp L100; x php8!*smm_shared_globals*; x php8!*accel_shared_globals*; dq php8!smm_shared_globals L1; dq poi(php8!smm_shared_globals) L20; dq php8!accel_shared_globals L1; dq poi(php8!accel_shared_globals) L40; dt php8!_zend_smm_shared_globals poi(php8!smm_shared_globals); ~* kv 100; lmv; !peb; !address -summary; q'

foreach ($dump in Get-ChildItem -Path $dumpOutputPath -Filter '*.dmp' -File) {
    $debuggerLog = Join-Path $debuggerOutputPath ($dump.BaseName + '.cdb.txt')
    & $cdb -z $dump.FullName -y $symbolPath -srcpath $sourcePath -lines -c $debuggerCommands 2>&1 |
        Tee-Object -FilePath $debuggerLog |
        Out-Host
}

Get-ChildItem -Path $diagnosticsPath -File -Recurse |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize |
    Out-String -Width 4096 |
    Set-Content -Path (Join-Path $diagnosticsPath 'manifest.txt')

Write-Host "Collected $($dumps.Count) full crash dump(s) and debugger output in $diagnosticsPath"
