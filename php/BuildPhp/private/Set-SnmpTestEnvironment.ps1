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

        $confPath = Join-Path $TestsDirectoryPath 'ext\snmp\tests\snmpd.conf'
        if (-not (Test-Path -LiteralPath $confPath)) {
            throw "snmpd.conf not found at $confPath"
        }

        $forwardTestsRoot = ($TestsDirectoryPath -replace '\\','/')
        $bigTestJs = "$forwardTestsRoot/ext/snmp/tests/bigtest.js"
        if (-not (Test-Path -LiteralPath $bigTestJs)) {
            # Windows equivalent of the older test pack's bigtest shell script.
            @'
for (var i = 0; i < 32; i++) {
    WScript.StdOut.Write("\x03\x02\x04\x09\x12\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17");
}
'@ | Set-Content -LiteralPath $bigTestJs -Encoding ASCII
        }

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
            # The daemon is a separate process. Never overwrite the tested
            # package's x86/version-specific dependency DLLs with x64 files.
            $daemonDirectory = Join-Path $env:SystemDrive 'php-test-snmpd'
            New-Item -ItemType Directory -Path $daemonDirectory -Force | Out-Null
            $archive = Join-Path $daemonDirectory 'snmpd.zip'
            Get-File -Url 'https://downloads.php.net/~windows/php-sdk/deps/vs16/x64/net-snmp-5.7.3-3-vs16-x64.zip' -OutFile $archive
            Expand-Archive -Path $archive -DestinationPath $daemonDirectory -Force
            $snmpd = Join-Path $daemonDirectory 'bin\snmpd.exe'
            $env:MIBDIRS = Join-Path $daemonDirectory 'share\mibs'
            if (-not (Test-Path -LiteralPath $snmpd)) {
                throw "snmpd.exe not found at $snmpd"
            }
        }
        if(-not(Test-Path snmpd_running)) {
            $daemon = Start-Process -FilePath $snmpd -ArgumentList @('-C','-c', "`"$confPath`"", '-Ln') -WindowStyle Hidden -PassThru
            Start-Sleep -Seconds 2
            if ($daemon.HasExited) { throw "SNMP test daemon exited with code $($daemon.ExitCode)." }
            Set-Content -Path snmpd_running -Value "running" -Encoding ASCII
        }
        $env:SNMP_MIBDIR = $env:MIBDIRS
    }
}
