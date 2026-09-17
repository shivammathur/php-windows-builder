# PHP < 8.5 phpize flattens ADD_SOURCES directories unless obj_dir is explicit.
# https://github.com/php/php-src/issues/16843
$configPath = Get-RecursiveFilePath -Directory (Get-Location).Path -FileName 'config.w32'
$content = Get-Content -LiteralPath $configPath -Raw
$patched = [regex]::Replace(
    $content,
    '(ADD_SOURCES\(\s*configure_module_dirname\s*\+\s*"/([^"]+)"\s*,\s*"[^"]+"\s*,\s*"ice")\s*\)',
    {
        param($match)
        $objectDirectory = $match.Groups[2].Value.Replace('/', '\\')
        $match.Groups[1].Value + ', "' + $objectDirectory + '")'
    }
)
if ($patched -cne $content) {
    Set-Content -LiteralPath $configPath -Value $patched -Encoding utf8 -NoNewline
}
