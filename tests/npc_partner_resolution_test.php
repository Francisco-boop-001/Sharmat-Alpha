<?php
// Execute production placeholder mapping without loading the server.
$root=$argv[1]??dirname(__DIR__);
$source=file_get_contents($root.'/nsfw_npc_scene.php');
$start=strpos($source,"if (!function_exists('aiagentNsfwCleanSceneName'))");
$end=strpos($source,'class NsfwNpcScene {');
eval(substr($source,$start,$end-$start));
$GLOBALS['PLAYER_NAME']='Player';
$checks=0;
function checkPartner($ok,$label) { $GLOBALS['checks']++; if (!$ok) throw new RuntimeException($label); }
$status=['is_npc_scene'=>true,'scene_phase'=>'engaged','scene_actors'=>['Test Speaker','Test Partner'],'npc_scene_partner'=>'Test Partner','current_primary_partner'=>'Test Speaker','sex_partner'=>'Test Speaker'];
foreach ([[],['primary_partner'=>'Test Speaker'],['primary_partner'=>'Player'],['primary_partner'=>'Old Partner']] as $extra) {
    $map=aiagentNsfwBuildScenePlaceholderMap('Test Speaker',$status,$extra);
    checkPartner($map['#PRIMARY_PARTNER#']==='Test Partner','self/player/stale primary must resolve actual counterpart');
    checkPartner($map['#NPC_PARTNER#']==='Test Partner','NPC counterpart must not be self');
}
$group=$status;
$group['scene_actors'][]='Third Actor';
$group['current_primary_partner']='Third Actor';
checkPartner(aiagentNsfwBuildScenePlaceholderMap('Test Speaker',$group)['#PRIMARY_PARTNER#']==='Third Actor','valid group primary is preserved');
checkPartner(aiagentNsfwBuildScenePlaceholderMap('Test Speaker',$group,['primary_partner'=>'Test Partner'])['#PRIMARY_PARTNER#']==='Test Partner','explicit valid group counterpart is preserved');
$single=['is_npc_scene'=>true,'scene_actors'=>['Test Speaker'],'current_primary_partner'=>'Test Speaker'];
checkPartner(aiagentNsfwBuildScenePlaceholderMap('Test Speaker',$single)['#PRIMARY_PARTNER#']==='the other NPC','missing counterpart must not become self');
$player=$status; $player['is_npc_scene']=false; $player['scene_actors']=['Test Speaker','Player']; unset($player['sex_partner']);
checkPartner(aiagentNsfwBuildScenePlaceholderMap('Test Speaker',$player)['#PRIMARY_PARTNER#']==='Player','player route unchanged');
$map=aiagentNsfwBuildScenePlaceholderMap('Test Speaker',$status,['orgasmer_name'=>'Test Speaker']);
checkPartner($map['#ORGASMER_NAME#']==='Test Speaker','self orgasm identity remains distinct from partner');
echo "npc_partner_resolution_test: {$checks} cases passed\n";
