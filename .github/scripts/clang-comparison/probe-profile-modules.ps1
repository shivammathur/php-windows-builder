$ErrorActionPreference = 'Stop'
$out = New-Item "$env:GITHUB_WORKSPACE/diagnostics" -ItemType Directory -Force
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
'__declspec(dllexport) int alpha(int x) { return x ? 10 : 11; }' | Set-Content "$out/alpha.c"
'__declspec(dllexport) int beta(int x) { return x ? 20 : 21; }' | Set-Content "$out/beta.c"
'__declspec(dllimport) int alpha(int); __declspec(dllimport) int beta(int); int main(void) { return alpha(1) + beta(1) != 30; }' | Set-Content "$out/main.c"
@(
    '@echo off',
    ('call "{0}\VC\Auxiliary\Build\vcvars64.bat"' -f $vs),
    ('cd /d "{0}"' -f $out),
    'clang-cl /O2 -fprofile-generate /LD alpha.c /Fealpha.dll',
    'if errorlevel 1 exit /b 1',
    'clang-cl /O2 -fprofile-generate /LD beta.c /Febeta.dll',
    'if errorlevel 1 exit /b 1',
    'clang-cl /O2 -fprofile-generate main.c alpha.lib beta.lib /Femain.exe',
    'exit /b %errorlevel%'
) | Set-Content "$out/build.bat"
& cmd /c "$out/build.bat" 2>&1 | Set-Content "$out/build.txt"
if ($LASTEXITCODE -ne 0) { throw 'Profile probe compilation failed' }
$results = foreach ($pattern in @('pid', 'module-pid')) {
    $dir = New-Item "$out/$pattern" -ItemType Directory -Force
    $name = if ($pattern -eq 'pid') { 'php-%p.profraw' } else { 'php-%m-%p.profraw' }
    $env:LLVM_PROFILE_FILE = "$dir/$name"
    & "$out/main.exe" 2>&1 | Set-Content "$dir/runtime.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Profile probe execution failed' }
    $raw = @(Get-ChildItem "$dir/*.profraw")
    & llvm-profdata merge "-output=$dir/merged.profdata" @($raw.FullName) 2>&1 | Set-Content "$dir/merge.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Profile probe merge failed' }
    & llvm-profdata show --all-functions --counts "$dir/merged.profdata" | Set-Content "$dir/counts.txt"
    [ordered]@{pattern=$name;rawFiles=$raw.Count}
}
$results | ConvertTo-Json | Set-Content "$out/results.json"
exit 0
