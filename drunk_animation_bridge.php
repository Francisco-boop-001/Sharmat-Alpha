<?php

// The companion OAR condition reads the current Variable10 actor value (AV 77).
function aiagentNsfwDrunkAnimationTarget($stage, $enabled, $inScene)
{
    $stage = max(0, min(10, (int)$stage));
    return $enabled && !$inScene && $stage >= 5 ? $stage : 0;
}

function aiagentNsfwSyncDrunkAnimation($refid, $stage, $enabled, $inScene, array &$state, $commands)
{
    $target = aiagentNsfwDrunkAnimationTarget($stage, $enabled, $inScene);
    $previous = (int)($state['aiagent_nsfw_drunk_av'] ?? 0);
    if ($target === 0 && $previous === 0) {
        return false;
    }
    $refid = preg_replace('/^0x/i', '', trim((string)$refid));
    if (!preg_match('/^[0-9a-fA-F]{1,8}$/', $refid) || hexdec($refid) === 0) {
        return false;
    }

    // Reassert active state on each context turn: the server cache is not a game
    // acknowledgement, and a loaded save may contain an older actor value.
    $commands->send($commands->Actor->ForceActorValue('0x' . $refid, 'Variable10', (float)$target));
    if ($target > 0) {
        $state['aiagent_nsfw_drunk_av'] = $target;
    } else {
        unset($state['aiagent_nsfw_drunk_av']);
    }
    // Only a real transition should defer the separate drunk-physics reaction.
    return $target !== $previous;
}
