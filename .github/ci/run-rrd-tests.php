<?php

$testPhp = getenv('TEST_PHP_EXECUTABLE');
$testPhpArgs = preg_split('/\s+/', trim((string) getenv('TEST_PHP_ARGS')));
if (!$testPhp || !$testPhpArgs) {
    fwrite(STDERR, "The test PHP command is not configured.\n");
    exit(1);
}

$preflight = getcwd() . DIRECTORY_SEPARATOR . 'rrd-extension-load-check.php';
file_put_contents(
    $preflight,
    '<?php exit(extension_loaded("rrd") ? 0 : 1);'
);
$command = implode(' ', array_map('escapeshellarg', array_merge(
    [$testPhp],
    $testPhpArgs,
    [$preflight]
)));
$pipes = [];
$process = proc_open(
    $command,
    [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    null,
    ['bypass_shell' => true]
);
if (!is_resource($process)) {
    unlink($preflight);
    fwrite(STDERR, "Failed to start the test PHP process.\n");
    exit(1);
}

$output = stream_get_contents($pipes[1]);
$errors = stream_get_contents($pipes[2]);
fclose($pipes[1]);
fclose($pipes[2]);
$exitCode = proc_close($process);
unlink($preflight);
if ($exitCode !== 0) {
    fwrite(STDERR, $output . $errors . "The rrd extension is not loaded by the test PHP process.\n");
    exit(1);
}

file_put_contents(
    getcwd() . DIRECTORY_SEPARATOR . 'tests' . DIRECTORY_SEPARATOR . 'rrdtool-bin.inc',
    <<<'PHP'
<?php
$rrdtool_bin = "no";
?>
PHP
);

require getcwd() . DIRECTORY_SEPARATOR . 'run-tests.php';
