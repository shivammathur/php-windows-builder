# Match PHP's sockets feature macro in uv_stdio_new's declaration and resource guard.
(Get-Content php_uv.c -Raw).Replace('defined(HAVE_SOCKET)', 'defined(HAVE_SOCKETS)') | Set-Content php_uv.c -NoNewline
