(Get-Content src\memcache_pool.h) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_pool.h
(Get-Content src\memcache_binary_protocol.c) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_binary_protocol.c

if (Test-Path tests\connect.inc) {
  $connect = Get-Content tests\connect.inc -Raw
  $connect = $connect -replace '\$host\s*=\s*"localhost";', '$host = "127.0.0.1";'
  $connect = $connect -replace '\$host2\s*=\s*"localhost";', '$host2 = "127.0.0.1";'
  $connect = $connect -replace '\$nonExistingHost\s*=\s*"localhost";', '$nonExistingHost = "127.0.0.1";'
  $connect = $connect -replace '\$domainsocket\s*=\s*''unix:///var/run/memcached/memcached.sock'';', '$domainsocket = "";'
  Set-Content tests\connect.inc -Value $connect -NoNewline
}
