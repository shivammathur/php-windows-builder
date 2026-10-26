<?php
$expected = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
$checked = [];
foreach ($expected as $name => $value) {
    // These two parser-internal tokens are not exposed by ext/tokenizer.
    if ($name === 'T_ERROR' || $name === 'T_NOELSE') {
        continue;
    }
    if (!defined($name) || constant($name) !== $value) {
        throw new RuntimeException("Runtime token mismatch: $name");
    }
    $checked[$name] = constant($name);
}
$tokens = token_get_all('<?php __LINE__;');
if ($tokens[1][0] !== $expected['T_LINE'] || eval("\nreturn __LINE__;") !== 2) {
    throw new RuntimeException('__LINE__ regression');
}
try {
    eval('function {');
    throw new RuntimeException('Invalid PHP syntax was accepted');
} catch (ParseError $error) {
    // Also exercise the generated parser's error path.
}
if (json_decode('{"value":42}', true, 512, JSON_THROW_ON_ERROR)['value'] !== 42) {
    throw new RuntimeException('JSON parser regression');
}
if (parse_ini_string('answer=42')['answer'] !== '42') {
    throw new RuntimeException('INI parser regression');
}
echo json_encode([
    'version' => PHP_VERSION,
    'bits' => PHP_INT_SIZE * 8,
    'zts' => (bool) PHP_ZTS,
    'tokens' => $checked,
    'line_regression' => 'passed',
    'syntax_error' => 'passed',
    'json_parser' => 'passed',
    'ini_parser' => 'passed',
], JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR), "\n";
