(Get-Content imagick.c) | ForEach-Object { $_ -replace 'php_strtolower', 'zend_str_tolower' } | Set-Content imagick.c