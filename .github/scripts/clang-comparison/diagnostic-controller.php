<?php
register_shutdown_function(static function (): void {
    $socket = $GLOBALS['workerSock'] ?? null;
    file_put_contents(getenv('VALIDATION_CONTROLLER_DIAGNOSTICS') . '/shutdown-' . getmypid() . '.json', json_encode([
        'pid' => getmypid(),
        'worker' => getenv('TEST_PHP_WORKER'),
        'last_error' => error_get_last(),
        'memory_peak' => memory_get_peak_usage(true),
        'socket' => is_resource($socket) ? stream_get_meta_data($socket) : null,
    ], JSON_PRETTY_PRINT));
});
