# SHARMAT Alpha - Skyrim mod download

**[Download the complete SHARMAT 3.1.9.10 ZIP](https://github.com/Wondernuttz/Sharmat-Alpha/releases/download/v3.1.9.10/SHARMAT-3.1.9.10.zip)**

Install the ZIP in MO2 or Vortex over your existing SHARMAT mod. Keep
`AIAgentNSFW.esp` enabled. Update the server through SHARMAT's Info page as well.
The release ZIP includes the matching embedded server package for CHIM versions
that support it. Individual files in this source folder are not the installer.

For drunk animations, separately install [Open Animation Replacer](https://www.nexusmods.com/skyrimspecialedition/mods/92109)
and the standard **Drunk animations 1.6.1** main file from
[Drunk or drugged animations OAR](https://www.nexusmods.com/skyrimspecialedition/mods/62191).
Let SHARMAT win the animation pack's `config.json` conflict. Custom OAR overrides
need the SHARMAT condition merged into them. No animation assets are bundled.

Version 3.1.9.10 restores the Plugin Page link after GitHub Plugin Manager installs
by including the standard `index.php` entry point in both server package formats.
The original `config_manager.php` address remains available. It retains the
3.1.9.9 complete-download fix and matching Download Game Mod button styling.
The game scripts are unchanged from the complete 3.1.9.8 GitHub release.
Ensure SHARMAT wins conflicts for `Scripts/AIAgentNSFW*.pex` in your mod manager.

The included game scripts isolate optional framework dependencies so missing SexLab scripts
cannot disable OStim event registration, and the shared scripts do not require
OStim-specific types on SexLab-only setups. Both frameworks remain supported
together. The full ZIP contains the rebuilt game scripts and matching server package.

Restart Skyrim and load a save after installing. No new save, quest reset, or
animation-cache deletion is needed. Preserve custom scene-framework settings.
