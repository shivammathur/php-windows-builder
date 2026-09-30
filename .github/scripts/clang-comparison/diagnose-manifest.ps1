$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$out = New-Item "$root/diagnostics" -ItemType Directory -Force
$zip = @(Get-ChildItem "$root/input/php-8*.zip")
if ($zip.Count -ne 1) { throw 'Expected one runtime archive' }
$runtime = "$root/manifest-runtime"
Expand-Archive $zip[0] $runtime
$probe = 'echo json_encode(["major"=>PHP_WINDOWS_VERSION_MAJOR,"minor"=>PHP_WINDOWS_VERSION_MINOR,"build"=>PHP_WINDOWS_VERSION_BUILD,"uname"=>php_uname()]);'
& "$runtime/php.exe" -n -r $probe | Set-Content "$out/before.json"
if ($LASTEXITCODE -ne 0) { throw 'Initial runtime probe failed' }
$mt = (Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/mt.exe" | Sort-Object FullName -Descending | Select-Object -First 1).FullName
foreach ($binary in Get-ChildItem $runtime -Recurse -File | Where-Object Name -Match '^php.*\.(exe|dll)$') {
    $id = if ($binary.Extension -eq '.exe') { 1 } else { 2 }
    & $mt -nologo -manifest "$root/source/win32/build/default.manifest" "-outputresource:$($binary.FullName);$id"
    if ($LASTEXITCODE -ne 0) { throw "Manifest embedding failed: $binary" }
}
& "$runtime/php.exe" -n -r $probe | Set-Content "$out/after.json"
if ($LASTEXITCODE -ne 0) { throw 'Manifested runtime probe failed' }
$env:TEST_PHP_EXECUTABLE = "$runtime/php.exe"
$env:TEST_PHP_JUNIT = "$out/results.xml"
$env:NO_INTERACTION = '1'
$env:REPORT_EXIT_STATUS = '1'
Set-Location "$root/source"
& "$runtime/php.exe" -n run-tests.php -n -q --offline --no-progress --show-diff ext/standard/tests/file/ghsa-9f67-6fw4-hpfp-win32.phpt ext/standard/tests/strings/bug65769.phpt 2>&1 | Tee-Object "$out/tests.log"
if ($LASTEXITCODE -ne 0) { throw 'Manifest regression tests failed' }
