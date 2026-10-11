<?php
// Run as a PostgreSQL role permitted to create disposable databases:
// php tests/npc_plugin_data_postgres_test.php /path/to/lib/postgresql.class.php [supported|old] [helper.php]
// Uses local peer authentication; never connects to an application database.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
$adapter = $argv[1] ?? '';
if (!is_file($adapter)) { throw new RuntimeException('Pass the installed CHIM SQL adapter path'); }
$mode = $argv[2] ?? 'supported';
if (!in_array($mode, ['supported', 'old'], true)) { throw new RuntimeException('Unknown test mode'); }
$admin = pg_connect('host=/var/run/postgresql dbname=postgres', PGSQL_CONNECT_FORCE_NEW);
if (!$admin) { throw new RuntimeException('Local PostgreSQL test connection failed'); }
$database = 'sharmat_pr5_test_' . bin2hex(random_bytes(6));
$identifier = pg_escape_identifier($admin, $database);
if (!pg_query($admin, "CREATE DATABASE {$identifier}")) { throw new RuntimeException('Cannot create disposable database'); }
$db = null;
$assertions = 0;
function npcAssert($condition, $message) {
    global $assertions;
    $assertions++;
    if (!$condition) { throw new RuntimeException($message); }
}
try {
    $dsn = 'host=/var/run/postgresql dbname=' . $database;
    $connection = pg_connect($dsn, PGSQL_CONNECT_FORCE_NEW);
    npcAssert(pg_dbname($connection) === $database, 'test connection targets newly created database');
    set_include_path(dirname($adapter) . PATH_SEPARATOR . get_include_path());
    require_once $adapter;
    restore_error_handler(); // Keep test failures out of the application's log.
    Logger::setCustomLog(sys_get_temp_dir() . '/' . $database . '.log');
    // Bypass the adapter constructor so its application connection is never opened.
    $reflection = new ReflectionClass('sql');
    $db = $reflection->newInstanceWithoutConstructor();
    $reflection->getProperty('link')->setValue(null, $connection);
    $reflection->getProperty('connString')->setValue($db, $dsn);
    $db->set_debug_level(0);
    $GLOBALS['db'] = $db;
    require_once ($argv[3] ?? dirname(__DIR__) . '/npc_plugin_data.php');
    $source = file_get_contents(dirname(__DIR__) . '/nsfw_data.php');
    $start = strpos($source, 'class NsfwNpcData {');
    $end = strpos($source, '// AUTO-INITIALIZATION', $start);
    npcAssert($start !== false && $end !== false, 'production NPC class located without profile initialization');
    eval(substr($source, $start, $end - $start));
    $column = $mode === 'supported' ? ", plugin_extended_data jsonb NOT NULL DEFAULT '{}'" : '';
    $db->execQuery("CREATE TABLE core_npc_master (id serial PRIMARY KEY, npc_name text NOT NULL {$column})");
    NsfwNpcData::ensureTable();
    if ($mode === 'old') {
        $db->execQuery("INSERT INTO core_npc_master(npc_name) VALUES ('Test Guard')");
        npcAssert(NsfwNpcData::save('test_guard', ['flag' => 1]), 'old-schema save works');
        npcAssert(NsfwNpcData::setKey('Test Guard', 'flag', 2), 'old-schema setKey works');
        sharmatSyncNpcPluginData();
        npcAssert(NsfwNpcData::getKey('Test Guard', 'flag') === 2, 'old schema retains authoritative plugin data');
        npcAssert((int)$db->fetchOne('SELECT count(*) AS n FROM core_npc_master')['n'] === 1, 'old schema creates no core profiles');
    } else {
        $db->execQuery('CREATE TABLE update_audit (id integer)');
        $db->execQuery('CREATE FUNCTION record_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO update_audit VALUES (NEW.id); RETURN NEW; END $$');
        $db->execQuery('CREATE TRIGGER record_update AFTER UPDATE ON core_npc_master FOR EACH ROW EXECUTE FUNCTION record_update()');
        $seed = function ($name, $data, $core = true) use ($db) {
            $name = $db->escapeLiteral($name); $data = $db->escapeLiteral(json_encode($core && $data === [] ? (object)[] : $data));
            if ($core) { $db->execQuery("INSERT INTO core_npc_master(npc_name,plugin_extended_data) VALUES ({$name},{$data}::jsonb)"); }
            else { $db->execQuery("INSERT INTO nsfw_npc_data(npc_name,extended_data) VALUES ({$name},{$data}::jsonb)"); }
        };
        $read = function ($name) use ($db) {
            $row = $db->fetchOne('SELECT plugin_extended_data AS data FROM core_npc_master WHERE npc_name=' . $db->escapeLiteral($name));
            return json_decode($row['data'], true);
        };
        $seed(" \tTest Guard\r\n", ['other' => ['keep' => true]]);
        npcAssert(NsfwNpcData::save('test_guard', ['flag' => 1, 'aiagent_nsfw_intimacy_data' => ['level' => 1]]), 'save succeeds');
        npcAssert(($read(" \tTest Guard\r\n")['sharmat']['flag'] ?? null) === 1, 'save hook matches padded core name');
        npcAssert(NsfwNpcData::save('Test Guard', ['flag' => 2]), 'partial save succeeds');
        npcAssert($read(" \tTest Guard\r\n")['sharmat']['aiagent_nsfw_intimacy_data']['level'] === 1, 'mirror includes preserved runtime keys');
        npcAssert(NsfwNpcData::setKey('TEST_GUARD', 'flag', 3), 'setKey succeeds');
        npcAssert($read(" \tTest Guard\r\n")['sharmat']['flag'] === 3, 'setKey hook refreshes copy');
        npcAssert($read(" \tTest Guard\r\n")['other'] === ['keep' => true], 'other namespace preserved');

        $seed(' River Scout ', []); $seed("\tRIVER_SCOUT\v", ['flag' => 4], false);
        sharmatSyncNpcPluginData("\r river_scout \t");
        npcAssert($read(' River Scout ')['sharmat'] === ['flag' => 4], 'both stored names and input trim before underscore/case normalization');
        $count = (int)$db->fetchOne('SELECT count(*) AS n FROM update_audit')['n'];
        sharmatSyncNpcPluginData('river_scout');
        npcAssert((int)$db->fetchOne('SELECT count(*) AS n FROM update_audit')['n'] === $count, 'unchanged copy does not write');

        $seed('Twin Guard', ['keep' => 1]); $seed(' twin_guard ', ['keep' => 2]); $seed('TWIN_GUARD', ['flag' => 5], false);
        sharmatSyncNpcPluginData('Twin Guard');
        npcAssert($read('Twin Guard') === ['keep' => 1] && $read(' twin_guard ') === ['keep' => 2], 'ambiguous core names skipped');
        $seed('Town Guard', ['keep' => 3]); $seed('Town Guard', ['flag' => 6], false); $seed(' town_guard ', ['flag' => 7], false);
        sharmatSyncNpcPluginData('town_guard');
        npcAssert($read('Town Guard') === ['keep' => 3], 'ambiguous plugin names skipped');

        $quote = "O'Brien_% Scout";
        $seed($quote, []); $seed($quote, ['flag' => 8], false);
        sharmatSyncNpcPluginData($quote);
        npcAssert($read($quote)['sharmat'] === ['flag' => 8], 'apostrophes and wildcard characters are literal data');
        $count = (int)$db->fetchOne('SELECT count(*) AS n FROM update_audit')['n'];
        sharmatSyncNpcPluginData("unknown' OR TRUE --");
        npcAssert((int)$db->fetchOne('SELECT count(*) AS n FROM update_audit')['n'] === $count, 'quoted unknown name cannot broaden update');

        $seed('Bulk Scout', ['other' => 9]); $seed('Bulk Scout', ['flag' => 10], false);
        $db->execQuery("UPDATE nsfw_npc_data SET extended_data = extended_data - 'aiagent_nsfw_intimacy_data' WHERE npc_name = 'Test Guard'");
        sharmatSyncNpcPluginData();
        npcAssert($read('Bulk Scout') === ['other' => 9, 'sharmat' => ['flag' => 10]], 'bulk synchronization copies new state');
        npcAssert(!isset($read(" \tTest Guard\r\n")['sharmat']['aiagent_nsfw_intimacy_data']), 'bulk synchronization reflects stale-state cleanup');
        npcAssert($read('Twin Guard') === ['keep' => 1] && $read('Town Guard') === ['keep' => 3], 'bulk synchronization still skips ambiguity');
        $seed('Unknown Plugin NPC', ['flag' => 11], false);
        $count = (int)$db->fetchOne('SELECT count(*) AS n FROM core_npc_master')['n'];
        sharmatSyncNpcPluginData();
        npcAssert((int)$db->fetchOne('SELECT count(*) AS n FROM core_npc_master')['n'] === $count, 'missing core NPC is never created');

        // Execute only the namespace-removal block from production; never the full reset.
        $reset = file_get_contents(dirname(__DIR__) . '/sharmat_reset.php');
        $start = strpos($reset, '            $pluginSchema =');
        $end = strpos($reset, "            \$summary['runtime_tables_created']", $start);
        npcAssert($start !== false && $end !== false, 'reset namespace block located');
        $schema = 'public'; $qSchema = '"public"';
        function sharmat_reset_exec($query) { return $GLOBALS['db']->execQuery($query); }
        eval(substr($reset, $start, $end - $start));
        npcAssert($read('Bulk Scout') === ['other' => 9], 'reset removes only SHARMAT namespace');
        npcAssert($read(" \tTest Guard\r\n") === ['other' => ['keep' => true]], 'reset preserves other plugin data');
    }
    echo "NPC plugin-data PostgreSQL tests passed ({$mode}; {$assertions} assertions).\n";
} finally {
    if ($db !== null) { $db->close(); }
    elseif (isset($connection) && $connection) { pg_close($connection); }
    if (!pg_query($admin, "DROP DATABASE {$identifier}")) { throw new RuntimeException('Could not remove disposable test database ' . $database); }
    pg_close($admin);
    $testLog = sys_get_temp_dir() . '/' . $database . '.log';
    if (is_file($testLog)) { unlink($testLog); }
}
