function Install-LegacyTestXdebug {
    param([string]$Version, [string]$Root, [string]$Label)
    $failure = $null
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            Install-PhpExtension -Extension xdebug -Version $Version -Path $Root -Verbose 4>&1 |
                Tee-Object "evidence/$Label-phpmanager.txt" -Append | Write-Host
            return
        } catch {
            if ([int]$_.Exception.Response.StatusCode -notin @(502, 503, 504)) { throw }
            $failure = $_.Exception.Message
            if ($attempt -eq 0) { Start-Sleep -Seconds 10 }
        }
    }
    # Xdebug has its own upstream downloads. Keep PhpManager's exact PHP/VC/TS/arch
    # selection and installation checks when the unrelated PECL package index is down.
    $selected = & (Get-Module PhpManager) {
        param($Root, $Version)
        $php = [PhpVersionInstalled]::FromPath($Root)
        Get-XdebugExtension -PhpVersion $php -Version $Version -MinimumStability stable -MaximumStability stable
    } $Root $Version
    if (-not $selected -or $selected.PackageVersion -cne $Version -or $selected.PackageArchiveUrl -notlike 'https://xdebug.org/files/php_xdebug-*.dll') {
        throw 'PhpManager did not select the exact upstream Xdebug version'
    }
    $download = Join-Path $env:RUNNER_TEMP "xdebug-$Label.dll"
    Invoke-WebRequest $selected.PackageArchiveUrl -OutFile $download -MaximumRetryCount 2 -RetryIntervalSec 5
    @{reason='PECL index HTTP 502/503/504 after two attempts'; error=$failure;
      url=$selected.PackageArchiveUrl; version=$Version; sha256=(Get-FileHash $download -Algorithm SHA256).Hash.ToLowerInvariant();
      mode='PhpManager Xdebug selector plus local-file installation'} |
        ConvertTo-Json -Depth 4 | Set-Content "evidence/$Label-xdebug-download.json"
    Install-PhpExtension -Extension $download -Path $Root -Verbose 4>&1 |
        Tee-Object "evidence/$Label-phpmanager.txt" -Append | Write-Host
}
