@echo off
setlocal
set "sdk=%~1"
set "vc=%ProgramFiles(x86)%\Microsoft Visual Studio %~2\VC"
set "arch=%~3"
set "config=%~4"
set "target=x86"
if "%arch%"=="x64" set "target=x86_amd64"
if "%~2"=="9.0" goto vc9

call "%vc%\vcvarsall.bat" %target%
if errorlevel 1 exit /b 1
if not "%~2"=="14.0" goto sdk
rem v140 expects unversioned tool paths. Use the installed Windows 10 SDK.
set "kit=%ProgramFiles(x86)%\Windows Kits\10"
set "version=10.0.19041.0"
set "PATH=%kit%\bin\%version%\x86;%PATH%"
set "INCLUDE=%kit%\Include\%version%\ucrt;%kit%\Include\%version%\shared;%kit%\Include\%version%\um;%kit%\Include\%version%\winrt;%INCLUDE%"
set "LIB=%kit%\Lib\%version%\ucrt\%arch%;%kit%\Lib\%version%\um\%arch%;%LIB%"
goto sdk

:vc9
rem Express SP1 supplies rc and mt. Use the Windows 10 SDK for mc.
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio 9.0\"
set "VCINSTALLDIR=%vc%\"
set "WindowsSdkDir=%VSINSTALLDIR%Windows SDK\"
set "mcdir="
for /d %%D in ("%ProgramFiles(x86)%\Windows Kits\10\bin\10.*") do if exist "%%D\x86\mc.exe" set "mcdir=%%D\x86"
if not defined mcdir exit /b 1
set "PATH=%vc%\bin;%VSINSTALLDIR%Common7\IDE;%WindowsSdkDir%Bin;%mcdir%;%PATH%"
set "INCLUDE=%vc%\include;%WindowsSdkDir%Include"
set "LIB=%vc%\lib;%WindowsSdkDir%Lib"

:sdk
call "%sdk%\bin\phpsdk_setvars.bat"
if errorlevel 1 exit /b 1
if not "%~2"=="14.0" (
    set "PATH=%sdk%\bin;%PATH%"
    set "BISON_PKGDATADIR=%sdk%\share\bison"
)
call buildconf.bat
if errorlevel 1 exit /b 1
call "%config%"
if errorlevel 1 exit /b 1
if not "%~2"=="14.0" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-legacy.ps1"
    if errorlevel 1 exit /b 1
)
nmake
if errorlevel 1 exit /b 1
nmake snap
exit /b %errorlevel%
