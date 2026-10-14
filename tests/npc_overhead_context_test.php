<?php
require dirname(__DIR__) . '/npc_scene_tone.php';
class NsfwRelationship {
    static function getRelationshipOverhead(...$args) { return 'PLAYER_RELATIONSHIP_SENTINEL'; }
    static function getRoleContextOverhead(...$args) { return 'PLAYER_SERVICE_SENTINEL'; }
    static function getRoleStatusOverhead(...$args) { return 'OWNER_IDENTITY_SENTINEL'; }
}
$source=file_get_contents(dirname(__DIR__).'/context_pre.php');
$start=strpos($source,'$__intimacyPromptState =');
$end=strpos($source,'// Real-drinks-only mode:', $start);
$block=str_replace("require_once __DIR__ . '/npc_scene_tone.php';", '', substr($source,$start,$end-$start));
foreach (['player','invite','accepted','engaged','ended','defeat'] as $case) {
    $actorName='Speaker';
    $GLOBALS['PLAYER_NAME']='Player';
    $GLOBALS['HERIKA_PERS']='BASE_CHARACTER_SENTINEL';
    $state=['is_npc_scene'=>$case!=='player','scene_phase'=>$case==='player'?'engaged':$case,'scene_actors'=>['Speaker','Partner B']];
    if ($case==='defeat') $state+=['framework_forced_scene'=>true,'scene_player_is_victim'=>true,'scene_actor_is_aggressor'=>true];
    $__promptState=['aiagent_nsfw_intimacy_data'=>$state];
    eval($block);
    $out=$GLOBALS['HERIKA_PERS'];
    $expected=in_array($case,['player','ended'],true);
    if (str_contains($out,'PLAYER_RELATIONSHIP_SENTINEL')!==$expected || str_contains($out,'PLAYER_SERVICE_SENTINEL')!==$expected) throw new RuntimeException($case.' wrong relationship overhead');
    if (!str_contains($out,'BASE_CHARACTER_SENTINEL')) throw new RuntimeException('base identity removed');
    if ($case!=='defeat' && !str_contains($out,'OWNER_IDENTITY_SENTINEL')) throw new RuntimeException('owner identity removed');
}
echo "npc_overhead_context_test: six routes passed\n";
