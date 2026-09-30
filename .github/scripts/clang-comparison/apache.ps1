param([string]$Arch, [hashtable]$Runtimes, [string]$Out)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$Out = $Out.Replace('\','/')
$archive = if ($Arch -eq 'x64') { 'httpd-2.4.68-260920-Win64-VS18.zip' } else { 'httpd-2.4.68-260920-win32-vs18.zip' }
$hash = if ($Arch -eq 'x64') { 'F6DCF17D08AA32721AE418CD818C157E4C521C9E889B758646FB64287F1D56E3' } else { '69E0A8A8C6284ED85CAC10B9ED1FA809E2DE91159E1A7CD7133FBE93EFFCD426' }
Invoke-WebRequest "https://www.apachelounge.com/download/VS18/binaries/$archive" -OutFile "$root/apache.zip"
if ((Get-FileHash "$root/apache.zip" -Algorithm SHA256).Hash -ne $hash) { throw 'Apache fixture checksum mismatch' }
Expand-Archive "$root/apache.zip" "$root/apache"
$server = (Get-ChildItem "$root/apache" -Recurse -Filter httpd.exe).FullName
$serverRoot = (Split-Path (Split-Path $server)).Replace('\','/')
$docroot = (New-Item "$root/apache-docroot" -ItemType Directory -Force).FullName.Replace('\','/')
@'
<?php
header('Content-Type: application/json');
$id = (int) $_GET['id'];
usleep(20000);
$db = new PDO('sqlite::memory:');
$value = $db->query('SELECT ' . $id)->fetchColumn();
$image = imagecreatetruecolor(8, 8);
ob_start(); imagepng($image); $png = ob_get_clean();
echo json_encode(['id' => $id, 'header' => $_SERVER['HTTP_X_VALIDATION_ID'] ?? '', 'sapi' => PHP_SAPI,
    'zts' => PHP_ZTS, 'pdo' => $value, 'gd' => strlen($png) > 0,
    'hash' => hash('sha256', str_repeat('clang-validation', 1000)),
    'intl' => Normalizer::normalize("e\u{0301}")]);
'@ | Set-Content "$docroot/test.php" -Encoding utf8NoBOM
$savedPath = $env:Path
$results = @()
foreach ($variant in @('msvc','clang')) {
    $runtime = $Runtimes[$variant].Replace('\','/')
    $env:Path = "$runtime;$savedPath"
    $ini = Write-TestIni $runtime 'opcache'
    Copy-Item $ini "$runtime/php.ini" -Force
    $config = "$Out/$variant-apache.conf".Replace('\','/')
    @"
ServerRoot "$serverRoot"
ServerName 127.0.0.1
Listen 127.0.0.1:18080
PidFile "$Out/$variant-apache.pid"
ErrorLog "$Out/$variant-apache-error.log"
LogLevel warn
ThreadsPerChild 32
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule php_module "$runtime/php8apache2_4.dll"
PHPIniDir "$runtime"
DocumentRoot "$docroot"
<Directory "$docroot">
    Require all granted
</Directory>
<FilesMatch "\.php$">
    SetHandler application/x-httpd-php
</FilesMatch>
"@ | Set-Content $config -Encoding ascii
    & $server -t -f $config 2>&1 | Set-Content "$Out/$variant-apache-config.txt"
    if ($LASTEXITCODE -ne 0) { throw "$variant Apache configuration/module load failed" }
    $process = Start-Process $server -ArgumentList @('-X','-f',('"' + $config + '"')) -PassThru -RedirectStandardOutput "$Out/$variant-apache-stdout.log" -RedirectStandardError "$Out/$variant-apache-stderr.log"
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    try {
        $ready = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            if ($process.HasExited) { throw "$variant Apache exited: $($process.ExitCode)" }
            try { $null = $client.GetStringAsync('http://127.0.0.1:18080/test.php?id=0').GetAwaiter().GetResult(); $ready = $true; break } catch { Start-Sleep -Milliseconds 200 }
        }
        if (-not $ready) { throw "$variant Apache did not become ready" }
        $requests = foreach ($id in 1..64) {
            $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, "http://127.0.0.1:18080/test.php?id=$id")
            $request.Headers.Add('X-Validation-Id', [string]$id)
            @{id=$id; message=$request; task=$client.SendAsync($request)}
        }
        foreach ($request in $requests) {
            $response = $request.task.GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            if (-not $response.IsSuccessStatusCode -or $body.id -ne $request.id -or $body.header -ne [string]$request.id -or $body.pdo -ne $request.id -or $body.sapi -ne 'apache2handler' -or -not $body.zts -or -not $body.gd -or $body.intl -ne [string][char]0xe9) { throw "$variant Apache request $($request.id) failed" }
            $results += [ordered]@{variant=$variant; response=$body}
            $response.Dispose(); $request.message.Dispose()
        }
    } finally {
        $client.Dispose()
        if (-not $process.HasExited) { & taskkill /PID $process.Id /T /F | Out-Null }
        $env:Path = $savedPath
    }
}
if (@($results.response.hash | Sort-Object -Unique).Count -ne 1) { throw 'Apache compiler checksums differ' }
$results | ConvertTo-Json -Depth 5 | Set-Content "$Out/apache-results.json"
