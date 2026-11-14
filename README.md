# Forge Tools

Automation for The Forge (Roblox): mining, forging, quests, selling and combat.

## Run it

Paste this into your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/forgetools/main/loader.lua"))()
```

The loader checks this repo every time it runs. If a newer build is here it downloads it first, then starts Forge Tools. If GitHub cannot be reached it runs the copy already on your machine.

Files are saved in your executor's `workspace/PlayerTools` folder, next to your settings.

## Files

| File | What it is |
| --- | --- |
| `loader.lua` | The one-line installer / updater |
| `ForgeTools.lua` | The script |
| `AtaraxiaLibrary.lua` | The menu library it uses |
| `version.json` | The build the loader compares against |
