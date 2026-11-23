$extensions = @('*.c', '*.h', '*.cc', '*.cpp', '*.cxx', '*.hpp', '*.hxx')

$replacements = [ordered]@{
  '\bzend_exception_get_default\s*\(\s*(?:TSRMLS_C)?\s*\)' = 'zend_ce_exception'
  '\bXtOffsetOf\b'                       = 'offsetof'
  '\bZEND_RESULT_CODE\b'                 = 'zend_result'
  '\bzval_dtor\b'                        = 'zval_ptr_dtor_nogc'
  '\bzval_is_true\b'                     = 'zend_is_true'
  '\bZVAL_IS_NULL\b'                     = 'Z_ISNULL_P'
  '\bphp_hash_bin2hex\b'                 = 'zend_bin2hex'
  '\bzend_parse_parameters_throw\b'      = 'zend_parse_parameters'
  '\bzend_parse_parameters_none_throw\b' = 'zend_parse_parameters_none'
  '\bZEND_PARSE_PARAMS_THROW\b'          = '0'
  '\bZEND_AST_METHOD_REFERENCE\b'        = 'ZEND_AST_TRAIT_METHOD_REFERENCE'
  '\b_php_stream_read\b'                = 'php_stream_read'
  '\b_php_stream_write\b'               = 'php_stream_write'
  '\bEMPTY_SWITCH_DEFAULT_CASE\s*\(\s*\)' = 'default: ZEND_UNREACHABLE(); break;'
  '\b(?:ZEND_WRONG_PARAM_COUNT\s*\(\s*\)|WRONG_PARAM_COUNT\b)' = 'do { zend_wrong_param_count(); RETURN_THROWS(); } while (0)'
}
foreach ($symbol in @('Aggregate', 'ArrayAccess', 'Countable', 'Iterator', 'Serializable', 'Stringable', 'Traversable')) {
  $replacements["\bspl_ce_$symbol\b"] = "zend_ce_$($symbol.ToLower())"
}

# Leave strings, comments and compatibility macro names intact.
$literal = '"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*'''
$comment = '//[^\r\n]*|/\*[\s\S]*?\*/'
$declarations = '(?m:^[\t ]*#[\t ]*(?:define|undef|ifdef|ifndef)[\t ]+\w+)'
$skip = "(?<skip>$declarations|$literal|$comment)"

Get-ChildItem -Path . -Recurse -File -Include $extensions | ForEach-Object {
  $file = $_.FullName
  $content = Get-Content -LiteralPath $file -Raw
  if ([string]::IsNullOrEmpty($content)) { return }
  $original = $content
  $content = $content -creplace 'ext/standard/php_smart_string(?:_public)?\.h', 'Zend/zend_smart_string.h'
  $content = $content.Replace('standard/php_lcg.h', 'random/php_random.h').Replace('ext/standard/php_rand.h', 'ext/random/php_random.h')
  foreach ($old in $replacements.Keys) {
    $new = $replacements[$old]
    $content = [regex]::Replace($content, "$skip|$old", {
      param($match)
      if ($match.Groups['skip'].Success) { return $match.Value }
      return $new
    })
  }

  # Retain strlen-based lookups and numeric BOOL conversion, including nonliteral names.
  $content = [regex]::Replace($content, "$skip|\bINI_(?<type>INT|FLT|STR|BOOL)\s*\((?<name>(?>[^()`"]+|`"(?:\\.|[^`"\\])*`"|(?<depth>\()|(?<-depth>\)))*(?(depth)(?!)))\)", {
    param($match)
    if ($match.Groups['skip'].Success) { return $match.Value }
    $name = $match.Groups['name'].Value.Trim()
    switch ($match.Groups['type'].Value) {
      'INT'  { return "zend_ini_long(($name), strlen($name), false)" }
      'FLT'  { return "zend_ini_double(($name), strlen($name), false)" }
      'STR'  { return "((char *) zend_ini_string(($name), strlen($name), false))" }
      'BOOL' { return "((bool) zend_ini_long(($name), strlen($name), false))" }
    }
  })

  $content = $content -creplace '\bphp_verror\(([^,]+),\s*(?:""|params),', 'php_verror($1,'
  $content = $content.Replace('php_stream_wrapper_log_error(wrapper, options,', 'php_stream_wrapper_log_warn(wrapper, NULL, options, Generic,')
  $content = $content -creplace '\bphp_stream_filter_alloc\(([^,;]+),\s*([^,;]+),\s*(\w+)\)', 'php_stream_filter_alloc($1, $2, $3, PSFS_SEEKABLE_NEVER, PSFS_SEEKABLE_NEVER)'
  $content = $content -creplace '(php_stream_filter\s*\*\s*\w+\(const char\s*\*\w+,\s*zval\s*\*\w+,\s*)uint8_t\b', '${1}bool'
  $content = $content -creplace '(\bphp_stream_filter_ops\s+\w+\s*=\s*\{\s*\w+\s*,)(\s*\w+\s*,\s*"[^"]+"\s*,?\s*\})', '$1 NULL,$2'
  $content = $content -creplace '\bZVAL_STRING\(([^,]+),\s*PG\(unserialize_callback_func\)\)', 'ZVAL_STR_COPY($1, PG(unserialize_callback_func))'
  $content = $content.Replace('PG(unserialize_callback_func)[0]', 'ZSTR_VAL(PG(unserialize_callback_func))[0]')

  # Only adapt legacy string uses inside session-open callbacks.
  $session = "(?ms)\bPS_OPEN_FUNC\(\w+\)(?:\s|$comment)*\{(?<body>.*?)^\}"
  $content = [regex]::Replace($content, $session, {
    param($match)
    $body = $match.Groups['body'].Value
    if ($body -notmatch '(?:strlen|strstr|estrdup|estrndup|php_url_parse_ex|memcached_servers_parse)\(save_path\b|\bpath\s*=\s*save_path\s*;') { return $match.Value }
    $body = [regex]::Replace($body, "(?<keep>$literal|$comment|ZSTR_(?:VAL|LEN)\(\s*(?:save_path|session_name)\s*\))|\b(?<name>save_path|session_name)\b", {
      param($parameter)
      if ($parameter.Groups['keep'].Success) { return $parameter.Value }
      return "ZSTR_VAL($($parameter.Value))"
    })
    return $match.Value.Substring(0, $match.Groups['body'].Index - $match.Index) + $body + '}'
  })

  if ($content -cne $original) {
    Set-Content -LiteralPath $file -Value $content -Encoding utf8 -NoNewline
  }
}
