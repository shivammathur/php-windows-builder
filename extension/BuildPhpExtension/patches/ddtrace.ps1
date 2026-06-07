Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DataDog/dd-trace-php/master/datadog-windows.sym" -OutFile "datadog-windows.sym"
Invoke-WebRequest -Uri "https://github.com/DataDog/libdatadog/archive/refs/heads/main.zip" -OutFile "$ENV:TEMP/libdatadog.zip"
Remove-Item -Path "libdatadog" -Recurse -Force
Expand-Archive -Path "$ENV:TEMP/libdatadog.zip" -DestinationPath "." -Force
Rename-Item -Path "libdatadog-main" -NewName "libdatadog"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DataDog/libdatadog/main/libdd-common/src/cc_utils.rs" -OutFile "libdatadog/tools/cc_utils/src/lib.rs"
