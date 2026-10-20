@echo off
call buildconf.bat 2>&1
if errorlevel 1 exit /b 1
call @CONFIG@ 2>&1
if errorlevel 1 exit /b 2
nmake 2>&1
if errorlevel 1 exit /b 3
nmake snap 2>&1
if errorlevel 1 exit /b 4
exit /b 0
