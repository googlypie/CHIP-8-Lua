# CHIP-8-Lua
A CHIP-8 emulator written entirely in Lua.

# Instructions
Download scoop for Windows if you don't already have it.<br>
Open PowerShell.<br>
Execute this command: "scoop install love"<br>
If this fails, try running "scoop bucket add extras", then try the previous command again.<br>
After this, put your .ch8 file in the same folder as the .lua file.<br>
Run the "run.bat" file.<br>
<br>
Change cycles_per_step in config.txt to change CPU speed.<br>
Change shift_mode in config.txt if needed. The two options are "original" and "modern".<br>
"debug" and "debug_c" in config.txt activate debug in love2d and debug in console.
