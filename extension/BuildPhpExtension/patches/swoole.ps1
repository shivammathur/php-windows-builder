(Get-Content config.w32) | ForEach-Object { $_.Replace('libzstd.lib', 'libzstd_a.lib') } | Set-Content config.w32
