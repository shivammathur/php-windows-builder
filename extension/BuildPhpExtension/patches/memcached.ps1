(Get-Content php_memcached_private.h) | ForEach-Object { $_ -replace '"php_stdint.h"', '<stdint.h>' } | Set-Content php_memcached_private.h

if (Test-Path tests\config.inc) {
  Set-Content tests\config.inc.local -Encoding ASCII -Value @'
<?php
define("MEMC_SERVER_HOST", getenv("MEMC_SERVER_HOST") ?: "127.0.0.1");
define("MEMC_SERVER_PORT", (int) (getenv("MEMC_SERVER_PORT") ?: 11211));
'@
}
