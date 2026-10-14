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
foreach ([false, 'false', 0, '0'] as $off) {
    $p = aiagentNsfwNpcSceneTonePolicy('Speaker','Partner B',$low,$profile + ['npc_scene_relationship_style_check'=>$off],$player);
    toneCheck($p['allow_style'] && $p['reason']==='style_check_disabled', 'explicit off preserves the selected style');
    $cue = aiagentNsfwApplyNpcSceneTone('STYLE_SENTINEL', $p);
    toneCheck(str_contains($cue,'STYLE_SENTINEL') && str_contains($cue,'affinity 8'), 'disabled style check retains style and actual relationship');
    toneCheck(str_contains($cue,'existing romantic bond'), 'disabled style check does not erase an existing bond');
}
toneCheck(!aiagentNsfwNpcSceneTonePolicy('A','B',$low,$profile + ['npc_scene_relationship_style_check'=>true],$player)['allow_style'], 'explicit on retains previous protection');
foreach (['invite','accepted','engaged'] as $phase) toneCheck(aiagentNsfwHasNpcSceneContext(['is_npc_scene'=>true,'scene_phase'=>$phase,'scene_actors'=>['A','B']]), 'NPC route suppresses player-addressed overhead');
foreach ([[],['is_npc_scene'=>false,'scene_phase'=>'engaged','scene_actors'=>['A','Player']],['is_npc_scene'=>true,'scene_phase'=>'ended','scene_actors'=>['A','B']]] as $status) toneCheck(!aiagentNsfwHasNpcSceneContext($status), 'ordinary/player/ended context keeps player overhead');

foreach ([true,false,'false','0','1'] as $global) {
    foreach (['A','Another NPC'] as $actor) {
        $p=aiagentNsfwNpcSceneTonePolicy($actor,'B',$low,[],$player,56,false,$global);
        toneCheck($p['allow_style'] === !filter_var($global,FILTER_VALIDATE_BOOLEAN), 'global default applies to every unoverridden NPC');
    }
}
foreach ([true,false] as $global) {
    foreach ([true,false] as $override) {
        $p=aiagentNsfwNpcSceneTonePolicy('A','B',$low,['npc_scene_relationship_style_check'=>$override],$player,56,false,$global);
        toneCheck($p['allow_style'] === !$override, 'explicit NPC override wins over global default');
        $p=aiagentNsfwNpcSceneTonePolicy('A','B',$low,['is_slut'=>true,'npc_scene_relationship_style_check'=>$override],$player,56,false,$global);
        toneCheck($p['allow_style'] && $p['reason']==='profile_role', 'generated/manual role bypass wins over both settings');
    }
}
toneCheck(!aiagentNsfwNpcSceneTonePolicy('A','B',$low,['is_slut'=>'false'],$player)['allow_style'], 'false string is not a role flag');
echo "npc_scene_tone_test: {$checks} checks passed\n";
