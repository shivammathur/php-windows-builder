(Get-Content config.w32) | ForEach-Object { $_.Replace('>= 80600', '>= 80700').Replace('< 8.6.0', '< 8.7.0') } | Set-Content config.w32
(Get-Content config.m4) | ForEach-Object { $_.Replace('-ge "80600"', '-ge "80700"').Replace('< 8.6.0', '< 8.7.0') } | Set-Content config.m4
(Get-Content src\profiler\profiler.c) | ForEach-Object { $_.Replace('ZSTR_INIT_LITERAL(tmp_name, false)', 'zend_string_init(tmp_name, strlen(tmp_name), false)') } | Set-Content src\profiler\profiler.c

$content = Get-Content src\base\base.c -Raw
if (!$content.Contains('zend_string_copy(zdata->func->internal_function.arg_info[i].name)')) {
    $content = $content -replace '(?m)^[\t ]*fse->var\[i\].name = zend_string_init\(\s*(zdata->func->internal_function.arg_info\[i\].name),\s*strlen\(\1\),\s*0\s*\);', @'
#if PHP_VERSION_ID >= 80600
			fse->var[i].name = zend_string_copy($1);
#else
$0
#endif
'@
    Set-Content src\base\base.c $content -NoNewline
}
