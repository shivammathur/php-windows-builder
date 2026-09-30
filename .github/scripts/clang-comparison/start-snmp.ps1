param([string]$Runtime, [string]$Variant)
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$qa = "$root/qa-services"
if (-not (Test-Path "$qa/snmp/bin/snmpd.exe")) { return }
# SNMP tests modify agent state. Start each compiler with a fresh daemon and
# persistent store so the second compiler does not inherit the first's state.
Get-CimInstance Win32_Process -Filter "Name='snmpd.exe'" |
    Where-Object { $_.ExecutablePath -eq "$qa/snmp/bin/snmpd.exe".Replace('/', '\') } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$env:SNMP_PERSISTENT_DIR = "$qa/snmp-state-$Variant"
New-Item $env:SNMP_PERSISTENT_DIR -ItemType Directory -Force | Out-Null
$server = Start-Process "$qa/snmp/bin/snmpd.exe" -ArgumentList @('-C','-c',"$qa/snmpd.conf",'-Ln') -PassThru -RedirectStandardOutput "$root/regressions/$Variant-snmp-server.log" -RedirectStandardError "$root/regressions/$Variant-snmp-server-errors.log"
$ready = $false
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    if ($server.WaitForExit(1000)) { throw "SNMP fixture exited: $($server.ExitCode)" }
    & "$Runtime/php.exe" -n -d "extension_dir=$Runtime/ext" -d extension=php_snmp.dll -r 'exit(@snmp2_get("127.0.0.1", "public", ".1.3.6.1.2.1.1.1.0", 1000000, 1) === false ? 1 : 0);'
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
}
if (-not $ready) { throw 'SNMP fixture did not answer a probe' }
[ordered]@{pid=$server.Id;persistentDirectory=$env:SNMP_PERSISTENT_DIR} | ConvertTo-Json | Set-Content "$root/regressions/$Variant-snmp-fixture.json"
