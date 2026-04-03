set "PHP_SDK_PGO_CASES_ARG="
if defined PHP_SDK_PGO_CASES set "PHP_SDK_PGO_CASES_ARG=--cases %PHP_SDK_PGO_CASES%"
set LDFLAGS="/d2:-AllowCompatibleILVersions" 2>&1
call phpsdk_deps.bat -s staging -u 2>&1
if errorlevel 1 exit 1
call buildconf.bat 2>&1
if errorlevel 1 exit 2
call config.nts.bat 2>&1
if errorlevel 1 exit 3
nmake 2>&1
if errorlevel 1 exit 4
call phpsdk_pgo --init %PHP_SDK_PGO_CASES_ARG% 2>&1
if errorlevel 1 exit 5
call phpsdk_pgo --train --scenario default %PHP_SDK_PGO_CASES_ARG% 2>&1
if errorlevel 1 exit 6
call phpsdk_pgo --train --scenario cache %PHP_SDK_PGO_CASES_ARG% 2>&1
if errorlevel 1 exit 7
nmake clean-pgo 2>&1
if errorlevel 1 exit 8
sed -i "s/enable-pgi/with-pgo/" config.nts.bat 2>&1
if errorlevel 1 exit 9
call config.nts.bat 2>&1
if errorlevel 1 exit 10
nmake && nmake snap 2>&1
if errorlevel 1 exit 11
