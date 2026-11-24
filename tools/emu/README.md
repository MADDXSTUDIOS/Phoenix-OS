# Test emulator

Runs Phoenix OS outside Minecraft so changes can be checked quickly. It boots
CC:Tweaked's real `bios.lua` and ROM in a Lua 5.2 runtime, fakes the screen,
disk, timers and http, and saves screenshots as PNG files.

Time is virtual, so a test that "waits" 5 seconds finishes instantly.

## Setup

```
pip install lupa pillow
git clone --depth 1 --branch v1.21.1-1.120.2 https://github.com/cc-tweaked/CC-Tweaked
export CC_LUA=$PWD/CC-Tweaked/projects/core/src/main/resources/data/computercraft/lua
```

## Run the tests

```
python3 tools/emu/test_phoenix.py shots/
```

This installs Phoenix on a blank computer, goes through setup, opens and drags
windows, checks the permissions a standard user gets, crashes a program on purpose,
reboots and runs the installer. Screenshots of each stage land in `shots/`.

## Differences from the real thing

- Plain Lua 5.2 rather than CC's Cobalt, so a few edge cases differ.
- No peripherals, modems or redstone yet.
- The font in screenshots is DejaVu Sans Mono, not CC's.

Always give it a go in game before a release.
