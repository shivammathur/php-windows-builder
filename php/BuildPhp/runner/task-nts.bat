set LDFLAGS="/d2:-AllowCompatibleILVersions" 2>&1
call phpsdk_deps.bat -s staging -u 2>&1
if errorlevel 1 exit 1
call buildconf.bat 2>&1
if errorlevel 1 exit 2
call config.nts.bat 2>&1
if errorlevel 1 exit 3
nmake && nmake snap 2>&1
if errorlevel 1 exit 4
