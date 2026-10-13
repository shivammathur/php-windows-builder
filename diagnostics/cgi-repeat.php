<?php
require $argv[1] . '/sapi/cgi/tests/include.inc';
$php = get_cgi_path();
if (!$php) throw new RuntimeException('Cannot discover original CGI binary');
reset_env_vars();
$results = [];
for ($iteration = 0; $iteration < 350; $iteration++) {
    foreach (['af' => '-n -a -f "wrong"', 'fa' => '-n -f "wrong" -a'] as $mode => $flags) {
        $command = "$php $flags";
        $output = shell_exec($command);
        $results[] = ['iteration' => $iteration, 'mode' => $mode, 'api' => 'shell_exec', 'output' => $output];
        ob_start();
        passthru($command, $status);
        $output = ob_get_clean();
        $results[] = ['iteration' => $iteration, 'mode' => $mode, 'api' => 'passthru', 'exit' => $status, 'output' => $output];
        // shell_exec uses the same text-mode popen/read/close path, but discards the child exit status.
        $pipe = popen($command, 'rt');
        if (!is_resource($pipe)) throw new RuntimeException('Cannot start CGI control');
        $output = stream_get_contents($pipe);
        $status = pclose($pipe);
        $results[] = ['iteration' => $iteration, 'mode' => $mode, 'api' => 'popen', 'exit' => $status, 'output' => $output];
    }
}
file_put_contents($argv[2], json_encode($results, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
$format = new NumberFormatter('en', NumberFormatter::DECIMAL);
foreach (['constant' => NAN, 'positive' => unpack('E', hex2bin('7ff8000000000000'))[1], 'negative' => unpack('E', hex2bin('fff8000000000000'))[1]] as $name => $value) {
    echo "$name ", bin2hex(pack('E', $value)), ': ', $format->format($value), "\n";
}
