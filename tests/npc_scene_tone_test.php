<?php
require_once dirname(__DIR__) . '/npc_scene_tone.php';
$checks = 0;
function toneCheck($ok, $label) { global $checks; ++$checks; if (!$ok) { throw new RuntimeException($label); } }
$profile = ['relationship_preference' => 'monogamous'];
$player = ['aff' => 100, 'type' => 'romantic'];
$low = ['aff' => 8, 'type' => 'platonic', 'tier' => 'Acquaintance'];
$high = ['aff' => 80, 'type' => 'romantic', 'tier' => 'Devoted'];
$p = aiagentNsfwNpcSceneTonePolicy('Speaker', 'Partner B', $low, $profile, $player, 31);
toneCheck(!$p['allow_style'], 'player bond must not authorize the low-affinity NPC style');
toneCheck(str_contains($p['context'], 'Partner B') && str_contains($p['context'], 'affinity 8'), 'context must use the actual partner');
toneCheck(str_contains($p['context'], 'existing romantic bond with the player'), 'monogamy must retain the existing bond');
toneCheck(!str_contains(aiagentNsfwApplyNpcSceneTone('DEVOTED_STYLE_SENTINEL', $p, 'FORMAT_SENTINEL'), 'DEVOTED_STYLE_SENTINEL'), 'ineligible style must be replaced, not merely contradicted');
toneCheck(str_contains(aiagentNsfwApplyNpcSceneTone('old', $p, 'FORMAT_SENTINEL'), 'FORMAT_SENTINEL'), 'output format must survive fallback');
$p = aiagentNsfwNpcSceneTonePolicy('Speaker', 'Partner B', $high, $profile, $player);
toneCheck(!$p['allow_style'], 'high affinity must not silently transfer a monogamous player bond');
$p = aiagentNsfwNpcSceneTonePolicy('Speaker', 'Partner B', $high, ['relationship_preference'=>'polyamorous'], $player);
toneCheck($p['allow_style'], 'eligible polyamorous partner keeps the configured style');
$cue = aiagentNsfwApplyNpcSceneTone('STYLE_SENTINEL', $p);
toneCheck(str_contains($cue, 'STYLE_SENTINEL'), 'eligible custom style is preserved');
toneCheck(aiagentNsfwApplyNpcSceneTone($cue, $p) === $cue, 'multiple cue stages must not duplicate context');
toneCheck(aiagentNsfwNpcSceneTonePolicy('A','B',$high,$profile,[])['allow_style'], 'monogamy alone must not invent an outside partner');
toneCheck(aiagentNsfwNpcSceneTonePolicy('A','B',$low,$profile,$player,31,true)['allow_style'], 'special-role style lane remains available');
toneCheck(!aiagentNsfwNpcSceneTonePolicy('A','B',[],[],[])['allow_style'], 'missing relationship must not inherit affection');
toneCheck(aiagentNsfwNpcSceneTonePolicy('A','B',['aff'=>31],[],[],31)['allow_style'], 'configured threshold is inclusive');
toneCheck(!aiagentNsfwNpcSceneTonePolicy('A','B',['aff'=>30],[],[],31)['allow_style'], 'configured threshold boundary');
foreach ([[], ['is_npc_scene'=>false], ['is_npc_scene'=>true,'scene_phase'=>'invite'], ['is_npc_scene'=>true,'scene_phase'=>'ended'], ['is_npc_scene'=>true,'scene_phase'=>'accepted','scene_actors'=>[]], ['is_npc_scene'=>true,'scene_phase'=>'accepted','scene_actors'=>['A','B'],'scene_is_idle'=>true]] as $status) {
    toneCheck(aiagentNsfwGetNpcSceneTone('A',$status) === null, 'inactive, player, invite and idle routes must be untouched');
}
echo "npc_scene_tone_test: {$checks} checks passed\n";
