function Set-ClangPgoSdk {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $SdkDirectory)

    # Packaging and SBOM export parse the compiler from the archive name.
    $sbomPath = Join-Path $SdkDirectory 'bin/phpsdk_sbom.php'
    $sbom = Get-Content $sbomPath -Raw
    $compilerPattern = 'v[sc]\d+'
    if (($sbom.Split($compilerPattern)).Count -ne 3) { throw 'Unexpected SDK archive-name parser' }
    Set-Content $sbomPath $sbom.Replace($compilerPattern, '(?:v[sc]\d+|clang)') -Encoding utf8NoBOM

    # SDK 2.8.4 forcibly kills CGI and overwrites the request limit. LLVM
    # writes profiles at normal process exit, unlike MSVC's pgosweep.
    $fcgiPath = Join-Path $SdkDirectory 'lib/php/libsdk/SDK/Build/PGO/PHP/FCGI.php'
    $fcgi = Get-Content $fcgiPath -Raw
    $old = '$env[$k] = $v;'
    $new = @'
if ($k === "PHP_FCGI_CHILDREN" && getenv("LLVM_PROFILE_FILE")) {
                // One worker must serve all requests and exit; the CGI parent
                // otherwise respawns eight workers and never flushes normally.
                $env[$k] = 0;
            } else {
                $env[$k] = ($k === "PHP_FCGI_MAX_REQUESTS" && getenv($k) !== false) ? getenv($k) : $v;
            }
'@
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

    $initPath = Join-Path $SdkDirectory 'pgo/cases/pgo01org/TrainingCaseHandler.php'
    $init = Get-Content $initPath -Raw
    $needle = '$out = file_get_contents("http://$http_host:$http_port/init.php");'
    if (-not $init.Contains($needle)) { throw 'Unexpected SDK training initialization' }
    $init = $init.Replace($needle, $needle + ' if (getenv("LLVM_PROFILE_FILE") && $out === false) { throw new \SDK\Exception("LLVM PGO initialization HTTP request failed."); }')
    Set-Content $initPath $init -Encoding utf8NoBOM
}
