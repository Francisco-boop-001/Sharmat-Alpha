<?php
$source=file_get_contents(dirname(__DIR__).'/config_manager.php');
$start=strpos($source,"            if (isset(\$_POST['npc_scene_relationship_style_check'])) {");
$end=strpos($source,"            \$extendedData['nsfw_profanity_level']",$start);
$save=substr($source,$start,$end-$start);
$checks=0;
foreach ([true,false,'true','false','0','1','inherit',null] as $input) {
    $extendedData=['npc_scene_relationship_style_check'=>false,'sex_speech_style'=>'custom'];
    $_POST=$input===null ? [] : ['npc_scene_relationship_style_check'=>$input];
    eval($save);
    $expected=$input==='inherit' ? null : ($input===null ? false : filter_var($input,FILTER_VALIDATE_BOOLEAN));
    if (($extendedData['npc_scene_relationship_style_check']??null)!==$expected || $extendedData['sex_speech_style']!=='custom') throw new RuntimeException('NPC override save failed');
    $checks++;
}
preg_match('/\x27npc_scene_relationship_style_check\x27 => (isset\(.*? : null),/',$source,$load);
foreach ([[],['npc_scene_relationship_style_check'=>false],['npc_scene_relationship_style_check'=>true]] as $extendedData) {
    $value=eval('return '.$load[1].';');
    if ($value!==($extendedData['npc_scene_relationship_style_check']??null)) throw new RuntimeException('NPC inheritance load mismatch');
    $checks++;
}
preg_match('/\x27NPC_SCENE_RELATIONSHIP_STYLE_CHECK\x27 => (isset\(.*?),\r?\n/',$source,$globalSave);
foreach ([true,false,'true','false','0','1',null] as $input) {
    $_POST=$input===null ? [] : ['NPC_SCENE_RELATIONSHIP_STYLE_CHECK'=>$input];
    $value=eval('return '.$globalSave[1].';');
    if ($value!==($input===null ? true : filter_var($input,FILTER_VALIDATE_BOOLEAN))) throw new RuntimeException('Global setting save failed');
    $checks++;
}
echo "npc_style_setting_test: {$checks} checks passed\n";
