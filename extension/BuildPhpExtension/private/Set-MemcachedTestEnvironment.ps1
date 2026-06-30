Function Set-MemcachedTestEnvironment {
    <#
    .SYNOPSIS
        Set up and verify the Memcached extension test server.
    .PARAMETER Config
        Extension Configuration
    #>
    [OutputType()]
    param(
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Extension Configuration')]
        [PSCustomObject] $Config
    )
    process {
        $currentDirectory = (Get-Location).Path
        $testsDirectory = Join-Path $currentDirectory 'tests'
        if (-not (Test-Path -LiteralPath (Join-Path $testsDirectory 'config.inc') -PathType Leaf)) {
            return
        }

        $php = Join-Path $currentDirectory 'php-bin\php.exe'
        $extensionPath = Join-Path (Join-Path $currentDirectory $Config.build_directory) 'php_memcached.dll'
        if (-not (Test-Path -LiteralPath $php -PathType Leaf)) {
            throw "PHP executable for memcached tests does not exist: $php"
        }
        if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) {
            throw "memcached extension DLL does not exist: $extensionPath"
        }

        function Invoke-MemcachedPhpProbe {
            param(
                [Parameter(Mandatory = $true)][string] $Php,
                [Parameter(Mandatory = $true)][string] $Extension,
                [Parameter(Mandatory = $true)][string] $Probe,
                [Parameter(Mandatory = $false)][int] $TimeoutSeconds = 30
            )

            $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("memcached-probe-stdout-$([Guid]::NewGuid().ToString('N')).log")
            $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("memcached-probe-stderr-$([Guid]::NewGuid().ToString('N')).log")
            try {
                $arguments = @(
                    '-n',
                    '-d', 'display_startup_errors=1',
                    '-d', 'display_errors=1',
                    '-d', 'error_reporting=-1',
                    '-d', "extension=$Extension",
                    $Probe
                )
                $process = Start-Process -FilePath $Php -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
                if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    $stdout = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
                    $stderr = @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
                    throw "PHP Memcached probe timed out after $TimeoutSeconds seconds. stdout=$($stdout -join "`n") stderr=$($stderr -join "`n")"
                }

                $stdout = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
                $stderr = @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
                return [PSCustomObject]@{
                    ExitCode = $process.ExitCode
                    Output = @($stdout + $stderr)
                }
            } finally {
                Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
            }
        }

        $env:SKIP_SLOW_TESTS = '1'
        $probePath = Join-Path ([System.IO.Path]::GetTempPath()) ("memcached-probe-$([Guid]::NewGuid().ToString('N')).php")
@'
<?php
echo "MEMCACHED_PROBE_BOOT\n";
if (!extension_loaded('memcached')) {
    fwrite(STDERR, "memcached extension is not loaded\n");
    exit(1);
}

$hosts = array();
foreach (array(getenv('MEMC_SERVER_HOST'), '127.0.0.1', 'localhost', '::1') as $host) {
    if ($host !== false && $host !== '' && !in_array($host, $hosts, true)) {
        $hosts[] = $host;
    }
}

$ports = array();
foreach (array(getenv('MEMC_SERVER_PORT'), '11211') as $port) {
    $port = (int) $port;
    if ($port > 0 && !in_array($port, $ports, true)) {
        $ports[] = $port;
    }
}

$errors = array();
function memcached_result($memcached) {
    return $memcached->getResultCode() . ' ' . $memcached->getResultMessage();
}

