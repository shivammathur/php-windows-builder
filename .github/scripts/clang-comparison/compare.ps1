param([string]$Arch, [string]$Ts)
. "$PSScriptRoot/common.ps1"
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/comparison" -ItemType Directory -Force
$runtime = @{}
Import-Module "$root/php/BuildPhp" -Force
. "$root/extension/BuildPhpExtension/private/Test-ClangToolset.ps1"
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
$dumpbin = (Get-ChildItem "$vs/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1).FullName
$metadata = [ordered]@{arch=$Arch; ts=$Ts; image=$env:ImageVersion; cpu=(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors); os=(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version); variants=@{}}
foreach ($variant in @('msvc','clang')) {
    $runtime[$variant] = Expand-Runtime $variant
    & python "$PSScriptRoot/inspect-artifacts.py" "$root/input/$variant" > "$out/$variant-artifact-checks.json"
    if ($LASTEXITCODE -ne 0) { throw "$variant artifact debug/SBOM validation failed" }
    Invoke-PhpSmokeTests -ArtifactsDirectory "$root/input/$variant" -Arch $Arch -Ts $Ts 2>&1 | Tee-Object "$out/$variant-smoke.log"
    $metadata.variants[$variant] = Get-Content "$root/input/$variant/metadata.json" -Raw | ConvertFrom-Json
    foreach ($zip in Get-ChildItem "$root/input/$variant/*.zip") {
        $archive = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
        try {
            $entries = foreach ($entry in $archive.Entries) {
                $stream = $entry.Open()
                try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
                [ordered]@{path=$entry.FullName; size=$entry.Length; compressed=$entry.CompressedLength; sha256=$hash}
            }
            [ordered]@{archive=$zip.Name; bytes=$zip.Length; entries=@($entries)} | ConvertTo-Json -Depth 6 | Set-Content "$out/$variant-$($zip.BaseName)-inventory.json"
        } finally { $archive.Dispose() }
    }
    $isClang = Test-ClangToolset -PhpBinary "$($runtime[$variant])/php.exe"
    if ($isClang -ne ($variant -eq 'clang')) { throw "Unexpected runtime compiler for $variant" }
    foreach ($binary in Get-ChildItem $runtime[$variant] -File | Where-Object { $_.Name -match '^php.*\.(exe|dll)$' }) {
        & $dumpbin /headers /loadconfig /dependents $binary.FullName | Set-Content "$out/$variant-$($binary.Name)-pe.txt"
        if ($LASTEXITCODE -ne 0) { throw "dumpbin failed for $($binary.Name)" }
    }
    $ini = Write-TestIni $runtime[$variant] 'nocache'
    $exe = "$($runtime[$variant])/php.exe"
    & $exe -n -c $ini -v 2>&1 | Set-Content "$out/$variant-version.txt"
    if ($LASTEXITCODE -ne 0) { throw "$variant php -v failed" }
    & $exe -n -c $ini -i 2>&1 | Set-Content "$out/$variant-phpinfo.txt"
    & $exe -n -c $ini -m 2>&1 | Set-Content "$out/$variant-modules.txt"
    if ($LASTEXITCODE -ne 0) { throw "$variant php -m failed" }
    & $exe -n -c $ini -r 'echo json_encode(["extensions"=>get_loaded_extensions(),"zend"=>get_loaded_extensions(true),"int_size"=>PHP_INT_SIZE,"zts"=>PHP_ZTS], JSON_THROW_ON_ERROR);' | Set-Content "$out/$variant-runtime.json"
    if ($LASTEXITCODE -ne 0) { throw "$variant runtime probe failed" }
}
$metadata | ConvertTo-Json -Depth 8 | Set-Content "$out/metadata.json"
$results = [Collections.Generic.List[object]]::new()
foreach ($mode in @('nocache','opcache','jit')) {
    $inis=@{}
    foreach ($variant in @('msvc','clang')) {
        $inis[$variant] = Write-TestIni $runtime[$variant] $mode
        & "$($runtime[$variant])/php.exe" -n -c $inis[$variant] -r 'echo json_encode(["ini"=>php_ini_loaded_file(), "opcache_enable_cli"=>ini_get("opcache.enable_cli"), "jit"=>ini_get("opcache.jit"), "status"=>opcache_get_status(false)], JSON_THROW_ON_ERROR);' | Set-Content "$out/$variant-$mode-status.json"
        if ($LASTEXITCODE -ne 0) { throw "Failed to inspect $variant $mode configuration" }
    }
    foreach ($workload in @('integer_calls','objects','arrays','json','strings_regex','hash','zend_bench')) {
        $repeats = 1
        if ($workload -ne 'zend_bench') {
            $calibration = & "$($runtime['msvc'])/php.exe" -n -c $inis['msvc'] "$PSScriptRoot/bench.php" $workload | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) { throw "Calibration failed: $workload" }
            $repeats = [Math]::Min(1000, [Math]::Max(1, [Math]::Ceiling(0.75 / $calibration.seconds)))
        }
        for ($round=0; $round -le 7; $round++) {
            $order = if ($round % 2 -eq 0) { @('msvc','clang') } else { @('clang','msvc') }
            foreach ($variant in $order) {
                $exe = "$($runtime[$variant])/php.exe"
                $watch = [Diagnostics.Stopwatch]::StartNew()
                if ($workload -eq 'zend_bench') {
                    $output = & $exe -n -c $inis[$variant] "$root/source/Zend/bench.php" 2>&1
                    $row = [pscustomobject]@{seconds=$watch.Elapsed.TotalSeconds; checksum='timed Zend/bench.php'}
                    $output | Set-Content "$out/$variant-$mode-zend-bench-last.txt"
                } else {
                    $output = & $exe -n -c $inis[$variant] "$PSScriptRoot/bench.php" $workload $repeats 2>&1
                    $row = $output | ConvertFrom-Json
                }
                if ($LASTEXITCODE -ne 0) { throw "$variant $mode $workload failed: $output" }
                if ($round -gt 0) {
                    $results.Add([ordered]@{variant=$variant;mode=$mode;workload=$workload;round=$round;repeats=$repeats;seconds=$row.seconds;checksum=$row.checksum})
                    $results | ConvertTo-Json -Depth 5 | Set-Content "$out/benchmarks.json"
                }
            }
        }
    }
}

& "$PSScriptRoot/extensions.ps1" -Arch $Arch -Ts $Ts -Runtimes $runtime -Out $out
if ($Ts -eq 'ts') { & "$PSScriptRoot/apache.ps1" -Arch $Arch -Runtimes $runtime -Out $out }
