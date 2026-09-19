$configPath = Get-RecursiveFilePath -Directory (Get-Location).Path -FileName 'config.w32'
$config = Get-Content -LiteralPath $configPath -Raw

if ($config -notmatch 'CHECK_LIB\(\s*"libopenblas\.lib"') {
    $guard = 'if (PHP_TENSOR != "no") {'
    if (-not $config.Contains($guard)) {
        throw 'Unable to find the Tensor enable guard in config.w32'
    }
    $lineEnding = if ($config.Contains("`r`n")) { "`r`n" } else { "`n" }
    $dependencyGuard = @(
        '  if (!CHECK_LIB("libopenblas.lib", "tensor", PHP_TENSOR) ||',
        '      !CHECK_HEADER_ADD_INCLUDE("cblas.h", "CFLAGS_TENSOR")) {',
        '    ERROR("tensor requires OpenBLAS libraries and headers");',
        '  }'
    ) -join $lineEnding
    $config = $config.Replace($guard, $guard + $lineEnding + $dependencyGuard)
    Set-Content -LiteralPath $configPath -Value $config -Encoding utf8 -NoNewline
}
