set "PHP_SDK_PGO_CASES_ARG="
if defined PHP_SDK_PGO_CASES set "PHP_SDK_PGO_CASES_ARG=--cases %PHP_SDK_PGO_CASES%"
set LDFLAGS="/d2:-AllowCompatibleILVersions" 2>&1
call buildconf.bat 2>&1
if errorlevel 1 exit 1
call config.ts.bat 2>&1
if errorlevel 1 exit 2
nmake 2>&1
if errorlevel 1 exit 3
call phpsdk_pgo --init %PHP_SDK_PGO_CASES_ARG% 2>&1
if errorlevel 1 exit 4
call phpsdk_pgo --train --scenario default %PHP_SDK_PGO_CASES_ARG% 2>&1
if errorlevel 1 exit 5
call phpsdk_pgo --train --scenario cache %PHP_SDK_PGO_CASES_ARG% 2>&1
if errorlevel 1 exit 6
nmake clean-pgo 2>&1
if errorlevel 1 exit 7
sed -i "s/enable-pgi/with-pgo/" config.ts.bat 2>&1
if errorlevel 1 exit 8
call config.ts.bat 2>&1
if errorlevel 1 exit 9
nmake && nmake snap 2>&1
if errorlevel 1 exit 10
