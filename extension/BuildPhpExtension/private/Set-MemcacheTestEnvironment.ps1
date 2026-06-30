Function Set-MemcacheTestEnvironment {
    <#
    .SYNOPSIS
        Set up and verify the Memcache extension test servers.
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
        if (-not (Test-Path -LiteralPath (Join-Path $testsDirectory 'connect.inc') -PathType Leaf)) {
            return
        }

        $php = Join-Path $currentDirectory 'php-bin\php.exe'
        $extensionPath = Join-Path (Join-Path $currentDirectory $Config.build_directory) 'php_memcache.dll'
        if (-not (Test-Path -LiteralPath $php -PathType Leaf)) {
            throw "PHP executable for memcache tests does not exist: $php"
        }
        if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) {
            throw "memcache extension DLL does not exist: $extensionPath"
        }

        function Invoke-MemcachePhpProbe {
            param(
                [Parameter(Mandatory = $true)][string] $Php,
                [Parameter(Mandatory = $true)][string] $Extension,
                [Parameter(Mandatory = $true)][string] $Probe,
                [Parameter(Mandatory = $false)][int] $TimeoutSeconds = 30
            )

            $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("memcache-probe-stdout-$([Guid]::NewGuid().ToString('N')).log")
            $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("memcache-probe-stderr-$([Guid]::NewGuid().ToString('N')).log")
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
                    throw "PHP Memcache probe timed out after $TimeoutSeconds seconds. stdout=$($stdout -join "`n") stderr=$($stderr -join "`n")"
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

        $probePath = Join-Path ([System.IO.Path]::GetTempPath()) ("memcache-probe-$([Guid]::NewGuid().ToString('N')).php")
@'
<?php
echo "MEMCACHE_PROBE_BOOT\n";
if (!extension_loaded('memcache')) {
    fwrite(STDERR, "memcache extension is not loaded\n");
    exit(1);
}

$host = getenv('MEMC_SERVER_HOST');
if ($host === false || $host === '') {
    $host = '127.0.0.1';
}
$port = (int) (getenv('MEMC_SERVER_PORT') ?: 11211);
$port2 = (int) (getenv('MEMC_SERVER_PORT_2') ?: 11212);

function memcache_probe_server($host, $port, $label, &$error) {
    echo "MEMCACHE_PROBE_TRY=$host:$port:$label\n";
    $memcache = @memcache_connect($host, $port, 1.0);
    if (!$memcache) {
        $error = "$label connect failed";
        return false;
    }

    $key = 'php_windows_builder_memcache_probe_' . $label . '_' . bin2hex(random_bytes(4));
    $value = 'probe-value-' . $label . '-' . str_repeat('x', 64);
    $stored = @memcache_set($memcache, $key, $value, false, 60);
    $read = $stored ? @memcache_get($memcache, $key) : false;
    $duplicate = $stored ? @memcache_add($memcache, $key, $value, false, 60) : null;
    $deleted = $stored ? @memcache_delete($memcache, $key) : false;
    @memcache_close($memcache);

    if (!$stored || $read !== $value || $duplicate !== false || !$deleted) {
        $error = "$label roundtrip failed stored=" . ($stored ? 'true' : 'false') . " read=" . var_export($read, true) . " duplicate=" . var_export($duplicate, true) . " deleted=" . ($deleted ? 'true' : 'false');
        return false;
    }

    echo "MEMCACHE_PROBE_ROUNDTRIP=$host:$port:$label:true\n";
    return true;
}

$errors = array();
$ok1 = memcache_probe_server($host, $port, 'primary', $error1);
if (!$ok1) {
    $errors[] = $error1;
}
$ok2 = memcache_probe_server($host, $port2, 'secondary', $error2);
if (!$ok2) {
    $errors[] = $error2;
}

if (!$ok1 || !$ok2) {
    fwrite(STDERR, "No usable memcache test server pair found via PHP Memcache: " . implode(' | ', $errors) . "\n");
    exit(1);
}

echo "MEMCACHE_TEST_CONFIG=" . json_encode(array(
    'host' => $host,
    'port' => $port,
    'host2' => $host,
    'port2' => $port2,
)) . "\n";
exit(0);
'@ | Set-Content -LiteralPath $probePath -Encoding ASCII

        try {
            $probe = Invoke-MemcachePhpProbe -Php $php -Extension $extensionPath -Probe $probePath -TimeoutSeconds 30
            $probeOutput = @($probe.Output)
            $probeExitCode = $probe.ExitCode
            $probeOutput | ForEach-Object { Write-Host $_ }
            if ($probeExitCode -ne 0) {
                throw "PHP Memcache could not validate the configured test server pair. exit_code=$probeExitCode Output: $($probeOutput -join "`n")"
            }

            $configLine = $probeOutput | Where-Object { $_ -match '^MEMCACHE_TEST_CONFIG=' } | Select-Object -Last 1
            if ([string]::IsNullOrWhiteSpace($configLine)) {
                throw "PHP Memcache probe did not report MEMCACHE_TEST_CONFIG. Output: $($probeOutput -join "`n")"
            }

            $server = ($configLine -replace '^MEMCACHE_TEST_CONFIG=', '') | ConvertFrom-Json
            $env:MEMC_SERVER_HOST = $server.host
            $env:MEMC_SERVER_PORT = [string] $server.port
            $env:MEMC_SERVER_PORT_2 = [string] $server.port2
            Write-Host "Memcache PHPT servers selected by PHP client: $($server.host):$($server.port), $($server.host2):$($server.port2)"
        } finally {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}
