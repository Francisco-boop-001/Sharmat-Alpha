<?php
/** True only while NPC-directed context owns the current scene/approach. */
function aiagentNsfwHasNpcSceneContext($status)
{
    return is_array($status) && !empty($status['is_npc_scene'])
        && in_array(strtolower((string)($status['scene_phase'] ?? '')), ['invite', 'accepted', 'engaged'], true)
        && !empty($status['scene_actors']);
}

/** Partner-specific dialogue policy; never starts, accepts, stops or scores a scene. */
function aiagentNsfwNpcSceneTonePolicy($actor, $partner, array $relationship, array $profile, array $playerRelationship, $minimumAffinity = 56, $roleStyle = false, $globalStyleCheck = true)
{
    $affinity = (int)($relationship['aff'] ?? 0);
    $tier = (string)($relationship['tier'] ?? 'unknown');
    $type = (string)($relationship['type'] ?? 'unknown');
    $preference = strtolower(trim((string)($profile['relationship_preference'] ?? 'uncommitted')));
    $playerType = strtolower(trim((string)($playerRelationship['type'] ?? '')));
    $otherBond = $preference === 'monogamous'
        && in_array($playerType, ['romantic', 'romance', 'marriage', 'married'], true)
        && (int)($playerRelationship['aff'] ?? 0) > 0;
    // Generated and manually edited profiles use the same role flag at request time.
    $automaticStyleBypass = filter_var($profile['is_slut'] ?? false, FILTER_VALIDATE_BOOLEAN);
    $styleCheckEnabled = !$automaticStyleBypass && filter_var($profile['npc_scene_relationship_style_check'] ?? $globalStyleCheck, FILTER_VALIDATE_BOOLEAN);
    $context = "Current partner: {$partner}. {$actor}'s relationship toward {$partner}: {$type}, {$tier}, affinity {$affinity}. "
        . "Relationship preference: {$preference}. Keep feelings toward this partner separate from feelings toward the player or another partner. "
        . "An active animation establishes an event, not affection, approval, devotion or a changed relationship. "
        . "Describe only the reported event and react in character; do not invent positive feelings or rewrite existing bonds. "
        . "This is dialogue context only; do not issue player-scene acceptance, refusal or stop commands from this instruction.";
    if ($otherBond) {
        $context .= ' The existing romantic bond with the player remains relevant; do not transfer that bond or its devoted speech to this NPC.';
    }
    return [
        'allow_style' => !$styleCheckEnabled || $roleStyle || ($affinity >= (int)$minimumAffinity && !$otherBond),
        'reason' => $automaticStyleBypass ? 'profile_role' : (!$styleCheckEnabled ? 'style_check_disabled' : ($roleStyle ? 'role_style' : ($otherBond ? 'existing_monogamous_bond' : ($affinity < (int)$minimumAffinity ? 'partner_affinity' : 'eligible_partner')))),
        'context' => $context,
    ];
}

function aiagentNsfwApplyNpcSceneTone($prompt, array $policy, $template = '')
{
    if (!$policy['allow_style']) {
        return '<npc_relationship_context>' . $policy['context'] . '</npc_relationship_context>'
            . ' React briefly to the current reported scene event using the relationship tone above.'
            . ($template !== '' ? ' ' . $template : '');
    }
    if (strpos((string)$prompt, $policy['context']) !== false) {
        return $prompt;
    }
    return $prompt . "\n<npc_relationship_context>" . $policy['context'] . '</npc_relationship_context>';
}

function aiagentNsfwGetNpcSceneTone($actor, $status, $extra = [])
{
    if (!is_array($status) || empty($status['is_npc_scene'])
        || !in_array($status['scene_phase'] ?? '', ['accepted', 'engaged'], true)
        || empty($status['scene_actors']) || !empty($status['scene_is_idle'])) {
        return null;
    }
    $map = aiagentNsfwBuildScenePlaceholderMap($actor, $status, $extra);
    $partner = $map['#PRIMARY_PARTNER#'] ?? '';
    // Use current directed relationships on every request, not the first scene's cache.
    $relationship = RelationshipManager::getRelationship($actor, $partner);
    $profile = NsfwNpcData::get($actor);
    $playerRelationship = RelationshipManager::getPlayerRelationship($actor);
    $roleStyle = (function_exists('isNpcSlave') && isNpcSlave($actor))
        || (function_exists('isProstitute') && isProstitute($actor));
    $floor = function_exists('_getNsfwSetting') ? (int)_getNsfwSetting('NSFW_SCENE_CALL_MIN_AFFINITY', 56) : 56;
    $globalStyleCheck = function_exists('_getNsfwSetting') ? _getNsfwSetting('NPC_SCENE_RELATIONSHIP_STYLE_CHECK', true) : true;
    return aiagentNsfwNpcSceneTonePolicy($actor, $partner, (array)$relationship, (array)$profile, (array)$playerRelationship, $floor, $roleStyle, $globalStyleCheck);
}
