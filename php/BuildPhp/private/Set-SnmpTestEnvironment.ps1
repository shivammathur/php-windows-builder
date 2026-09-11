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
        $env:SNMP_MIBDIR = $env:MIBDIRS

        $confPath = Join-Path $TestsDirectoryPath 'ext\snmp\tests\snmpd.conf'
        if (-not (Test-Path -LiteralPath $confPath)) {
            throw "snmpd.conf not found at $confPath"
        }

        $forwardTestsRoot = ($TestsDirectoryPath -replace '\\','/')
        $bigTestJs = "$forwardTestsRoot/ext/snmp/tests/bigtest.js"
        # Windows equivalent of php-src's POSIX bigtest fixture: the same
        # 18 octal-escaped bytes repeated 32 times, without a trailing newline.
        $bigTestScript = @'
var bytes = [3, 2, 4, 9, 18, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];
var output = "";
for (var i = 0; i < 32; i++) {
    for (var j = 0; j < bytes.length; j++) output += String.fromCharCode(bytes[j]);
}
WScript.StdOut.Write(output);
'@
        [System.IO.File]::WriteAllText($bigTestJs, $bigTestScript, [System.Text.UTF8Encoding]::new($false))

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
        if(-not(Test-Path snmpd_running)) {
            $agent = Start-Process -FilePath $snmpd -ArgumentList @('-C','-c', $confPath, '-Ln') -WindowStyle Hidden -PassThru
            Start-Sleep -Seconds 2
            if ($agent.HasExited) {
                throw "The SNMP test agent exited during startup with code $($agent.ExitCode)."
            }
            Set-Content -Path snmpd_running -Value "running" -Encoding ASCII
        }
    }
}
