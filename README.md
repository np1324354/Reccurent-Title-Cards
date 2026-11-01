# Reccurent-Title-Cards
A small edit to hud.ui to make it so the large title cards are triggered when entering an area regardless of whether or not you've already been there. Basically, the game has m_bHasVisitedLocation set as either true or false. If false, the game triggers the title card. If true, the title card isn't triggered. This mod doesn't change the true/false value (so the game still knows if you've been somewhere), it just makes it so the UI doesn't care either way and drops the title card even if m_bHasVisitedLocation is true.

See a video demo here: https://streamable.com/k4slb6

Requirements
- Loose Files Loader

Installation 
- Install the Loose Files Loader
- Extract the contents of this mod's archive into your Control installation directory (the folder containing Control_DX12.exe), usually something like 'C:\Program Files (x86)\Steam\steamapps\common\Control'
- Double-click 'Install-Recurrent-Title-Cards.bat'
- Once the installer reports success, you're good to go.

If nothing changes in-game, confirm the Loose Files Loader is installed next to Control_DX12.exe, then check %LOCALAPPDATA%\Remedy\Control\LooseFilesLoader.log. Make sure you see >> Loose file request: data\uiresources\p7\hud.ui

To uninstall, navigate to 'Control\data\uiresources\p7' and delete the loose 'hud.ui' file created by this mod. Alternatively, if you don't have any other mods under the uiresources umbrella, feel free to delete that whole folder. This mod doesn't change anything in the game's actual archives, executables, or your saves, so it should be save compatible and safe to add/remove whenever you want.

Compatibility
- This mod only adds an edited loose data\uiresources\p7\hud.ui resource and should be compatible with anything that doesn't touch that file. Anything that does would conflict and would need to be merged. 
- If you already have a loose hud.ui file from another mod, the script will attempt to merge its edits into your existing hud.ui file. If successful, it'll save a backup of your original hud.ui file as 
hud.ui.before-recurrent-title-cards-[timestamp].bak
- If you then want to uninstall this mod from your merged hud.ui file, just delete the existing hud.ui and rename the backup .bak file back to hud.ui
- Tested on the Steam DX12 version of the game.

Credits
GrzybDev's Northlight Tools: https://github.com/GrzybDev/NorthlightTools
