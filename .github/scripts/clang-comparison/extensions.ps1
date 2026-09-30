param([string]$Arch, [string]$Ts, [hashtable]$Runtimes, [string]$Out)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$probeRoot = New-Item "$root/extension-probes" -ItemType Directory -Force
Push-Location $probeRoot
try { Get-PhpSdk } finally { Pop-Location }
$sdk = "$probeRoot/php-sdk/phpsdk-starter.bat"
New-Item "$probeRoot/deps/include", "$probeRoot/deps/lib" -ItemType Directory -Force | Out-Null
$dlls = @{}
foreach ($variant in @('msvc','clang')) {
    $pack = @(Get-ChildItem "$root/input/$variant/php-devel-pack-*.zip")
    if ($pack.Count -ne 1) { throw "Expected one devel pack for $variant" }
    $dir = New-Item "$probeRoot/$variant" -ItemType Directory -Force
    Expand-Archive $pack[0] "$dir/devel"
    $dev = (Get-ChildItem "$dir/devel" -Directory | Select-Object -First 1).FullName
    @'
ARG_ENABLE("validation-probe", "Validation extension", "no");
if (PHP_VALIDATION_PROBE != "no") {
    EXTENSION("validation_probe", "validation_probe.c");
}
'@ | Set-Content "$dir/config.w32"
    @'
#include "php.h"
ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_validation_probe, 0, 0, IS_STRING, 0)
ZEND_END_ARG_INFO()
PHP_FUNCTION(validation_probe) { RETURN_STRING("extension ABI probe passed"); }
static const zend_function_entry probe_functions[] = {
    PHP_FE(validation_probe, arginfo_validation_probe)
    PHP_FE_END
};
zend_module_entry validation_probe_module_entry = {
    STANDARD_MODULE_HEADER, "validation_probe", probe_functions,
    NULL, NULL, NULL, NULL, NULL, "1.0", STANDARD_MODULE_PROPERTIES
};
ZEND_GET_MODULE(validation_probe)
'@ | Set-Content "$dir/validation_probe.c"
    $toolset = if ($variant -eq 'clang') { 'clang' } else { 'vs' }
    @(
        '@echo on',
        ('cd /d "{0}"' -f $dir),
        ('call "{0}\phpize.bat"' -f $dev),
        'if errorlevel 1 exit /b 1',
        ('call configure --enable-validation-probe --with-toolset={0} --with-php-build="{1}\deps" --with-prefix="{2}" --with-mp=disable' -f $toolset,$probeRoot,$Runtimes[$variant]),
        'if errorlevel 1 exit /b 2',
        'nmake /nologo',
        'exit /b %errorlevel%'
    ) | Set-Content "$dir/build.bat" -Encoding ascii
    & $sdk -c vs18 -a $Arch -t "$dir/build.bat" 2>&1 | Tee-Object "$Out/$variant-extension-build.log"
    if ($LASTEXITCODE -ne 0) { throw "$variant extension build failed" }
    $dll = @(Get-ChildItem $dir -Recurse -Filter php_validation_probe.dll)
    if ($dll.Count -ne 1) { throw "Expected one probe DLL for $variant" }
    $dlls[$variant] = $dll[0].FullName
    Copy-Item $dll[0].FullName "$Out/$variant-php_validation_probe.dll"
}
$results = foreach ($runtimeVariant in @('msvc','clang')) {
    foreach ($extensionVariant in @('msvc','clang')) {
        $exe = "$($Runtimes[$runtimeVariant])/php.exe"
        $output = & $exe -n -d "extension=$($dlls[$extensionVariant])" -r 'if (!extension_loaded("validation_probe")) { exit(3); } echo validation_probe();' 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($runtimeVariant -eq $extensionVariant -and $code -ne 0) { throw "$runtimeVariant matching extension rejected: $output" }
        [ordered]@{runtime=$runtimeVariant; extension=$extensionVariant;exitCode=$code;output=$output}
    }
}
$results | ConvertTo-Json -Depth 5 | Set-Content "$Out/extension-compatibility.json"
