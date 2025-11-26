(Get-Content config.w32) | ForEach-Object { $_ -replace '80500', '80600' } | Set-Content config.w32
(Get-Content src/lib/compat.c) | ForEach-Object { $_.Replace('url_encode)', 'false, url_encode)') } | Set-Content src/lib/compat.c
