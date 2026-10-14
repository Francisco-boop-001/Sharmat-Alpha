<?php
// CLI-only disposable database test. Never connects to an application database.
if (PHP_SAPI !== 'cli') { exit; }
$root = $argv[1] ?? dirname(__DIR__);
$admin = pg_connect('host=/var/run/postgresql dbname=postgres');
$name = 'sharmat_fertility_test_' . bin2hex(random_bytes(5));
pg_query($admin, 'CREATE DATABASE ' . pg_escape_identifier($admin, $name));
$conn = pg_connect('host=/var/run/postgresql dbname=' . $name, PGSQL_CONNECT_FORCE_NEW);
function check($ok, $message) { $GLOBALS['checks']++; if (!$ok) throw new RuntimeException($message); }
$checks = 0;
class FixtureDb {
    function __construct(public $conn) {}
    function escape($s) { return pg_escape_string($this->conn, $s); }
    function execQuery($q) { return pg_query($this->conn, $q) ?: throw new RuntimeException(pg_last_error($this->conn)); }
    function fetchOne($q) { return pg_fetch_assoc($this->execQuery($q)) ?: []; }
}
class FixtureTerminated extends Exception {}
function terminate() { throw new FixtureTerminated(); }
function logEvent($event) {}
function nsfwIsNarratorName($name) { return strtolower(trim($name)) === 'the narrator'; }
class NpcMaster { function getByName($name) { return []; } }
function observe($payload) {
    $GLOBALS['gameRequest'] = ['fertility_notification', 0, 1000, $payload];
    try { processInfoFertility(); } catch (FixtureTerminated $e) {}
}
try {
    $GLOBALS['db'] = new FixtureDb($conn);
    require $root . '/npc_plugin_data.php';
    $source = file_get_contents($root . '/nsfw_data.php');
    $start = strpos($source, 'class NsfwNpcData {');
    $end = strpos($source, '// AUTO-INITIALIZATION', $start);
    eval(substr($source, $start, $end - $start));
    $source = file_get_contents($root . '/common.php');
    $start = strpos($source, 'function processInfoFertility()');
    $end = strpos($source, "\nfunction ", $start + 1);
    eval(substr($source, $start, $end - $start));
    $GLOBALS['HERIKA_NAME'] = 'The Narrator';
    $GLOBALS['PLAYER_NAME'] = 'Player';
    NsfwNpcData::save('Test Mother', ['sex_speech_style'=>'custom', 'profile_note'=>'keep']);
    observe('Test Mother@pregnant@5@Partner');
    $pregnant = NsfwNpcData::get('Test Mother');
    check(!empty($pregnant['fertility_is_pregnant']), 'payload actor must receive pregnancy, not routing actor');
    check(NsfwNpcData::get('The Narrator') === [], 'narrator must have no fertility record');
    foreach (['menses','follicular','ovulation','pms'] as $phase) {
        observe('Test Mother@conceived@Partner');
        observe('Test Mother@pregnant@5@Partner');
        observe('Test Mother@cycle@' . $phase);
        $state = NsfwNpcData::get('Test Mother');
        check($state['fertility_is_pregnant'] === false && $state['fertility_progress'] === 0, $phase . ' clears pregnancy');
        check(!isset($state['fertility_father']) && !isset($state['fertility_conceived_ts']), $phase . ' clears stale pregnancy context');
        check($state['sex_speech_style'] === 'custom', 'observation preserves profile style');
        observe('Test Mother@pregnant@5@Partner');
        check(NsfwNpcData::get('Test Mother')['fertility_is_pregnant'] === true, 'rapid status reversal must not be throttled');
    }
    observe('Test Mother@cleared');
    NsfwNpcData::save('Test Mother', $pregnant + ['edited'=>'yes']);
    check(NsfwNpcData::get('Test Mother')['fertility_is_pregnant'] === false, 'stale whole-profile save must not resurrect pregnancy');
    check(!isset(NsfwNpcData::get('Test Mother')['fertility_father']), 'stale father must not return');
    observe('Test Mother@pregnant@2@');
    check(NsfwNpcData::get('Test Mother')['fertility_father'] === '', 'unknown father must not default to player');
    observe('Test Mother@recovery@2');
    check(NsfwNpcData::get('Test Mother')['fertility_is_pregnant'] === false, 'recovery clears pregnancy');
    NsfwNpcData::save('Test Mother', ['sex_speech_style'=>'edited']);
    check(NsfwNpcData::get('Test Mother')['fertility_recovery_day'] === 2, 'partial profile save preserves current fertility');
    observe('Test Mother@cycle@follicular');
    check(!isset(NsfwNpcData::get('Test Mother')['fertility_recovery_day']), 'normal cycle clears recovery');
    check(NsfwNpcData::get('Test Mother')['sex_speech_style'] === 'edited', 'fertility writer preserves newest profile');
    echo "fertility_state_postgres_test: {$checks} checks passed\n";
} finally {
    pg_close($conn);
    pg_query($admin, 'DROP DATABASE ' . pg_escape_identifier($admin, $name));
    pg_close($admin);
}
