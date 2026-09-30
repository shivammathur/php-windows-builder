function Set-ClangPgoSdk {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $SdkDirectory)

    # SDK 2.8.4 forcibly kills CGI and overwrites the request limit. LLVM
    # writes profiles at normal process exit, unlike MSVC's pgosweep.
    $fcgiPath = Join-Path $SdkDirectory 'lib/php/libsdk/SDK/Build/PGO/PHP/FCGI.php'
    $fcgi = Get-Content $fcgiPath -Raw
    $old = '$env[$k] = $v;'
    $new = '$env[$k] = ($k === "PHP_FCGI_MAX_REQUESTS" && getenv($k) !== false) ? getenv($k) : $v;'
    if (-not $fcgi.Contains($old)) { throw 'Unexpected SDK FCGI environment implementation' }
    $fcgi = $fcgi.Replace($old, $new)
    $old = 'exec("taskkill /f /im php-cgi.exe >nul 2>&1");'
    $new = @'
if (getenv("LLVM_PROFILE_FILE")) {
            // Do not race LLVM's atexit profile writer after the final response.
            $deadline = microtime(true) + 60;
            do {
                $processes = shell_exec('tasklist /FI "IMAGENAME eq php-cgi.exe" /NH');
                if (stripos($processes, 'php-cgi.exe') === false) {
                    break;
                }
                if (microtime(true) >= $deadline) {
                    throw new Exception("CGI did not exit normally; refusing incomplete LLVM profiles.");
                }
                usleep(100000);
            } while (true);
        } else {
            exec("taskkill /f /im php-cgi.exe >nul 2>&1");
        }
'@
    if (-not $fcgi.Contains($old)) { throw 'Unexpected SDK FCGI shutdown implementation' }
    Set-Content $fcgiPath $fcgi.Replace($old, $new) -Encoding utf8NoBOM

    $pgoPath = Join-Path $SdkDirectory 'lib/php/libsdk/SDK/Build/PGO/Tool/PGO.php'
    $pgo = Get-Content $pgoPath -Raw
    foreach ($signature in @('public function dump(bool $merge = true) : void', 'public function clean(bool $clean_pgc = true, bool $clean_pgd = true) : void')) {
        $pattern = [regex]::Escape($signature) + '\s*\{'
        if (-not [regex]::IsMatch($pgo, $pattern)) { throw "Unexpected SDK PGO implementation: $signature" }
        $pgo = [regex]::Replace($pgo, $pattern, "$signature`n`t{`n`t`tif (getenv(`"LLVM_PROFILE_FILE`")) { return; }")
    }
    Set-Content $pgoPath $pgo -Encoding utf8NoBOM

    $casePath = Join-Path $SdkDirectory 'lib/php/libsdk/SDK/Build/PGO/Abstracts/TrainingCase.php'
    $case = Get-Content $casePath -Raw
    $needle = 'if (count($stat["not_ok"]) > 0) {'
    if (-not $case.Contains($needle)) { throw 'Unexpected SDK training status implementation' }
    $case = $case.Replace($needle, $needle + ' if (getenv("LLVM_PROFILE_FILE")) { throw new \SDK\Exception("Failed HTTP responses during LLVM PGO training."); }')
    Set-Content $casePath $case -Encoding utf8NoBOM
}