foreach ($hosts as $host) {
    foreach ($ports as $port) {
        echo "MEMCACHED_PROBE_TRY=$host:$port\n";
        $ok = true;
        $checks = array();

        foreach (array(false, true) as $binary) {
            $label = $binary ? 'binary' : 'ascii';
            $memcached = new Memcached();
            echo "MEMCACHED_PROBE_NEW_OK=" . $host . ":" . $port . ":" . $label . "\n";

            $setProtocol = @$memcached->setOption(Memcached::OPT_BINARY_PROTOCOL, $binary);
            echo "MEMCACHED_PROBE_PROTOCOL=" . $host . ":" . $port . ":" . $label . ":" . ($setProtocol ? 'true' : 'false') . "\n";
            if (!$setProtocol) {
                $ok = false;
                $checks[] = "$label protocol=false result=" . memcached_result($memcached);
                continue;
            }

            $added = @$memcached->addServer($host, $port);
            echo "MEMCACHED_PROBE_ADD=" . $host . ":" . $port . ":" . $label . ":" . ($added ? 'true' : 'false') . "\n";
            if (!$added) {
                $ok = false;
                $checks[] = "$label add=false result=" . memcached_result($memcached);
                continue;
            }

            $flushed = @$memcached->flush();
            echo "MEMCACHED_PROBE_FLUSH=" . $host . ":" . $port . ":" . $label . ":" . ($flushed !== false ? 'true' : 'false') . "\n";
            if ($flushed === false) {
                $ok = false;
                $checks[] = "$label flush=false result=" . memcached_result($memcached);
                continue;
            }

            $key = 'php_windows_builder_memcached_probe_' . $label . '_' . bin2hex(random_bytes(4));
            $value = 'probe-value-' . $label . '-' . str_repeat('x', 64);
            $stored = @$memcached->set($key, $value, 60);
            $read = $stored ? @$memcached->get($key) : false;
            $deleted = $stored ? @$memcached->delete($key) : false;
            echo "MEMCACHED_PROBE_ROUNDTRIP=" . $host . ":" . $port . ":" . $label . ":" . ($stored && $read === $value && $deleted ? 'true' : 'false') . "\n";
            if (!$stored || $read !== $value || !$deleted) {
                $ok = false;
                $checks[] = "$label roundtrip=false stored=" . ($stored ? 'true' : 'false') . " read=" . var_export($read, true) . " deleted=" . ($deleted ? 'true' : 'false') . " result=" . memcached_result($memcached);
            }
        }

        if ($ok) {
            echo "MEMCACHED_TEST_CONFIG=" . json_encode(array(
                'host' => $host,
                'port' => $port,
                'status' => 'usable',
            )) . "\n";
            exit(0);
        }

        $errors[] = sprintf(
            '%s:%d %s',
            $host,
            $port,
            implode(', ', $checks)
        );
    }
}

$fallbackHost = count($hosts) > 0 ? $hosts[0] : '127.0.0.1';
$fallbackPort = count($ports) > 0 ? $ports[0] : 11211;
echo "MEMCACHED_TEST_CONFIG=" . json_encode(array(
    'host' => $fallbackHost,
    'port' => $fallbackPort,
    'status' => 'unusable',
    'errors' => $errors,
)) . "\n";
exit(0);
'@ | Set-Content -LiteralPath $probePath -Encoding ASCII

        try {
            $probe = Invoke-MemcachedPhpProbe -Php $php -Extension $extensionPath -Probe $probePath -TimeoutSeconds 30
            $probeOutput = @($probe.Output)
            $probeExitCode = $probe.ExitCode
            $probeOutput | ForEach-Object { Write-Host $_ }
            if ($probeExitCode -ne 0) {
                throw "PHP Memcached could not select any configured test server. exit_code=$probeExitCode Output: $($probeOutput -join "`n")"
            }

            $configLine = $probeOutput | Where-Object { $_ -match '^MEMCACHED_TEST_CONFIG=' } | Select-Object -Last 1
            if ([string]::IsNullOrWhiteSpace($configLine)) {
                throw "PHP Memcached probe did not report MEMCACHED_TEST_CONFIG. Output: $($probeOutput -join "`n")"
            }

            $server = ($configLine -replace '^MEMCACHED_TEST_CONFIG=', '') | ConvertFrom-Json
            $env:MEMC_SERVER_HOST = $server.host
            $env:MEMC_SERVER_PORT = [string] $server.port

            Set-Content (Join-Path $testsDirectory 'config.inc.local') -Encoding ASCII -Value @"
<?php
define("MEMC_SERVER_HOST", "$($server.host)");
define("MEMC_SERVER_PORT", $($server.port));
"@
            if ($server.status -eq 'usable') {
                Write-Host "Memcached PHPT server selected by PHP client: $($server.host):$($server.port) (ascii and binary round trips OK)"
            } else {
                Write-Host "Memcached PHP client could not complete ascii/binary round trips against any configured server. Raw text fallback is not used; upstream skipif will classify server-backed PHPTs."
                foreach ($error in @($server.errors)) {
                    Write-Host "Memcached probe failure: $error"
                }
            }
        } finally {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}
