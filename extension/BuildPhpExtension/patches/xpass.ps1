Invoke-WebRequest -Uri "https://raw.githubusercontent.com/remicollet/php-xpass/refs/heads/master/config.w32" -OutFile config.w32

$configW32 = Get-Content config.w32 -Raw
$configW32 = $configW32.Replace('CHECK_HEADER_ADD_INCLUDE("crypt.h", "CLFAGS_XPASS", PHP_XPASS)', 'CHECK_HEADER_ADD_INCLUDE("crypt.h", "CFLAGS_XPASS", PHP_XPASS)')

if ($configW32 -notmatch 'HAVE_CRYPT_SM3') {
    $configW32 = $configW32.Replace(
        '        AC_DEFINE("HAVE_CRYPT_SHA512", 1, "Have sha512 hash support");',
        "        AC_DEFINE(`"HAVE_CRYPT_SHA512`", 1, `"Have sha512 hash support`");`r`n        AC_DEFINE(`"HAVE_CRYPT_SM3`", 1, `"Have SM3 hash support`");"
    )
}

Set-Content config.w32 -Value $configW32
