param([string]$Kind)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/diagnostics" -ItemType Directory -Force
$runtime = "$root/input/failed-runtime"
$meta = Get-Content "$root/input/metadata.json" -Raw | ConvertFrom-Json
'<?php echo "execution passed\n";' | Set-Content "$out/probe.php"
$template = Get-ChildItem "$root/input/sdk-diagnostics" -Recurse -Filter "php-8.7-pgo-$($meta.ts).ini" | Select-Object -First 1
$ini = (Get-Content $template.FullName -Raw).Replace('PHP_SDK_PGO_PHP_EXTENSION_DIR', $runtime).Replace('PHP_SDK_PGO_PHP_ERROR_LOG', "$out/php-errors.log")
$ini | Set-Content "$out/pgo.ini"
$lldb = (Get-Command lldb.exe).Source
& $lldb --version 2>&1 | Set-Content "$out/debugger-version.txt"
$probes = @(
    @{name='cli-no-extensions';exe='php.exe';args=@('-n',"$out/probe.php")},
    @{name='cli-pgo-ini';exe='php.exe';args=@('-n','-c',"$out/pgo.ini","$out/probe.php")},
    @{name='cgi-pgo-ini';exe='php-cgi.exe';args=@('-n','-c',"$out/pgo.ini",'-d','cgi.force_redirect=0','-f',"$out/probe.php")}
)
foreach ($probe in $probes) {
    $exe = "$runtime/$($probe.exe)"
    $arguments = $probe.args
    & $exe @arguments 2>&1 | Set-Content "$out/$($probe.name).txt"
    $code = $LASTEXITCODE
    "exit=$code" | Add-Content "$out/$($probe.name).txt"
    if ($code -ne 0) {
        & $lldb --batch --no-lldbinit -o run -k 'thread backtrace all' -k 'register read' -k 'disassemble --frame' -- $exe @arguments 2>&1 | Set-Content "$out/$($probe.name)-backtrace.txt"
    }
}
if ($Kind -eq 'x64-cfg') {
    # Diagnostic copy only: clear the image CFG bit, preserving compiled code.
    # Never publish or use this modified copy for performance comparisons.
    $copy = "$root/cfg-disabled-diagnostic"
    Copy-Item $runtime $copy -Recurse
    foreach ($file in Get-ChildItem $copy -File | Where-Object Extension -In '.exe','.dll') {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        $offset = $pe + 24 + 70
        $flags = [BitConverter]::ToUInt16($bytes, $offset)
        $patched = [BitConverter]::GetBytes([uint16]($flags -band 0xbfff))
        $bytes[$offset] = $patched[0]
        $bytes[$offset+1] = $patched[1]
        [IO.File]::WriteAllBytes($file.FullName, $bytes)
    }
    & "$copy/php.exe" -n "$out/probe.php" 2>&1 | Set-Content "$out/cfg-bit-cleared.txt"
    "exit=$LASTEXITCODE" | Add-Content "$out/cfg-bit-cleared.txt"
}
exit 0
