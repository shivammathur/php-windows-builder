param([ValidateSet('original','no-shrink-wrap')][string]$Mode,[ValidateSet('nocache','opcache')][string]$Cache)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$workspace=(Get-Location).Path
$results=(New-Item results -ItemType Directory -Force).FullName
$sourceSha='6d72982f6f2f42fbfb6523ed777cb217f8925afd'
$builderSha='1d4e815ca5467192388eb2c89d1227522cf1e3d5'
if ((git -C source rev-parse HEAD) -ne $sourceSha -or (git -C builder rev-parse HEAD) -ne $builderSha) { throw 'Reviewed branches changed' }
$zip="$workspace/artifacts/php-8.6.0-dev-Win32-vs18-arm64.zip"
$originalHash=(Get-FileHash $zip).Hash
if ($originalHash -ne 'B75908B86982D42EF48178A6DF8119573B3488500F58B901AC2F64ECB0FEB2CB') { throw 'Original package changed' }
function Get-Entries([string]$Path) {
    $z=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $map=@{}
        foreach($entry in $z.Entries) {
            $stream=$entry.Open()
            try {$map[$entry.FullName]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))} finally {$stream.Dispose()}
        }
        $map
    } finally {$z.Dispose()}
}
$before=Get-Entries $zip
if ($Mode -eq 'no-shrink-wrap') {
    $dll="$workspace/relink/php8ts.dll"
    if ((Get-FileHash $dll).Hash -ne '6243C8EC5F336157E29DA82FCEAA38C68216859CB3656421E114D182EAE59EEB') { throw 'Controlled link DLL changed' }
    $z=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry=$z.GetEntry('php8ts.dll')
        if (-not $entry) {throw 'Missing core DLL'}
        $entry.Delete()
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$dll,'php8ts.dll')|Out-Null
    } finally {$z.Dispose()}
}
$after=Get-Entries $zip
$changed=@($before.Keys|Where-Object {$before[$_] -cne $after[$_]})
if ($before.Count -ne $after.Count -or ($Mode -eq 'original' -and $changed.Count) -or ($Mode -ne 'original' -and ($changed.Count -ne 1 -or $changed[0] -cne 'php8ts.dll'))) {throw 'Unexpected runtime package changes'}
@{mode=$Mode;cache=$Cache;source=$sourceSha;builder=$builderSha;originalPackage=$originalHash;runtimePackage=(Get-FileHash $zip).Hash;changedEntries=$changed;coreHash=$after['php8ts.dll']}|ConvertTo-Json|Set-Content "$results/provenance.json"
Import-Module "$workspace/builder/php/BuildPhp" -Force
Push-Location "$workspace/artifacts"
try {
    Invoke-PhpTests -PhpVersion '8.6.0-dev' -Arch arm64 -Ts ts -Opcache $Cache -TestType php -SourceRepository shivammathur/php-src -SourceRef fix/windows-arm64-8.6
} finally {Pop-Location}
$report="$workspace/artifacts/test-arm64-ts-$Cache-php.xml"
if (-not(Test-Path $report)) {throw 'No core report'}
Copy-Item "$workspace/artifacts/test-arm64-ts-$Cache-php.*" $results
$testRoot=Join-Path (Split-Path $env:TEST_PHP_JUNIT) tests
$sourceFiles=@(foreach($dir in 'Zend/tests','tests','sapi/cgi/tests','sapi/cli/tests'){Get-ChildItem "$workspace/source/$dir" -Recurse -File -Filter *.phpt})
foreach($file in $sourceFiles) {
    $relative=[IO.Path]::GetRelativePath("$workspace/source",$file.FullName)
    if ((Get-FileHash $file.FullName).Hash -cne (Get-FileHash (Join-Path $testRoot $relative)).Hash) {throw "Test source differs: $relative"}
}
Copy-Item (Join-Path (Split-Path $testRoot) 'phpbin/php-test.ini') "$results/php-test.ini"
Copy-Item "$testRoot/php-tests-to-run.txt" $results
$xml=[xml](Get-Content $report -Raw)
$cases=$xml.SelectNodes('//testcase')
if ($cases.Count -ne 6655) {throw "Unexpected full core coverage: $($cases.Count)"}
@{sourceFilesVerified=$sourceFiles.Count;cases=$cases.Count;skips=$xml.SelectNodes('//testcase[skipped]').Count;failures=@($xml.SelectNodes('//testcase[failure or error]')|ForEach-Object OuterXml)}|ConvertTo-Json -Depth 6|Set-Content "$results/review.json"
$global:LASTEXITCODE=0
