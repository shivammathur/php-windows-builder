$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/diagnostics" -ItemType Directory -Force
$runtime = "$root/input/failed-runtime"
'<?php echo "execution passed\n";' | Set-Content "$out/probe.php"
& "$runtime/php.exe" -n "$out/probe.php" 2>&1 | Set-Content "$out/original.txt"
"exit=$LASTEXITCODE" | Add-Content "$out/original.txt"
$lldb = (Get-Command lldb.exe).Source
& $lldb --version 2>&1 | Set-Content "$out/debugger-version.txt"
& $lldb --batch --no-lldbinit -o run -k 'thread backtrace all' -k 'register read' -k 'disassemble --frame' -- "$runtime/php.exe" -n "$out/probe.php" 2>&1 | Set-Content "$out/backtrace.txt"

# Diagnostic copy only: leave compiled code intact, clear the image CFG bit,
# and check whether the same program can execute. Never publish this copy.
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
exit 0
