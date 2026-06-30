(Get-Content src\memcache_pool.h) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_pool.h
(Get-Content src\memcache_binary_protocol.c) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_binary_protocol.c

if (Test-Path tests\connect.inc) {
  $connect = Get-Content tests\connect.inc -Raw
  $connect = $connect -replace '\$host\s*=\s*"localhost";', '$host = getenv("MEMC_SERVER_HOST") ?: "127.0.0.1";'
  $connect = $connect -replace '\$port\s*=\s*11211;', '$port = (int) (getenv("MEMC_SERVER_PORT") ?: 11211);'
  $connect = $connect -replace '\$host2\s*=\s*"localhost";', '$host2 = getenv("MEMC_SERVER_HOST") ?: "127.0.0.1";'
  $connect = $connect -replace '\$port2\s*=\s*11212;', '$port2 = (int) (getenv("MEMC_SERVER_PORT_2") ?: 11212);'
  $connect = $connect -replace '\$domainsocket\s*=\s*''unix:///var/run/memcached/memcached.sock'';', 'unset($domainsocket);'
  Set-Content tests\connect.inc -Value $connect -NoNewline
}

if (Test-Path tests\052.phpt) {
  $test052 = Get-Content tests\052.phpt -Raw
  $test052 = $test052 -replace '\$start\s*=\s*time\(\);', '$start = microtime(true);'
  $test052 = $test052 -replace '\$end\s*=\s*time\(\);', '$end = microtime(true);'
  Set-Content tests\052.phpt -Value $test052 -NoNewline
}

if (Test-Path tests\018.phpt) {
  $test018 = Get-Content tests\018.phpt -Raw
  $test018 = $test018 -replace "include 'connect\.inc';\r?\n\r?\n", "include 'connect.inc';`n`n`$memcache = memcache_connect('127.0.0.1', `$port);`n`n"
  Set-Content tests\018.phpt -Value $test018 -NoNewline
}

if (Test-Path tests\pecl63142.phpt) {
  $pecl63142 = Get-Content tests\pecl63142.phpt -Raw
  $pecl63142 = $pecl63142 -replace '(?m)^report_memleaks=0\r?\n?', ''
  Set-Content tests\pecl63142.phpt -Value $pecl63142 -NoNewline
}
