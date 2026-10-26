<?php

function expectValue(mixed $actual, mixed $expected, string $label): void
{
    if ($actual !== $expected) {
        throw new RuntimeException($label . ': expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}

$sourceId = '2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76';

foreach (['SQLite3', 'PDO_SQLite'] as $api) {
    $db = $api === 'SQLite3' ? new SQLite3(':memory:') : new PDO('sqlite::memory:');
    if ($db instanceof SQLite3) {
        $db->enableExceptions(true);
        $scalar = fn(string $sql): mixed => $db->querySingle($sql);
    } else {
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $scalar = fn(string $sql): mixed => $db->query($sql)->fetchColumn();
    }

    expectValue($scalar('SELECT sqlite_version()'), '3.54.1', "$api version");
    expectValue($scalar('SELECT sqlite_source_id()'), $sourceId, "$api source ID");
    foreach (['ENABLE_MATH_FUNCTIONS', 'ENABLE_PERCENTILE', 'ENABLE_RTREE', 'ENABLE_DBSTAT_VTAB'] as $option) {
        expectValue((int) $scalar("SELECT sqlite_compileoption_used('$option')"), 1, "$api $option");
    }

    expectValue((float) $scalar('SELECT sqrt(81)'), 9.0, "$api sqrt");
    expectValue((float) $scalar('SELECT pow(2, 10)'), 1024.0, "$api pow");
    expectValue((float) $scalar('SELECT log(100)'), 2.0, "$api log");
    expectValue($scalar('SELECT sqrt(-1)'), null, "$api math domain error");
    $values = 'WITH v(x) AS (VALUES (1), (2), (3), (4), (NULL)) SELECT ';
    foreach (['median(x)' => 2.5, 'percentile(x, 50)' => 2.5, 'percentile_cont(x, 0.5)' => 2.5, 'percentile_disc(x, 0.5)' => 2.0] as $expression => $expected) {
        expectValue((float) $scalar($values . $expression . ' FROM v'), $expected, "$api $expression");
    }

    $db->exec('CREATE VIRTUAL TABLE spatial USING rtree(id, min_x, max_x, min_y, max_y)');
    $db->exec('INSERT INTO spatial VALUES (1, 0, 10, 0, 10), (2, 20, 30, 20, 30)');
    expectValue((int) $scalar('SELECT count(*) FROM spatial WHERE min_x <= 5 AND max_x >= 5 AND min_y <= 5 AND max_y >= 5'), 1, "$api spatial query");
    $db->exec('BEGIN');
    $db->exec('DELETE FROM spatial');
    $db->exec('ROLLBACK');
    expectValue((int) $scalar('SELECT count(*) FROM spatial'), 2, "$api spatial rollback");
    expectValue($scalar("SELECT rtreecheck('spatial')"), 'ok', "$api R-tree integrity");

    $db->exec('CREATE TABLE payload(id INTEGER PRIMARY KEY, value TEXT)');
    $db->exec("INSERT INTO payload(value) VALUES ('sqlite feature validation')");
    expectValue((int) $scalar("SELECT count(*) > 0 FROM dbstat WHERE name = 'payload' AND pgsize > 0"), 1, "$api DBSTAT");
    expectValue((int) $scalar("SELECT sum(ncell) FROM dbstat WHERE name = 'payload'"), 1, "$api DBSTAT cells");

    foreach (['fts3', 'fts4', 'fts5'] as $fts) {
        $db->exec("CREATE VIRTUAL TABLE search_$fts USING $fts(content)");
        $db->exec("INSERT INTO search_$fts VALUES ('sqlite feature validation')");
        expectValue((int) $scalar("SELECT count(*) FROM search_$fts WHERE search_$fts MATCH 'feature'"), 1, "$api $fts");
    }
    expectValue((int) $scalar("SELECT json_extract('{\"answer\":42}', '$.answer')"), 42, "$api JSON");
    expectValue($scalar('PRAGMA integrity_check'), 'ok', "$api database integrity");
    echo "$api: SQLite 3.54.1 math, percentile, RTREE, DBSTAT, FTS and JSON checks passed\n";
}
