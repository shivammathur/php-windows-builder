$symbolFile = if ((Get-Content -Path "config.w32" -Raw).Contains("ddtrace-extension-windows.sym")) {
    "ddtrace-extension-windows.sym"
} else {
    "datadog-windows.sym"
}

Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DataDog/dd-trace-php/master/ddtrace-extension-windows.sym" -OutFile $symbolFile
