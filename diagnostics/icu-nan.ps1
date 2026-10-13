param([Parameter(Mandatory)][string]$Arch)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
New-Item results -ItemType Directory -Force | Out-Null
$artifact = switch ($Arch) {
    arm64 { @{id=11820085788;sha='48320c3e5cd1417f457e2bcff5666283b97047dad034d2f3c7ca6fe5db06d613'} }
    x64 { @{id=11819324701;sha='75e78543b647632f50aed0db1991cc4fedf55e1cbec2baed3f3d8ca89735a6df'} }
    default { throw 'Unexpected architecture' }
}
Invoke-WebRequest "https://api.github.com/repos/winlibs/winlib-builder/actions/artifacts/$($artifact.id)/zip" -Headers @{Authorization="Bearer $env:GH_TOKEN"} -OutFile icu.zip
if ((Get-FileHash icu.zip).Hash -ne $artifact.sha) { throw 'ICU artifact digest mismatch' }
$artifact | ConvertTo-Json | Set-Content results/artifact.json
Expand-Archive icu.zip icu
$header = @(Get-ChildItem icu -Filter unum.h -Recurse)
if ($header.Count -ne 1) { throw 'Unexpected ICU layout' }
$include = $header[0].Directory.Parent.FullName
$lib = @(Get-ChildItem icu -Filter icuin.lib -Recurse)
if ($lib.Count -ne 1) { throw 'Unexpected ICU libraries' }
$libs = $lib[0].Directory.FullName
$dll = @(Get-ChildItem icu -Filter icuin*.dll -Recurse)
if ($dll.Count -ne 1) { throw 'Unexpected ICU runtime' }
$env:PATH = "$($dll[0].Directory.FullName);$env:PATH"
Get-ChildItem icu -Recurse -File | Sort-Object FullName | Get-FileHash | ConvertTo-Json | Set-Content results/icu-hashes.json
Get-Command cl.exe | Select-Object Source | ConvertTo-Json | Set-Content results/compiler.json
& cl /nologo /EHsc /MD /O2 /std:c++17 "/I$include" diagnostics/icu-nan.cpp /Foresults/icu-nan.obj /Feresults/icu-nan.exe /link "/LIBPATH:$libs" icuin.lib icuuc.lib icudt.lib 2>&1 | Tee-Object results/build.log
if ($LASTEXITCODE) { throw 'ICU API control did not compile' }
& dumpbin /headers results/icu-nan.exe > results/headers.txt
& ./results/icu-nan.exe | Tee-Object results/output.txt
if ($LASTEXITCODE) { throw 'ICU API control failed' }
