<?php
require $argv[1] . '/sapi/cgi/tests/include.inc';
$php = get_cgi_path();
if (!$php) throw new RuntimeException('Missing CGI binary');
reset_env_vars();
$log = fopen($argv[2], 'wb');
for ($iteration = 0; $iteration < 1000; $iteration++) {
    foreach (['af' => '-n -a -f "wrong"', 'fa' => '-n -f "wrong" -a'] as $mode => $flags) {
        foreach (['shell_exec', 'popen'] as $api) {
            $start = microtime(true);
            $exit = null;
            if ($api === 'shell_exec') {
                $output = shell_exec("$php $flags");
            } else {
                $pipe = popen("$php $flags", 'r');
                if (!$pipe) throw new RuntimeException('Cannot start CGI child');
                $output = stream_get_contents($pipe);
                $exit = pclose($pipe);
            }
            fwrite($log, json_encode(['pid' => getmypid(), 'iteration' => $iteration, 'mode' => $mode,
                'api' => $api, 'start' => $start, 'end' => microtime(true), 'output' => $output,
                'exit' => $exit], JSON_THROW_ON_ERROR) . "\n");
            fflush($log);
        }
    }
}
fclose($log);
