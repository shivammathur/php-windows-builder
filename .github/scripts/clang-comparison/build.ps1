param([string]$Variant, [string]$Arch, [string]$Ts)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/results" -ItemType Directory -Force
Start-Transcript "$out/build.log"
try {
    $meta = [ordered]@{variant=$Variant; arch=$Arch; ts=$Ts; builder=(& git -C "$root/builder" rev-parse HEAD); source=(& git -C "$root/source" rev-parse HEAD); image=$env:ImageVersion; llvm=(& clang-cl --version | Out-String); started=[DateTime]::UtcNow.ToString('o')}
    $meta | ConvertTo-Json | Set-Content "$out/metadata.json"
    Import-Module "$root/builder/php/BuildPhp" -Force
    Set-Location "$root/source"
    Invoke-PhpBuild -Arch $Arch -Ts $Ts
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
    Stop-Transcript
}
