$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/diagnostics" -ItemType Directory -Force
$runtime = "$root/runtime"
$zip = Get-ChildItem "$root/input/php-8*.zip"
Expand-Archive $zip.FullName $runtime
Expand-Archive (Get-ChildItem "$root/input/php-debug-pack-*.zip").FullName $runtime -Force
$toolsDir = New-Item "$root/debugger-x86" -ItemType Directory -Force
$installer = "$toolsDir/LLVM-20.1.8-win32.exe"
Invoke-WebRequest 'https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-win32.exe' -OutFile $installer
if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne '430b5c04252c9ff195a8993ae1c2ff2b73a14f42067f44cfe8f6db73232313cd') { throw 'LLVM debugger checksum mismatch' }
& 7z e $installer 'bin/lldb.exe' 'bin/liblldb.dll' 'bin/lldb-server.exe' "-o$toolsDir" -y
if ($LASTEXITCODE -ne 0) { throw 'Could not extract debugger' }
@'
<?php
$formatter = new MessageFormatter('en_US', '{0,number,integer}');
var_dump($formatter->format([42]));
echo "before parse\n";
var_dump($formatter->parse('42'));
echo "after parse\n";
'@ | Set-Content "$out/parse.php"
$arguments = @('-n','-d',"extension_dir=$runtime/ext",'-d','extension=intl',"$out/parse.php")
& "$runtime/php.exe" @arguments 2>&1 | Set-Content "$out/result.txt"
"exit=$LASTEXITCODE" | Add-Content "$out/result.txt"
& "$toolsDir/lldb.exe" --batch --no-lldbinit -o run -k 'image list' -k 'thread backtrace all' -k 'register read' -k 'disassemble --frame' -k 'memory read --format x --size 4 --count 40 $esp' -- "$runtime/php.exe" @arguments 2>&1 | Set-Content "$out/backtrace.txt"
$sbom = Get-Content (Get-ChildItem "$root/input/*.cdx.json").FullName -Raw | ConvertFrom-Json
$url = (($sbom.components | Where-Object name -eq 'ICU').externalReferences | Where-Object type -eq 'distribution').url
Invoke-WebRequest $url -OutFile "$root/icu.zip"
Expand-Archive "$root/icu.zip" "$root/icu"
@'
#include <cstdio>
#include <unicode/msgfmt.h>
using namespace icu;
int main() {
    UErrorCode status = U_ZERO_ERROR;
    MessageFormat formatter(UnicodeString::fromUTF8("{0,number,integer}"), Locale("en_US"), status);
    int32_t count = 0;
    Formattable *values = formatter.parse(UnicodeString::fromUTF8("42"), count, status);
    if (U_FAILURE(status) || count != 1 || values[0].getLong() != 42) return 1;
    printf("parsed 42; sizeof(Formattable)=%zu align=%zu\n", sizeof(Formattable), alignof(Formattable));
    fflush(stdout);
#ifdef ADOPT
    Formattable owner;
    owner.adoptArray(values, count);
#else
    delete[] values;
#endif
    puts("cleanup passed");
    return 0;
}
'@ | Set-Content "$out/icu-delete.cpp"
$vs = & "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe" -latest -products '*' -property installationPath
foreach ($compiler in @('msvc','clang','clang-modules')) {
    foreach ($mode in @('delete','adopt')) {
        $cc = if ($compiler -eq 'msvc') { 'cl' } else { 'clang-cl -m32' }
        if ($compiler -eq 'clang-modules') { $cc += ' -Xclang -fmodules -fms-compatibility -fms-extensions /D_USE_32BIT_TIME_T=1' }
        $define = if ($mode -eq 'adopt') { '/DADOPT' } else { '' }
        $name = "$compiler-$mode"
        @('@echo off', ('call "{0}\VC\Auxiliary\Build\vcvars32.bat"' -f $vs), ('{0} /nologo /MD /EHsc /std:c++17 /O2 {1} /I"{2}/icu/include" "{3}/icu-delete.cpp" /Fe"{4}/{5}.exe" /link /libpath:"{2}/icu/lib" icuin.lib icuuc.lib' -f $cc,$define,$root,$out,$runtime,$name), 'exit /b %errorlevel%') | Set-Content "$out/$name.cmd" -Encoding ascii
        & cmd /c "$out/$name.cmd" 2>&1 | Set-Content "$out/$name-build.txt"
        if ($LASTEXITCODE -ne 0) { throw "$name probe compilation failed" }
        & "$runtime/$name.exe" 2>&1 | Set-Content "$out/$name-result.txt"
        "exit=$LASTEXITCODE" | Add-Content "$out/$name-result.txt"
    }
}
exit 0
