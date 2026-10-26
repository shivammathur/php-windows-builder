<?php

function expectLdap(mixed $actual, mixed $expected, string $label): void
{
    if ($actual !== $expected) {
        throw new RuntimeException($label . ': expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}

ob_start();
(new ReflectionExtension('ldap'))->info();
$info = ob_get_clean();
expectLdap(preg_match('/Vendor Version => 20702\b/', $info), 1, 'OpenLDAP runtime version');
expectLdap(preg_match('/SASL Support => Enabled/i', $info), 1, 'Cyrus SASL support');

$connection = ldap_connect('ldap://127.0.0.1:389');
expectLdap(ldap_set_option($connection, LDAP_OPT_PROTOCOL_VERSION, 3), true, 'Set LDAP protocol version');
expectLdap(ldap_get_option($connection, LDAP_OPT_PROTOCOL_VERSION, $version), true, 'Get LDAP protocol version');
expectLdap($version, 3, 'LDAP protocol version');
expectLdap(ldap_explode_dn('cn=Alice,ou=People,dc=example', 1), ['count' => 3, 0 => 'Alice', 1 => 'People', 2 => 'example'], 'LDAP DN parsing');
expectLdap(ldap_escape("a*(b)\\\0", '', LDAP_ESCAPE_FILTER), 'a\2a\28b\29\5c\00', 'LDAP filter escaping');
expectLdap(ldap_unbind($connection), true, 'LDAP unbind');
echo "OpenLDAP 2.7.2: version, Cyrus SASL support, protocol options, DN parsing and filter escaping checks passed\n";
