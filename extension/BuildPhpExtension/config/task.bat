
call phpize 2>&1
call configure --with-php-build="..\deps" OPTIONS --with-mp="disable" 2>&1
nmake NMAKE_FLAGS 2>&1
exit %errorlevel%
