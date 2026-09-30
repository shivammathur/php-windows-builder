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
exit 0
