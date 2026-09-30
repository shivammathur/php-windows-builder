param([string]$Variant, [string]$Arch, [string]$Ts)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/results" -ItemType Directory -Force
$started = Get-Date
$built = $false
# Preserve crash evidence on the disposable runner, including failures during PGO.
foreach ($exe in @('php.exe', 'php-cgi.exe', 'phpdbg.exe')) {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\$exe"
    New-Item $key -Force | Out-Null
    New-ItemProperty $key -Name DumpFolder -Value "$out/crashes" -PropertyType ExpandString -Force | Out-Null
    New-ItemProperty $key -Name DumpType -Value 1 -PropertyType DWord -Force | Out-Null
}
Start-Transcript "$out/build.log"
try {
    $meta = [ordered]@{variant=$Variant; arch=$Arch; ts=$Ts; builder=(& git -C "$root/builder" rev-parse HEAD); source=(& git -C "$root/source" rev-parse HEAD); image=$env:ImageVersion; llvm=(& clang-cl --version | Out-String); started=[DateTime]::UtcNow.ToString('o')}
    $meta | ConvertTo-Json | Set-Content "$out/metadata.json"
    Import-Module "$root/builder/php/BuildPhp" -Force
    Set-Location "$root/source"
    Invoke-PhpBuild -Arch $Arch -Ts $Ts
    $built = $true
    $meta.finished = [DateTime]::UtcNow.ToString('o')
    $meta | ConvertTo-Json | Set-Content "$out/metadata.json"
} finally {
    Set-Location $root
    foreach ($file in @('Makefile','config.nice.bat','config.nice.phpize.bat','main/config.w32.h')) {
        if (Test-Path "source/$file") { Copy-Item "source/$file" "$out/$([IO.Path]::GetFileName($file))" }
    }
    $buildDir = if ($Ts -eq 'ts') { 'obj/Release_TS' } else { 'obj/Release' }
    if (Test-Path $buildDir) {
        # Preserve archives even when a later compliance/export step fails.
        Get-ChildItem "$buildDir/php-*.zip" -File | Copy-Item -Destination $out
        Get-ChildItem $buildDir -File | Select-Object Name,Length | ConvertTo-Json | Set-Content "$out/build-files.json"
        if (Test-Path "$buildDir/php.profdata") {
            Copy-Item "$buildDir/php.profdata" $out
            & llvm-profdata show --all-functions --counts "$buildDir/php.profdata" > "$out/profile.txt"
        }
    }
    if (Test-Path 'source/artifacts') {
        Get-ChildItem 'source/artifacts' -File | Copy-Item -Destination $out -Force
    }
    if (-not $built) {
        if (Test-Path $buildDir) {
            $failed = New-Item "$out/failed-runtime" -ItemType Directory -Force
            Get-ChildItem $buildDir -File | Where-Object Extension -In '.exe','.dll','.pdb' | Copy-Item -Destination $failed
            if (Test-Path 'deps/bin') { Copy-Item 'deps/bin/*.dll' $failed -ErrorAction Continue }
            if (Test-Path "$buildDir/php.exe") {
                & "$root/$buildDir/php.exe" -n -v 2>&1 | Set-Content "$out/failed-version.txt"
                "exit=$LASTEXITCODE" | Add-Content "$out/failed-version.txt"
                & "$root/$buildDir/php.exe" -n "$root/source/Zend/bench.php" 2>&1 | Set-Content "$out/failed-bench.txt"
                "exit=$LASTEXITCODE" | Add-Content "$out/failed-bench.txt"
            }
        }
        foreach ($sdk in Get-ChildItem "$env:TEMP/php-*/php-sdk" -Directory -ErrorAction SilentlyContinue) {
            $dest = New-Item "$out/sdk-diagnostics/$($sdk.Parent.Name)" -ItemType Directory -Force
            Get-ChildItem "$($sdk.FullName)/pgo" -Recurse -File -Include '*.log','*.ini','*.conf','*.json' -ErrorAction SilentlyContinue | ForEach-Object {
                $target = Join-Path $dest ([IO.Path]::GetRelativePath($sdk.FullName, $_.FullName))
                New-Item ([IO.Path]::GetDirectoryName($target)) -ItemType Directory -Force | Out-Null
                Copy-Item $_.FullName $target
            }
        }
        Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$started} -ErrorAction SilentlyContinue |
            Where-Object ProviderName -In 'Application Error','Windows Error Reporting' |
            Select-Object TimeCreated,Id,ProviderName,Message | ConvertTo-Json -Depth 5 | Set-Content "$out/crash-events.json"
    }
    Stop-Transcript
}
