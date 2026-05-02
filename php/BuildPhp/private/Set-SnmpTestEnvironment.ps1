function Set-SnmpTestEnvironment {
    <#
    .SYNOPSIS
        Configure SNMP test environment: set MIBDIRS, patch snmpd.conf, and start snmpd.
    .PARAMETER TestsDirectoryPath
        Absolute path to the extracted PHP tests directory (use the $testsDirectoryPath from Add-TestRequirements).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $TestsDirectoryPath
    )
    process {
        if (-not $env:DEPS_DIR) {
            throw 'DEPS_DIR is not set. Ensure dependencies are downloaded before SNMP setup.'
        }

        $env:MIBDIRS = Join-Path $env:DEPS_DIR 'share\mibs'
        $buildDirectory = Split-Path -Path $TestsDirectoryPath -Parent
        $snmpArtifactsDirectory = Join-Path $buildDirectory 'snmp'
        $snmpdStatePath = Join-Path $snmpArtifactsDirectory 'snmpd-state.json'
        $snmpdLogPath = Join-Path $snmpArtifactsDirectory 'snmpd.log'
        $snmpdStdOutPath = Join-Path $snmpArtifactsDirectory 'snmpd.stdout.log'
        $snmpdStdErrPath = Join-Path $snmpArtifactsDirectory 'snmpd.stderr.log'

        New-Item -Path $snmpArtifactsDirectory -ItemType Directory -Force > $null 2>&1

        $env:PHP_WINDOWS_BUILDER_SNMPD_STATE = $snmpdStatePath
        $env:PHP_WINDOWS_BUILDER_SNMPD_LOG = $snmpdLogPath
        $env:PHP_WINDOWS_BUILDER_SNMPD_STDOUT = $snmpdStdOutPath
        $env:PHP_WINDOWS_BUILDER_SNMPD_STDERR = $snmpdStdErrPath

        $confPath = Join-Path $TestsDirectoryPath 'ext\snmp\tests\snmpd.conf'
        if (-not (Test-Path -LiteralPath $confPath)) {
            throw "snmpd.conf not found at $confPath"
        }

        $forwardTestsRoot = ($TestsDirectoryPath -replace '\\','/')
        $bigTestJs = "$forwardTestsRoot/ext/snmp/tests/bigtest.js"

        $content = Get-Content -LiteralPath $confPath -Raw -Encoding UTF8
        $newLine = "exec HexTest cscript.exe /nologo $bigTestJs"
        $updated = [System.Text.RegularExpressions.Regex]::Replace(
            $content,
            '^exec\s+HexTest\s+.*$',
            [System.Text.RegularExpressions.MatchEvaluator] { param($match) $newLine },
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )
        if ($updated -ne $content) {
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($confPath, $updated, $utf8NoBom)
        }

        $snmpd = Join-Path $env:DEPS_DIR 'bin\snmpd.exe'
        if (-not (Test-Path -LiteralPath $snmpd)) {
            # We have net-snmp builds without snmpd.exe
            Get-File -Url 'https://downloads.php.net/~windows/php-sdk/deps/vs16/x64/net-snmp-5.7.3-3-vs16-x64.zip' -OutFile "net-snmp-5.7.3-3-vs16-x64.zip"
            Expand-Archive -Path "net-snmp-5.7.3-3-vs16-x64.zip" -DestinationPath $env:DEPS_DIR -Force
            if (-not (Test-Path -LiteralPath $snmpd)) {
                throw "snmpd.exe not found at $snmpd"
            }
        }
        $existingProcess = $null
        if (Test-Path -LiteralPath $snmpdStatePath) {
            try {
                $snmpdState = Get-Content -LiteralPath $snmpdStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $snmpdState -and $null -ne $snmpdState.Pid) {
                    $existingProcess = Get-Process -Id ([int] $snmpdState.Pid) -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Warning "Unable to read SNMP state file at ${snmpdStatePath}: $($_.Exception.Message)"
            }
        }

        if ($null -ne $existingProcess) {
            $env:PHP_WINDOWS_BUILDER_SNMPD_PID = [string] $existingProcess.Id
            return
        }

        foreach ($diagnosticPath in @($snmpdLogPath, $snmpdStdOutPath, $snmpdStdErrPath)) {
            if (Test-Path -LiteralPath $diagnosticPath) {
                Remove-Item -LiteralPath $diagnosticPath -Force
            }
        }

        $snmpdProcess = Start-Process -FilePath $snmpd `
                                      -ArgumentList @('-f', '-C', '-c', $confPath, '-Lf', $snmpdLogPath) `
                                      -RedirectStandardOutput $snmpdStdOutPath `
                                      -RedirectStandardError $snmpdStdErrPath `
                                      -WindowStyle Hidden `
                                      -PassThru

        Start-Sleep -Seconds 1

        $env:PHP_WINDOWS_BUILDER_SNMPD_PID = [string] $snmpdProcess.Id
        [pscustomobject] @{
            Pid = $snmpdProcess.Id
            ConfPath = $confPath
            LogPath = $snmpdLogPath
            StdOutPath = $snmpdStdOutPath
            StdErrPath = $snmpdStdErrPath
            StartedAtUtc = [DateTime]::UtcNow.ToString('o')
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath $snmpdStatePath -Encoding UTF8

        if ($snmpdProcess.HasExited) {
            $errorDetails = @()
            foreach ($diagnosticPath in @($snmpdLogPath, $snmpdStdErrPath, $snmpdStdOutPath)) {
                if (Test-Path -LiteralPath $diagnosticPath) {
                    $tail = Get-Content -LiteralPath $diagnosticPath -Tail 40
                    if ($tail.Count -gt 0) {
                        $errorDetails += "[$diagnosticPath]`n$($tail -join [Environment]::NewLine)"
                    }
                }
            }

            $message = "snmpd exited immediately after startup. See diagnostics in $snmpArtifactsDirectory."
            if ($errorDetails.Count -gt 0) {
                $message = "$message`n$($errorDetails -join [Environment]::NewLine)"
            }

            throw $message
        }
    }
}
