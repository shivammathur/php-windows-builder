<?php
// Compatibility fixes for the extracted test pack; never modify expected output.
$tests = $argv[1];
$runner = $tests . '/run-tests.php';
$code = file_get_contents($runner);
$lookup = 'in_array(strtolower(str_replace("-", "_", $req_ext)), array_map("strtolower", str_replace(["Zend OPcache", "-"], ["opcache", "_"], $loaded)), true)';
$code = str_replace(
    ['in_array($req_ext, $loaded, true)', 'in_array($req_ext, $loaded)'],
    $lookup,
    $code
);
if (strpos($code, '// Allow an explicit PHPT OPcache opt-in.') === false) {
    $code = preg_replace_callback(
        '/^([ \t]*)((?:\$ini_settings = )?settings2params\(\$ini_settings\);)$/m',
        function ($match) {
            return $match[1] . <<<'PHP'
// Allow an explicit PHPT OPcache opt-in. The lane defaults remain disabled.
if (!isset($ini_settings['opcache.enable']) &&
    isset($ini_settings['opcache.enable_cli']) &&
    in_array(strtolower((string) $ini_settings['opcache.enable_cli']), ['1', 'on', 'true', 'yes'], true)) {
    $ini_settings['opcache.enable'] = '1';
}
PHP
                . "\n" . $match[0];
        },
        $code,
        -1,
        $count
    );
    if ($count !== 1) {
        throw new RuntimeException('Unrecognized PHPT INI handling.');
    }
}
// Older JUnit reporters lose redirected outcomes or recurse while exporting.
$start = strpos($code, 'function junit_mark_test_as(');
$end = $start === false ? false : strpos($code, "\nfunction junit_suite_record(", $start);
if ($end !== false && strpos($code, 'function junit_path_to_classname($file_name)') !== false) {
    $function = substr($code, $start, $end - $start);
    if (strpos($function, "\n\tglobal \$JUNIT;") !== false &&
        strpos($function, 'junit_init_suite(') === false) {
        $old = "\t" . '$suite = junit_get_suitename_for($file_name);';
        if (substr_count($function, $old) !== 1 ||
            substr_count($function, '$JUNIT[\'files\'][$file_name]') !== 7) {
            throw new RuntimeException('Unrecognized legacy JUnit reporter.');
        }
        $function = str_replace($old, <<<'PHP'
	global $IN_REDIRECT;
	$timer_file = $file_name;
	if (is_array($IN_REDIRECT)) {
		$file_name = $IN_REDIRECT['dir'] . DIRECTORY_SEPARATOR . basename($file_name);
	}
	$suite = junit_get_suitename_for($file_name);
	junit_init_suite($suite);
	// Register completed outcomes, not timer placeholders. Preserve repetitions.
	$report_key = $file_name . '#' . $JUNIT['test_total'];
	$JUNIT['suites'][$suite]['files'][$report_key] = $report_key;
PHP
            , $function);
        $function = str_replace(
            ['junit_get_timer($file_name)', '$JUNIT[\'files\'][$file_name]'],
            ['junit_get_timer($timer_file)', '$JUNIT[\'files\'][$report_key]'],
            $function
        );
        $code = substr_replace($code, $function, $start, $end - $start);
        $registration = "\t\t" . '$JUNIT[\'suites\'][$suite][\'files\'][$file_name] = $file_name;' . "\n";
        if (substr_count($code, $registration) !== 1) {
            throw new RuntimeException('Unrecognized legacy JUnit timer.');
        }
        $code = str_replace($registration, '', $code);
    }
}
file_put_contents($runner, $code);

// Tidy's newline option takes LF/CRLF/CR, not a literal newline character.
$tidy = $tests . '/ext/tidy/tests/018.phpt';
if (is_file($tidy)) {
    $code = file_get_contents($tidy);
    file_put_contents($tidy, str_replace("'newline' => \"\\n\"", "'newline' => \"LF\"", $code));
}

// The older COM subprocess test loads the module twice with an extension INI.
$com = $tests . '/ext/com_dotnet/tests/bug77578.phpt';
if (is_file($com)) {
    $code = file_get_contents($com);
    if (strpos($code, '-d extension=com_dotnet ') !== false) {
        $code = str_replace('-d extension=com_dotnet ', '', $code);
        $code = str_replace("new COM('WbemScripting.SWbemLocator');",
            "if (!extension_loaded('com_dotnet')) dl('com_dotnet'); new COM('WbemScripting.SWbemLocator');", $code);
        file_put_contents($com, $code);
    }
}

