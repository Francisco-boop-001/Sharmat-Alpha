<?php
// Load the actual production mapper without bootstrapping a live CHIM database.
$source = file_get_contents(($argv[1] ?? dirname(__DIR__)) . '/common.php');
$start = strpos($source, 'function aiagentNsfwOrgasmLocationPhrase(');
$end = strpos($source, "\nfunction ", $start + 1);
eval(substr($source, $start, $end - $start));
$checks = 0;
foreach (['', 'ostim_partner_fallback', 'actor_list_fallback', 'unrecognized_action'] as $action) {
    foreach ([false,true] as $female) {
        ++$checks;
        if (aiagentNsfwOrgasmLocationPhrase($action,$female) !== '') { throw new RuntimeException("unknown metadata invented a location: {$action}"); }
    }
}
foreach (['vaginalsex', 'analsex', 'handjob'] as $action) {
    ++$checks;
    if (aiagentNsfwOrgasmLocationPhrase($action,false) === '') { throw new RuntimeException("known action mapping lost: {$action}"); }
}
echo "orgasm_metadata_test: {$checks} checks passed\n";
