<?php
// Usage: php tests/drunk_animation_bridge_test.php /path/to/CHIM/lib/scriptproxy_papyrus.php /path/to/original-config.json
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once dirname(__DIR__) . '/drunk_animation_bridge.php';
require_once $argv[1];

$checks = 0;
function drunkCheck($ok, $label) {
    global $checks;
    $checks++;
    if (!$ok) { throw new RuntimeException($label); }
}
class DrunkMockDatabase {
    public $rows = [];
    public $fail = false;
    public function insert($table, $row) {
        if ($this->fail) { throw new RuntimeException('mock queue unavailable'); }
        drunkCheck($table === 'responselog', 'writes only to the mocked command queue');
        $this->rows[] = $row;
    }
}
$GLOBALS['db'] = $db = new DrunkMockDatabase();
$commands = new SkyrimCommandBuilder();
$file = dirname(__DIR__) . '/mod/meshes/actors/character/animations/OpenAnimationReplacer/Drunk animations/Drunk animations/config.json';
$config = json_decode(file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
$original = json_decode(file_get_contents($argv[2]), true, 512, JSON_THROW_ON_ERROR);
$withoutBridge = $config;
$bridge = array_pop($withoutBridge['conditions'][0]['Conditions']);
drunkCheck($withoutBridge === $original, 'all original conditions and priority are preserved exactly');
drunkCheck($config['priority'] === 6002107, 'no animation priority escalation');

// A small evaluator for this pack's condition vocabulary, not an OAR engine test.
function drunkCondition($condition, $av, $active = []) {
    $kind = $condition['condition'];
    if ($kind === 'OR' || $kind === 'AND') {
        $values = array_map(fn($c) => drunkCondition($c, $av, $active), $condition['Conditions']);
        return $kind === 'OR' ? in_array(true, $values, true) : !in_array(false, $values, true);
    }
    if ($kind === 'CompareValues') {
        $value = function ($v) use ($av) {
            if (isset($v['actorValue'])) {
                drunkCheck($v['actorValueType'] === 'Value', 'uses current value, not percentage or base value');
                return $av[$v['actorValue']] ?? 0;
            }
            return $v['value'];
        };
        $a = $value($condition['Value A']); $b = $value($condition['Value B']);
        switch ($condition['Comparison']) {
            case '==': return $a == $b;
            case '>=': return $a >= $b;
            case '<=': return $a <= $b;
            default: throw new RuntimeException('Unsupported mock comparison');
        }
    }
    if (!in_array($kind, ['HasMagicEffect', 'HasSpell', 'IsCurrentPackage', 'IsInFaction'], true)) {
        throw new RuntimeException('Unsupported mock condition: ' . $kind);
    }
    return in_array(json_encode($condition), $active, true);
}
function drunkLeaves($c) {
    if (isset($c['Conditions'])) {
        $result = [];
        foreach ($c['Conditions'] as $child) { $result = array_merge($result, drunkLeaves($child)); }
        return $result;
    }
    return [$c];
}
function drunkDeliveredValue($row, $refid) {
    $prefix = 'rolecommand|ScriptProxy@';
    drunkCheck(strpos($row['action'], $prefix) === 0, 'real CHIM builder emits ScriptProxy command');
    $cmd = json_decode(substr($row['action'], strlen($prefix)), true, 512, JSON_THROW_ON_ERROR);
    drunkCheck($cmd['cmdID'] === 11 && $cmd['targetObjectFormId'] === $refid
        && $cmd['asValueName'] === 'Variable10', 'command targets only the intended actor and value');
    return $cmd['afNewValue'];
}

// Full mocked path: production bridge -> real CHIM serializer -> fake queue -> OAR predicate.
foreach ([false, true] as $enabled) {
    foreach ([false, true] as $scene) {
        for ($stage = 0; $stage <= 10; $stage++) {
            $state = ['aiagent_nsfw_drunk_av' => 8]; $db->rows = [];
            aiagentNsfwSyncDrunkAnimation('0x000A2C94', $stage, $enabled, $scene, $state, $commands);
            drunkCheck(count($db->rows) === 1, 'active or previously active actors receive one update');
            $value = drunkDeliveredValue($db->rows[0], '0x000A2C94');
            $expected = $enabled && !$scene && $stage >= 5;
            drunkCheck(drunkCondition($config['conditions'][0], [77 => $value]) === $expected,
                "stage {$stage}, enabled={$enabled}, scene={$scene}");
            drunkCheck(($state['aiagent_nsfw_drunk_av'] ?? 0) === ($expected ? $stage : 0), 'state follows queued target');
        }
    }
}
// Every original effect/spell/package/faction must still work with SHARMAT off.
$legacy = 0;
foreach (drunkLeaves($original['conditions'][0]) as $leaf) {
    if ($leaf['condition'] === 'CompareValues') { continue; }
    $active = [json_encode($leaf)];
    drunkCheck(drunkCondition($original['conditions'][0], [], $active), 'original trigger is independently valid');
    drunkCheck(drunkCondition($config['conditions'][0], [77 => 0], $active), 'original trigger survives SHARMAT reset');
    $legacy++;
}
foreach ([-1, 0, 1, 4, 11, 42] as $value) {
    drunkCheck(!drunkCondition($config['conditions'][0], [77 => $value]), 'unrelated/out-of-range values do not activate');
}
drunkCheck(!drunkCondition($config['conditions'][0], [76 => 8, 95 => 8]), 'skooma/other actor values cannot activate the bridge');

$state = ['aiagent_nsfw_drunk_av' => 7]; $db->rows = [];
$changed = aiagentNsfwSyncDrunkAnimation('000A2C94', 7, true, false, $state, $commands);
drunkCheck(!$changed && count($db->rows) === 1, 'same stage reasserts after save load without suppressing physics');
drunkCheck(drunkDeliveredValue($db->rows[0], '0x000A2C94') === 7, 'reassertion restores missing game-side value');

$state = []; $db->rows = [];
aiagentNsfwSyncDrunkAnimation('000A2C94', 0, true, false, $state, $commands);
drunkCheck(!$db->rows, 'never-drunk actor is not modified');
foreach (['', '0', '0x0', '0x0x000A2C94', 'not-an-id', '123456789'] as $refid) {
    $state = ['aiagent_nsfw_drunk_av' => 7];
    aiagentNsfwSyncDrunkAnimation($refid, 0, false, false, $state, $commands);
    drunkCheck(!$db->rows && $state['aiagent_nsfw_drunk_av'] === 7, 'invalid actor keeps its retry marker without emitting a command');
}
$db->fail = true; $state = ['aiagent_nsfw_drunk_av' => 7];
try { aiagentNsfwSyncDrunkAnimation('000A2C94', 0, false, false, $state, $commands); }
catch (RuntimeException $e) { drunkCheck($e->getMessage() === 'mock queue unavailable', 'queue failure surfaced'); }
drunkCheck($state['aiagent_nsfw_drunk_av'] === 7, 'queue exception does not discard reset marker');
$db->fail = false;
$alice = []; $bob = []; $db->rows = [];
aiagentNsfwSyncDrunkAnimation('000A2C94', 6, true, false, $alice, $commands);
aiagentNsfwSyncDrunkAnimation('000A2C95', 8, true, true, $bob, $commands);
drunkCheck(count($db->rows) === 1 && !$bob && $alice['aiagent_nsfw_drunk_av'] === 6, 'actor states stay independent');

// Guards against dropping the game reset marker before context synchronization.
$common = file_get_contents(dirname(__DIR__) . '/common.php');
preg_match('/\$drunkRuntimeKeys = \[(.*?)\];/s', $common, $match);
drunkCheck(isset($match[1]) && strpos($match[1], 'aiagent_nsfw_drunk_av') === false, 'rollback cleanup retains reset marker');
echo "Drunk animation mock tests passed ({$checks} assertions; {$legacy} original triggers preserved).\n";
