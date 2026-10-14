<?php
// Executes the real cue builder with an isolated, read-only relationship fixture.
$case = $argv[1] ?? 'low';
$root = $argv[2] ?? dirname(__DIR__);
require_once dirname(__DIR__) . '/npc_scene_tone.php';
function _getNsfwSetting($key,$default=null) { return $key==='NPC_SCENE_RELATIONSHIP_STYLE_CHECK' ? $GLOBALS['case']!=='global_off' : $default; }
function getGlobalPrompt($key) { return in_array($key,['dd_awareness','dd_gag_muffle'],true) ? '1' : ''; }
function getIntimacyForActor($actor) { return $GLOBALS['fixtureStatus']; }
function getDrunkStageForActor($actor) { return $GLOBALS['case'] === 'drunk' ? 3 : 0; }
class NsfwNpcData {
    static function get($actor) { return ['relationship_preference'=>'monogamous', 'sex_speech_style'=>'custom', 'npc_scene_relationship_style_check'=>$GLOBALS['case']==='style_off' ? false : null, 'is_slut'=>$GLOBALS['case']==='generated_role', 'aiagent_nsfw_devices'=>$GLOBALS['case']==='gag' ? 'gag' : '']; }
}
class NsfwData { static function getSpeakStyle($name) { return ['climax_prompt'=>'STYLE_SENTINEL']; } }
class RelationshipManager {
    static function getRelationship($a,$b) { return ['aff'=>$GLOBALS['case']==='high' ? 80 : 8,'tier'=>'Acquaintance','type'=>'platonic']; }
    static function getPlayerRelationship($a) { return $GLOBALS['case']==='high' ? [] : ['aff'=>100,'type'=>'romantic']; }
}
class PromptFixtureDb {
    function fetchOne($sql) { return ['value'=>json_encode(['climax'=>'CLIMAX_SENTINEL','orgasm'=>'ORGASM_SENTINEL','npc_scene_active'=>'DEFAULT_SCENE_SENTINEL','npc_orgasm'=>'DEFAULT_ORGASM_SENTINEL'])]; }
}
$source=file_get_contents($root.'/nsfw_npc_scene.php');
$start=strpos($source,"if (!function_exists('aiagentNsfwCleanSceneName'))");
$end=strpos($source,'class NsfwNpcScene {');
eval(substr($source,$start,$end-$start));
$GLOBALS['db']=new PromptFixtureDb();
$GLOBALS['HERIKA_NAME']='Speaker';
$GLOBALS['PLAYER_NAME']='Player';
$GLOBALS['TEMPLATE_DIALOG']='FORMAT_SENTINEL';
$GLOBALS['gameRequest']=['ext_nsfw_npc_scene',0,0,'REPORTED_EVENT'];
$GLOBALS['fixtureStatus']=['is_npc_scene'=>true,'scene_phase'=>'accepted','scene_actors'=>['Speaker','Partner B'],'npc_scene_partner'=>'Partner B','current_primary_partner'=>'Partner B'];
$GLOBALS['AIAGENTNSFW_SCENE_CUE_OVERRIDE']='STYLE_SENTINEL FORMAT_SENTINEL';
$GLOBALS['AIAGENTNSFW_RECHAT_SEX']=true;
$GLOBALS['PROMPTS']['rechat']['cue']=['RECHAT_SENTINEL'];
if ($case==='player') { $GLOBALS['fixtureStatus']['is_npc_scene']=false; $GLOBALS['fixtureStatus']['scene_actors']=['Speaker','Player']; }
if ($case==='invite') { $GLOBALS['gameRequest'][0]='ext_nsfw_npc_invite'; $GLOBALS['fixtureStatus']['scene_phase']='invite'; }
if ($case==='pillow') { $GLOBALS['AIAGENTNSFW_PILLOW_TALK_CUE']='PILLOW_SENTINEL'; }
if ($case==='refusal') { $GLOBALS['AIAGENTNSFW_NONCONSENT_CUE']='REFUSAL_SENTINEL'; }
// Only the required data include is stubbed; prompt code is copied unchanged.
$tmp=sys_get_temp_dir().'/sharmat-prompt-test-'.bin2hex(random_bytes(8));
mkdir($tmp);
file_put_contents($tmp.'/prompts.php',file_get_contents($root.'/prompts.php'));
file_put_contents($tmp.'/nsfw_data.php',"<?php\n");
try { require $tmp.'/prompts.php'; }
finally { unlink($tmp.'/prompts.php'); unlink($tmp.'/nsfw_data.php'); rmdir($tmp); }
$cue=$GLOBALS['PROMPTS']['ext_nsfw_npc_scene']['cue'][0];
$chat=$GLOBALS['PROMPTS']['chatnf_sl']['cue'][0];
$check=function($ok,$msg) use($case) { if (!$ok) { throw new RuntimeException("{$case}: {$msg}"); } };
if (in_array($case,['low','drunk'],true)) {
    $check(!str_contains($cue,'STYLE_SENTINEL') && !str_contains($cue,'DEFAULT_SCENE_SENTINEL'),'forced style survived final cue assembly');
    $check(str_contains($cue,'affinity 8') && str_contains($cue,'Partner B'),'actual relationship missing');
    $check(str_contains($cue,'FORMAT_SENTINEL'),'response format lost');
    $check($GLOBALS['PROMPTS']['rechat']['cue'][0] === $chat,'rechat lost final scene tone');
    $check(!str_contains($GLOBALS['PROMPTS']['ext_nsfw_npc_orgasm']['cue'][0],'DEFAULT_ORGASM_SENTINEL'),'climax cue bypassed tone policy');
}
if ($case==='drunk') { $check(str_contains($cue,'You are intoxicated'),'intoxication override lost'); }
if (in_array($case,['high','player','style_off','global_off','generated_role'],true)) { $check(str_contains($chat,'STYLE_SENTINEL'),'eligible/player/disabled-check style changed'); }
if (in_array($case,['style_off','global_off','generated_role'],true)) {
    $check(str_contains($cue,'STYLE_SENTINEL') && str_contains($cue,'Partner B'),'NPC style override lost on final assembly');
    $check(str_contains($cue,'affinity 8'),'disabling style check must retain actual relationship context');
}
if ($case==='pillow') { $check(str_contains($cue,'PILLOW_SENTINEL'),'post-scene precedence lost'); }
if ($case==='refusal') { $check(str_contains($chat,'REFUSAL_SENTINEL'),'refusal precedence lost'); }
if ($case==='gag') { $check(!str_contains($chat,'npc_relationship_context'),'gag muffle overwritten by tone fallback'); }
if ($case==='invite') { $check(!str_contains($GLOBALS['PROMPTS']['ext_nsfw_npc_invite']['cue'][0],'npc_relationship_context'),'invite route overwritten'); }
echo "npc_scene_prompt_integration_test: {$case} passed\n";
