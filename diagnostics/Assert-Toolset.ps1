$ErrorActionPreference = 'Stop'
$evidence = Join-Path $env:GITHUB_WORKSPACE 'toolset-evidence'
$expected = [IO.Path]::GetFullPath("$env:DIAGNOSTIC_TOOLSET_PATH/bin/Hostarm64/arm64").TrimEnd('\')
$tools = foreach ($name in @('cl.exe','link.exe','pgomgr.exe')) {
    $candidates = @(Get-Command $name -CommandType Application)
    $command = $candidates[0]
    if ([IO.Path]::GetDirectoryName($command.Source) -ine $expected) { throw "$name resolved outside requested native toolset: $($command.Source)" }
    @{name=$name; path=$command.Source; candidates=@($candidates.Source); version=(Get-Item $command.Source).VersionInfo.FileVersion; sha256=(Get-FileHash $command.Source).Hash}
}
$msc = if ($env:DIAGNOSTIC_TOOLSET.StartsWith('14.50.')) {1950} elseif ($env:DIAGNOSTIC_TOOLSET.StartsWith('14.52.')) {1952} else {throw 'Unexpected toolset'}
@"
#include <stdio.h>
#if !defined(_M_ARM64) || defined(__clang__) || _MSC_VER != $msc
#error Wrong compiler or architecture
#endif
int main(void) { printf("_MSC_VER=%d _MSC_FULL_VER=%d ARM64=1\n", _MSC_VER, _MSC_FULL_VER); return 0; }
"@ | Set-Content "$evidence/compiler.c"
& cl.exe /nologo /Bv "$evidence/compiler.c" "/Fe:$evidence/compiler.exe" "/Fo:$evidence/compiler.obj" 2>&1 | Tee-Object "$evidence/compiler.log" | Out-Host
if ($LASTEXITCODE) { throw 'Compiler identity probe failed' }
& "$evidence/compiler.exe" | Tee-Object "$evidence/compiler-runtime.txt" | Out-Host
if ($LASTEXITCODE) { throw 'Compiler identity runtime failed' }
$tools | ConvertTo-Json -Depth 8 | Set-Content "$evidence/actual-tools.json"
@{VCToolsVersion=$env:VCToolsVersion; VCToolsInstallDir=$env:VCToolsInstallDir; VSCMD_ARG_HOST_ARCH=$env:VSCMD_ARG_HOST_ARCH; VSCMD_ARG_TGT_ARCH=$env:VSCMD_ARG_TGT_ARCH; PATH=$env:PATH; INCLUDE=$env:INCLUDE; LIB=$env:LIB} |
    ConvertTo-Json -Depth 5 | Set-Content "$evidence/actual-environment.json"
