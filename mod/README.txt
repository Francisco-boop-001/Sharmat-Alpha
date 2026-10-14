SHARMAT 3.1.9.7 - Scene Dialogue, Affection Roles and Fertility State

INSTALL / UPDATE
1. Fully exit Skyrim.
2. Install the complete release ZIP into your existing SHARMAT mod in MO2 or Vortex.
3. Keep AIAgentNSFW.esp enabled. Preserve any custom values in
   SKSE/Plugins/StorageUtilData/SHARMAT_scene_framework.json.
4. Restart Skyrim and load a save.

Requires CHIM and its normal dependencies, plus the enabled OStim or SexLab
framework and suitable installed animations. Those frameworks and animation
packs are separate downloads.

This update adds global and per-NPC Speak Style controls, corrects NPC scene
partner context and OStim affection roles, and prevents stale profile saves
from restoring cleared pregnancy state. Both server and game files must be updated.

The Sharmat web updater updates the SERVER component. After updating, use
Download Game Mod on the Info page to obtain the matching game files.
The web updater alone does not replace the Papyrus scripts in your game.

Release ZIPs also include a matching server component under CHIM/server-plugins.
CHIM versions supporting embedded server packages install it on save load.

SCENE FRAMEWORK SETTINGS
SKSE/Plugins/StorageUtilData/SHARMAT_scene_framework.json defaults to:
  { "ostim": 1, "sexlab": 1 }
Set a value to 0 to disable that framework's game-side hooks, then reload a save.
These settings are independent of the web Detect OStim / Detect SexLab options.

DRUNK ANIMATION COMPATIBILITY
Install Open Animation Replacer and the standard "Drunk animations" 1.6.1
main file from https://www.nexusmods.com/skyrimspecialedition/mods/62191.
Let SHARMAT win the config.json conflict with that animation pack in MO2/Vortex.
SHARMAT supplies a compatibility condition only; SamuelGA24's animations remain
a separate dependency. This configuration retains the pack's original triggers
and priority, adding SHARMAT's Variable10 values 5 through 10 as another trigger.
Stages 1-4 do not activate this animation pack through SHARMAT.

Enable Track Drunk Status and Enable Drunk Animations / Physics in SHARMAT.
Changes to drunkenness and the animation toggle synchronize on an NPC context
turn. Existing CACO/other-mod triggers continue working independently, including
when SHARMAT's animation option is off. A higher-priority eligible OAR animation
can still win; SHARMAT does not raise the animation pack's priority.

If you customized this pack in OAR, back up your configuration and merge the
SHARMAT condition into your custom configuration instead of overwriting it.
A user.json override may take precedence over this packaged config.json.
The Animated Inebriation alternate main file has not been validated here.
