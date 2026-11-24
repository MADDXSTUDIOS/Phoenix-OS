# Phoenix OS

A Windows-style desktop operating system for CC:Tweaked advanced computers
(Minecraft 1.21.1). This is the `dev` branch: **Phoenix OS Standard 0.1.2-dev**.

## Install

Phoenix OS isn't released yet: `main` only shows an "under development" screen.
To install this development build on an **Advanced Computer**, run:

```
wget run https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/install.lua dev
```

It downloads the OS, restarts, and asks you to create the administrator account.
The computer then keeps updating from `dev`.

## Updating

Administrators can update from **Settings > Updates** (Check, then Update) or by typing
`update` in the Shell. It downloads the new version, removes files that are no longer part
of the OS, and restarts. Accounts, settings and everything in `/usr` are left alone.

Every change pushed to GitHub counts as an update, even without a new version number,
because each release has a build code made from all of its files. To test work in
progress on another branch, point a computer at it with `update branch <name>` in the
Shell (or the Branch button in Settings). `update force` reinstalls even when it's already
up to date. Until the first release, `main` has nothing to update from, so stay on `dev`.

## Versions and branches

- `main` holds releases only. Until the first one it's a placeholder (README plus an installer
  that shows "under development"); normal computers will update from here once it's released.
- `dev` is work in progress and carries the next version with `-dev` on the end, e.g. `0.1.2-dev`.
  Install a test computer from it with the `install.lua dev` command above.
- Builds handed to other people to test get `-alpha.1`, `-alpha.2` (rough, things missing),
  then `-beta.1`... (feature-complete, bug fixing).
- To release: drop the tag in `system/boot.lua`, rebuild the manifest, merge `dev` into `main`
  (replacing the placeholder installer and README with dev's), then bump dev to the next `-dev` version.

**Before committing changes to the OS, run `python3 tools/mkmanifest.py`** so the
file list and build code are current, otherwise computers won't see the update.

A standard (non-advanced) computer, turtle or pocket computer shows a
"not compatible" message instead. A command-line edition is planned for those.

## What works

- **Boot** with a recovery key: press **F8** on the start-up screen to drop to CraftOS.
  If Phoenix itself ever crashes it puts CraftOS back, shows the error and saves it to `/etc/crash.log`.
- **Accounts:** first-run setup, sign-in, lock screen, sign out. Passwords are salted SHA-256 hashes in `/etc/users.db`.
  Administrators and standard users.
- **Desktop:** icons (double-click), taskbar with a button per window, clock (Minecraft or real time),
  Start menu with apps, Lock, Sign out, Restart and Shut down.
- **Windows:** drag by the title bar, resize from the right and bottom edges, minimise, maximise
  (button or double-click the title), close. Each program draws only inside its own window.
- **Sandbox:** every program gets its own copy of the globals, its own `shell`, and can only send
  events to itself. Ctrl+T stops the program in front, never Phoenix itself.
- **Permissions:** standard users can read `/rom`, `/apps`, `/opt`, `/lib`; read and write their
  own `/usr/<name>`, `/tmp` and floppy disks; and can't see `/system`, `/etc` or other users' folders.
  Administrators can do everything.
- **Apps:** Files, Shell, Editor, Settings (system info, desktop colour, clock, users and passwords),
  Tasks (running programs, end task).
- **CraftOS programs** (`ls`, `edit`, `lua`, `wget`, `pastebin`...) run unchanged in the Shell.
- **Event log** in `/etc/events.log`: sign-ins, failed sign-ins, crashes, power.
- **Updater:** Settings > Updates or `update` in the Shell, with a branch switch for testing.

## Layout

```
startup.lua      starts /system/boot.lua
system/          the OS: boot, kernel, window manager, desktop, sign-in, accounts
lib/             libraries programs can require ("ui", "sha256", "update")
apps/<id>/       built-in apps: app.cfg (name, icon, window size) + main.lua
etc/  usr/  tmp/ made on the computer: settings and accounts, home folders, temporary files
tools/           test emulator, icon maker, manifest builder (not installed)
```

## Writing an app

Make a folder with `app.cfg` and `main.lua`: in `/apps` for built-in apps, or in `/opt`
for installed programs (updates never touch `/opt`). Phoenix finds it at start-up.

In the Start menu, apps go in the **Programs** sub-menu unless `app.cfg` says otherwise:
`group = "Utilities"` puts it in Utilities (or any new group name), and `group = false`
puts it at the top level, like Files.

```lua
-- app.cfg
{ name = "Hello", w = 30, h = 8 }
```

```lua
-- main.lua
local ui = require("ui")
local form = ui.form(term.current())
form:add(ui.label({ x = 2, y = 2, text = "Hello, " .. phoenix.user() }))
form:add(ui.button({ x = 2, y = 4, text = "Close", onClick = function() form.done = true end }))
ui.run(form)
```

Apps also get the `phoenix` API: `phoenix.user()`, `phoenix.launch(id)`, `phoenix.run(path)`,
`phoenix.window.setTitle(text)`, `phoenix.proc.list()` / `kill(pid)`, `phoenix.settings.get/set`,
`phoenix.users.*`, `phoenix.system.info()` and `phoenix.power.*`.

## Testing without Minecraft

`tools/emu` is a small CC:Tweaked emulator that boots the real CraftOS ROM and drives
Phoenix with fake key presses and clicks. See [tools/emu/README.md](tools/emu/README.md).

## Not in this version yet

Recycle Bin, file permissions editor, App Store, Print Manager, Event Log viewer, multi-monitor,
the Workstation's 102x38 screen, and everything Professional and Server (domain, group policies,
roaming files).
