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
if ($meta.arch -eq 'x86') {
    # The x64 LLDB build reports the WOW64 host context instead of the faulting
    # x86 context. Use the matching native debugger and Python architecture.
    $toolsDir = New-Item "$root/debugger-x86" -ItemType Directory -Force
    $installer = "$toolsDir/LLVM-20.1.8-win32.exe"
    Invoke-WebRequest 'https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-win32.exe' -OutFile $installer
    if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne '430b5c04252c9ff195a8993ae1c2ff2b73a14f42067f44cfe8f6db73232313cd') {
        throw 'LLVM debugger installer checksum mismatch'
    }
    & 7z e $installer 'bin/lldb.exe' 'bin/liblldb.dll' 'bin/lldb-server.exe' "-o$toolsDir" -y
    if ($LASTEXITCODE -ne 0) { throw 'Failed to extract x86 debugger' }
    $lldb = "$toolsDir/lldb.exe"
}
& $lldb --version 2>&1 | Set-Content "$out/debugger-version.txt"
$probes = @(
    @{name='cli-no-extensions';exe='php.exe';args=@('-n',"$out/probe.php")},
    @{name='cli-pgo-ini';exe='php.exe';args=@('-n','-c',"$out/pgo.ini","$out/probe.php")},
    @{name='cgi-no-extensions';exe='php-cgi.exe';args=@('-n','-d','cgi.force_redirect=0','-f',"$out/probe.php")},
    @{name='cgi-pgo-ini';exe='php-cgi.exe';args=@('-n','-c',"$out/pgo.ini",'-d','cgi.force_redirect=0','-f',"$out/probe.php")}
)
foreach ($probe in $probes) {
    $exe = "$runtime/$($probe.exe)"
    $arguments = $probe.args
    & $exe @arguments 2>&1 | Set-Content "$out/$($probe.name).txt"
    $code = $LASTEXITCODE
    "exit=$code" | Add-Content "$out/$($probe.name).txt"
    if ($code -ne 0) {
        & $lldb --batch --no-lldbinit -o run -k 'image list' -k 'thread backtrace all' -k 'register read' -k 'disassemble --frame' -k 'memory read --format x --size 8 --count 40 $rsp' -k 'image lookup --address `*(unsigned long long*)$rsp`' -k 'disassemble --start-address `*(unsigned long long*)$rsp-32` --count 32' -- $exe @arguments 2>&1 | Set-Content "$out/$($probe.name)-backtrace.txt"
    }
}
if ($Kind -eq 'x64-cfg') {
    @'
#ifdef PRESERVE_NONE
# define CC __attribute__((preserve_none))
#else
# define CC
#endif
typedef int fn_type(int) CC;
__declspec(noinline) int CC add_one(int x) { return x+1; }
fn_type *volatile func = add_one;
int main(void) { return func(41) != 42; }
'@ | Set-Content "$out/guard-probe.c"
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    $vs = & $vswhere -latest -products '*' -property installationPath
    foreach ($mode in @('normal','preserve-none')) {
        $define = if ($mode -eq 'preserve-none') { '/DPRESERVE_NONE' } else { '' }
        @(
            '@echo off',
            ('call "{0}\VC\Auxiliary\Build\vcvars64.bat"' -f $vs),
            ('cd /d "{0}"' -f $out),
            ('clang-cl /O2 /guard:cf {0} guard-probe.c /Feguard-{1}.exe /link /guard:cf' -f $define,$mode),
            'if errorlevel 1 exit /b 1',
            ('clang-cl /O2 /guard:cf {0} /c /FA /Faguard-{1}.asm guard-probe.c' -f $define,$mode),
            'exit /b %errorlevel%'
        ) | Set-Content "$out/guard-$mode.bat"
        & cmd /c "$out/guard-$mode.bat" 2>&1 | Set-Content "$out/guard-$mode-build.txt"
        if ($LASTEXITCODE -ne 0) { throw "Guard probe compile failed: $mode" }
        & "$out/guard-$mode.exe"
        "exit=$LASTEXITCODE" | Set-Content "$out/guard-$mode-result.txt"
    }

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
