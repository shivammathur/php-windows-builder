# Use the static zstd library shipped in the PHP SDK dependencies.
(Get-Content config.w32) | ForEach-Object { $_.Replace('libzstd.lib', 'libzstd_a.lib') } | Set-Content config.w32

# Enable C++20 for the designated initializers used with PHP 8.5.
(Get-Content config.w32) | ForEach-Object { $_.Replace('"/D SW_USE_POLL=1"', '"/D SW_USE_POLL=1 /std:c++20"') } | Set-Content config.w32

# Use PHP's stat structure on Windows NTS while retaining virtual paths on TS.
$path = 'thirdparty\php\streams\plain_wrapper.c'
$replacement = @'
$1#ifdef ZTS
        return VCWD_LSTAT(url, &ssb->sb);
#else
        return php_sys_lstat(url, &ssb->sb);
#endif
'@
(Get-Content $path -Raw) -replace '(#ifdef PHP_WIN32\s+if \(flags & PHP_STREAM_URL_STAT_LINK\) \{\r?\n)        return VCWD_LSTAT\(url, &ssb->sb\);', $replacement | Set-Content $path -NoNewline

# Resolve the precise clock at runtime to retain PHP 8.2's Windows 7 target.
$replacement = @'
    static const auto precise_time = reinterpret_cast<void (WINAPI *)(LPFILETIME)>(
        GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetSystemTimePreciseAsFileTime"));
    if (precise_time) {
        precise_time(&ft);
    } else {
        GetSystemTimeAsFileTime(&ft);
    }
'@
(Get-Content src\os\win32.cc -Raw).Replace('    GetSystemTimePreciseAsFileTime(&ft);', $replacement) | Set-Content src\os\win32.cc -NoNewline

# Avoid empty variadic arguments in ssl_error with the VS16 preprocessor.
(Get-Content src\protocol\ssl.cc) | ForEach-Object { $_ -replace 'ssl_error\(("[^"%]*")\);', 'ssl_error("%s", $1);' } | Set-Content src\protocol\ssl.cc

# Load Zend portability macros before PHP 8.5's Windows I/O headers.
$replacement = '${1}#include "Zend/zend_portability.h"' + "`n" + '${2}'
(Get-Content src\coroutine\iocp.cc -Raw) -replace '(#endif\r?\n)(#include "win32/ioutil.h")', $replacement | Set-Content src\coroutine\iocp.cc -NoNewline