// Legacy SNI fixtures expired in April 2026. Renew the test chain, keeping
// hostname and certificate verification enabled and the existing leaf keys.
$ssl = $tests . '/ext/openssl/tests';
if (is_file($ssl . '/sni_server_cs.pem')) {
    $cert = openssl_x509_parse(file_get_contents($ssl . '/sni_server_cs.pem'));
    if ($cert === false) {
        throw new RuntimeException('Cannot read the SNI fixture certificate.');
    }
    if ($cert['validTo_time_t'] < time() + 86400) {
        $config = tempnam(sys_get_temp_dir(), 'php-sni-');
        try {
            $baseConfig = "[req]\ndistinguished_name=dn\n[dn]\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n";
            file_put_contents($config, $baseConfig);
            $options = ['config' => $config, 'digest_alg' => 'sha256', 'private_key_bits' => 2048];
            $caKey = openssl_pkey_new($options);
            $caRequest = openssl_csr_new(['commonName' => 'PHP SNI test CA'], $caKey, $options);
            $ca = openssl_csr_sign($caRequest, null, $caKey, 365, $options + ['x509_extensions' => 'ca'], 1);
            if (!$ca || !openssl_x509_export($ca, $caPem)) {
                throw new RuntimeException('Cannot create the SNI fixture CA.');
            }
            file_put_contents($ssl . '/sni_server_ca.pem', $caPem);
            foreach (['cs', 'uk', 'us'] as $index => $name) {
                file_put_contents($config, $baseConfig . "[leaf]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:$name.php.net\n");
                $keyPem = file_get_contents($ssl . "/sni_server_{$name}_key.pem");
                $key = openssl_pkey_get_private($keyPem);
                $request = openssl_csr_new(['commonName' => "$name.php.net"], $key, $options);
                $leaf = openssl_csr_sign($request, $ca, $caKey, 365, $options + ['x509_extensions' => 'leaf'], $index + 2);
                if (!$leaf || !openssl_x509_export($leaf, $pem)) {
                    throw new RuntimeException('Cannot renew an SNI fixture certificate.');
                }
                file_put_contents($ssl . "/sni_server_{$name}_cert.pem", $pem);
                file_put_contents($ssl . "/sni_server_{$name}.pem", $keyPem . $pem);
            }
        } finally {
            unlink($config);
        }
    }
}

// Some legacy test packs reference the upstream Firebird payload server without
// shipping it. Supply the helper only when absent; preserve each original test.
$firebird = $tests . '/ext/pdo_firebird/tests';
foreach (['payload_server.inc', 'payload_server.php'] as $helper) {
    if (is_dir($firebird) && !is_file($firebird . '/' . $helper)) {
        copy(__DIR__ . '/firebird/' . $helper, $firebird . '/' . $helper);
    }
}
$testDb = $firebird . '/testdb.inc';
if (is_file($testDb)) {
    $code = file_get_contents($testDb);
    $code = str_replace("\$user = 'SYSDBA';", "\$user = getenv('PDO_FIREBIRD_TEST_USER') ?: 'SYSDBA';", $code);
    $code = str_replace("\$password = 'masterkey';", "\$password = getenv('PDO_FIREBIRD_TEST_PASS') ?: 'masterkey';", $code);
    file_put_contents($testDb, $code);
}
$payloadServer = $firebird . '/payload_server.php';
if (is_file($payloadServer)) {
    $code = file_get_contents($payloadServer);
    file_put_contents($payloadServer, str_replace('tcp://localhost:0', 'tcp://127.0.0.1:0', $code));
}

// These two older TLS fixtures also expired. Preserve their names, keys, SANs
// and unrestricted certificate purposes; leave deliberately invalid fixtures.
foreach (['bug69215-ca.pem', 'san-ca.pem'] as $fixture) {
    $path = $ssl . '/' . $fixture;
    if (!is_file($path)) continue;
    $old = openssl_x509_parse(file_get_contents($path));
    if (!$old) throw new RuntimeException('Cannot read legacy TLS fixture.');
    if ($old['validTo_time_t'] >= time() + 86400) continue;
    $config = tempnam(sys_get_temp_dir(), 'php-tls-');
    try {
        $san = $fixture === 'san-ca.pem';
        file_put_contents($config, "[req]\ndistinguished_name=dn\n[dn]\n[cert]\n" .
            ($san ? "subjectAltName=DNS:example.org,DNS:www.example.org,DNS:test.example.org\n" :
                "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n"));
        $options = ['config' => $config, 'digest_alg' => 'sha256', 'private_key_bits' => 2048];
        $keyPem = $san ? file_get_contents($ssl . '/san-cert.pem') : null;
        $key = $san ? openssl_pkey_get_private($keyPem) : openssl_pkey_new($options);
        $request = openssl_csr_new($old['subject'], $key, $options);
        $ca = openssl_csr_sign($request, null, $key, 365, $options + ['x509_extensions' => 'cert'], 1);
        if (!$ca || !openssl_x509_export($ca, $caPem)) throw new RuntimeException('Cannot renew TLS fixture CA.');
        file_put_contents($path, $caPem);
        if ($san) {
            if (!openssl_pkey_export($key, $keyPem, null, $options)) throw new RuntimeException('Cannot export SAN fixture key.');
            file_put_contents($ssl . '/san-cert.pem', $keyPem . $caPem);
        } else {
            foreach (['server', 'client'] as $i => $name) {
                $path = $ssl . "/bug69215-$name.pem";
                $pem = file_get_contents($path);
                $leafKey = openssl_pkey_get_private($pem, 'elephpant');
                preg_match('/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/s', $pem, $match);
                $subject = openssl_x509_parse($match[0])['subject'];
                $request = openssl_csr_new($subject, $leafKey, $options);
                $leaf = openssl_csr_sign($request, $ca, $key, 365, $options, $i + 2);
                if (!$leaf || !openssl_x509_export($leaf, $certPem)) throw new RuntimeException('Cannot renew mutual TLS fixture.');
                if (!openssl_pkey_export($leafKey, $keyPem, 'elephpant', $options)) throw new RuntimeException('Cannot export mutual TLS fixture key.');
                file_put_contents($path, $keyPem . $certPem);
            }
        }
    } finally {
        unlink($config);
    }
}

// Newer backported tests call the HTTP capability check without an address.
$http = $tests . '/ext/standard/tests/http/server.inc';
if (is_file($http)) {
    $code = file_get_contents($http);
    $code = str_replace('function http_server_skipif($socket_string)',
        "function http_server_skipif(\$socket_string = 'tcp://localhost:0')", $code);
    file_put_contents($http, $code);
}
