@echo off
setlocal

set "PHP_PGO_BIN=%~f1"
set "PHP_PGO_MODE=%~2"

if "%PHP_PGO_BIN%"=="" exit /b 1
if not exist "%PHP_PGO_BIN%\php.exe" exit /b 1
if not exist "%~dp0train-pgo-error-handlers.php" exit /b 1

"%PHP_PGO_BIN%\php.exe" -n "%~dp0train-pgo-error-handlers.php"
if errorlevel 1 exit /b %ERRORLEVEL%

if /i "%PHP_PGO_MODE%"=="verify" exit /b 0

call :merge_pgo php8
if errorlevel 1 exit /b %ERRORLEVEL%
call :merge_pgo php
if errorlevel 1 exit /b %ERRORLEVEL%

exit /b 0

:merge_pgo
set "PGO_IMAGE=%~1"
set "PGO_PGD=%PHP_PGO_BIN%\%PGO_IMAGE%.pgd"

if not exist "%PGO_PGD%" exit /b 0

for %%D in ("%PHP_PGO_BIN%" "%CD%") do (
  for %%F in ("%%~fD\%PGO_IMAGE%!*.pgc") do (
    if exist "%%~fF" (
      pgomgr /merge:1000 "%%~fF" "%PGO_PGD%"
      if errorlevel 1 exit /b 1
      del "%%~fF"
    )
  )
)

exit /b 0
