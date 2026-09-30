param([string]$Variant)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$metadata = Get-Content "$root/input/$Variant/metadata.json" -Raw | ConvertFrom-Json
$arch = $metadata.arch
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
$target = $arch
$compiler = if ($Variant -eq 'clang') { 'clang-cl' } else { 'cl' }
$flags = if ($Variant -eq 'clang') { if ($arch -eq 'x86') { '-m32' } else { '-m64' } } else { '' }
$directory = (New-Item "$root/comtest/$Variant" -ItemType Directory -Force).FullName
$batch = "$directory/build.bat"
@"
BUILD_DIR=$directory
PHP_CL=$compiler
CFLAGS_ARCH=$flags
LINK=link.exe
!include ext\com_dotnet\Makefile.frag.w32
"@ | Set-Content "$directory/Makefile" -Encoding ascii
@"
@echo off
call "$vs/VC/Auxiliary/Build/vcvarsall.bat" $target >nul
if errorlevel 1 exit /b 1
cd /d "$root/source"
nmake /nologo /f "$directory/Makefile" comtest.dll register_comtest
exit /b %errorlevel%
"@ | Set-Content $batch -Encoding ascii
& cmd /d /c $batch 2>&1 | Tee-Object "$root/regressions/$Variant-comtest-build.log"
if ($LASTEXITCODE -ne 0) { throw "$Variant COM fixture build/registration failed" }
