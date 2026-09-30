param([string]$Arch, [string]$Ts)
. "$PSScriptRoot/common.ps1"
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/comparison" -ItemType Directory -Force
$runtime = @{}
$metadata = [ordered]@{arch=$Arch; ts=$Ts; image=$env:ImageVersion; cpu=(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors); os=(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version); variants=@{}}
foreach ($variant in @('msvc','clang')) {
    $runtime[$variant] = Expand-Runtime $variant
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
    foreach ($variant in @('msvc','clang')) { $inis[$variant] = Write-TestIni $runtime[$variant] $mode }
    foreach ($workload in @('integer_calls','objects','arrays','json','strings_regex','hash','zend_bench')) {
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
                    $output = & $exe -n -c $inis[$variant] "$PSScriptRoot/bench.php" $workload 2>&1
                    $row = $output | ConvertFrom-Json
                }
                if ($LASTEXITCODE -ne 0) { throw "$variant $mode $workload failed: $output" }
                if ($round -gt 0) {
                    $results.Add([ordered]@{variant=$variant;mode=$mode;workload=$workload;round=$round;seconds=$row.seconds;checksum=$row.checksum})
                    $results | ConvertTo-Json -Depth 5 | Set-Content "$out/benchmarks.json"
                }
            }
        }
    }
}
