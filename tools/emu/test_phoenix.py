#!/usr/bin/env python3
"""End-to-end test of Phoenix OS in the emulator.

    CC_LUA=/path/to/CC-Tweaked/.../data/computercraft/lua python3 tools/emu/test_phoenix.py [shots_dir]

Boots a fresh computer, goes through first-run setup, drives the desktop with
fake key presses and clicks, and checks what ends up on screen. Screenshots of
each stage are saved if a folder is given.
"""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from emu import Emu  # noqa: E402

LUA = os.environ.get("CC_LUA")
SHOTS = sys.argv[1] if len(sys.argv) > 1 else None
if not LUA or not os.path.isfile(os.path.join(LUA, "bios.lua")):
    sys.exit("Set CC_LUA to CC:Tweaked's data/computercraft/lua folder (see tools/emu/README.md)")
if SHOTS:
    os.makedirs(SHOTS, exist_ok=True)

passed = 0
last = None  # the emulator most recently looked at, so a failure can show its screen


def check(cond, what):
    global passed
    if not cond:
        if last:
            print("\n".join(last.screen()))
        raise AssertionError(what)
    passed += 1


def shot(e, name):
    if SHOTS:
        e.png(os.path.join(SHOTS, name + ".png"))


def text(e):
    global last
    last = e
    return "\n".join(e.screen())


def desktop(e):
    """True when the taskbar (and so the desktop) is showing."""
    return text(e).split("\n")[e.h - 1].startswith(" Phoenix ")


def install(root):
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root)
    # a pretend installed program, to check /opt apps land in Programs
    os.makedirs(os.path.join(root, "opt", "clock"))
    with open(os.path.join(root, "opt", "clock", "app.cfg"), "w") as f:
        f.write('{ name = "Clock", w = 20, h = 5 }\n')
    with open(os.path.join(root, "opt", "clock", "main.lua"), "w") as f:
        f.write('print(textutils.formatTime(os.time()))\nos.pullEvent("key")\n')
    for item in ("startup.lua", "system", "lib", "apps"):
        src, dst = os.path.join(REPO, item), os.path.join(root, item)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)


GROUPED = {"Shell": "Utilities", "Settings": "Utilities", "Tasks": "Utilities", "Editor": "Programs", "Clock": "Programs"}


def menu(e, item):
    """Open the Start menu and click an entry by its text (going through its sub-menu if it has one)."""
    e.click(3, e.h)
    if item in GROUPED:
        pos = e.find("  " + GROUPED[item])
        check(pos, "Start menu shows " + GROUPED[item])
        e.click(pos[0] + 3, pos[1])
        # look only in the sub-menu, which pops out to the right of the menu (columns 23+)
        for y, row in enumerate(text(e).split("\n")):
            x = row.find("  " + item, 22)
            if x >= 0:
                e.click(x + 4, y + 1, settle=0.5)
                return
        check(False, "Utilities shows " + item)
    pos = e.find("  " + item)
    check(pos, "Start menu shows " + item)
    e.click(pos[0] + 3, pos[1], settle=0.5)


def sign_in(e, name, password):
    check("Sign in" in text(e), "sign-in screen is showing")
    e.type(name)
    e.key("enter")
    e.type(password)
    e.key("enter", settle=0.5)


def main():
    tmp = tempfile.mkdtemp(prefix="phoenix-emu-")
    root = os.path.join(tmp, "computer")
    install(root)

    # ---- a standard (non-advanced) computer is refused
    e = Emu(LUA, root, colour=False)
    e.boot()
    e.run(2)
    check("not compatible with Phoenix OS" in text(e), "standard computer gets the not-compatible message")
    check(e.screen()[-1].startswith(">") or any(r.startswith(">") for r in e.screen()), "and is left at CraftOS")
    shot(e, "00_not_compatible")

    # ---- recovery key at start-up
    e = Emu(LUA, root)
    e.boot()
    e.run(0.2)
    check("Press F8 for recovery" in text(e), "boot screen offers recovery")
    shot(e, "01_boot")
    e.key("f8", settle=0.5)
    check("Phoenix OS recovery" in text(e), "F8 drops to CraftOS")
    e.type("ls")
    e.key("enter")
    check("system" in text(e), "CraftOS works after recovery (APIs restored)")

    # ---- first run: create the administrator
    e = Emu(LUA, root)
    e.boot()
    e.run(2)
    check("Create the administrator account" in text(e), "first boot shows setup")
    shot(e, "02_setup")
    e.type("Aaron")
    e.key("enter")
    e.type("hunter2")
    e.key("enter")
    e.type("nope")
    e.key("enter")
    check("passwords don't match" in text(e), "setup rejects mismatched passwords")
    e.type("hunter2")
    e.key("enter", settle=1)
    check(desktop(e), "desktop with taskbar after setup")
    check(os.path.isdir(os.path.join(root, "usr", "aaron", "documents")), "home folder created (name lower-cased)")
    db = open(os.path.join(root, "etc", "users.db")).read()
    check("hunter2" not in db and "hash" in db, "password stored as a hash, not text")
    shot(e, "03_desktop")

    # ---- start menu, apps, windows
    e.click(3, e.h)
    check("aaron (admin)" in text(e) and "Shut down" in text(e), "Start menu opens")
    rows = e.screen()
    top = e.find("aaron (admin)")[1]  # the menu runs from the name row down to the taskbar
    menu_text = "\n".join(r[:22] for r in rows[top - 1:e.h - 1])
    check("Files" in menu_text and "Programs" in menu_text and "Utilities" in menu_text, "Files, Programs and Utilities are in the Start menu")
    check(not any(n in menu_text for n in ("Shell", "Settings", "Tasks", "Editor", "Clock")), "the other apps aren't loose in it")
    shot(e, "04_start_menu")
    pos = e.find("  Programs")
    e.click(pos[0] + 3, pos[1])
    fly = "\n".join(r[22:40] for r in e.screen()[top - 1:e.h - 1])
    check("Editor" in fly and "Clock" in fly, "Programs pops out Editor and the program installed in /opt")
    shot(e, "04a_programs")
    e.click(pos[0] + 3, pos[1])
    pos = e.find("  Utilities")
    e.click(pos[0] + 3, pos[1])
    fly = "\n".join(r[22:40] for r in e.screen()[top - 1:e.h - 1])
    check("Settings" in fly and "Tasks" in fly and "Shell" in fly, "Utilities pops out Settings, Tasks and Shell")
    shot(e, "04b_utilities")
    e.click(pos[0] + 3, pos[1])
    check("Shell" not in "\n".join(r[22:40] for r in e.screen()[top - 1:e.h - 1]), "clicking Utilities again closes the sub-menu")
    e.click(40, 5)
    check("Shut down" not in text(e), "clicking away closes the Start menu")

    e.double_click(5, 3, settle=0.5)
    check("aaron - Files" in text(e) and "documents" in text(e), "double-clicking the Files icon opens Files in the home folder")
    shot(e, "05_files")

    menu(e, "Shell")
    check("Phoenix OS Shell" in text(e), "Shell opens from the Start menu")
    e.type("ls /")
    e.key("enter")
    check("system" in text(e) and "startup.lua" in text(e), "CraftOS programs run in the shell (administrator sees /system)")
    e.type("ps")
    e.key("enter")
    check("Files" in text(e) and "Shell" in text(e), "ps lists processes")
    shot(e, "06_two_windows")

    # move the shell window by its title bar
    x, y = e.find(" Shell")
    e.drag(x + 4, y, x + 6, y - 1)
    check(e.find(" Shell") == (x + 2, y - 1), "dragging the title bar moves the window")
    # resize from the bottom-right corner (shell opens 46x14)
    x, y = e.find(" Shell")
    e.drag(x + 45, y + 13, x + 35, y + 10)
    e.type("clear")
    e.key("enter")
    e.type("lua")
    e.key("enter")
    e.type("term.getSize()")
    e.key("enter")
    check("34" in text(e) and "9" in text(e), "resizing changes the size the program sees")
    e.type("_G == getfenv(print), fs == _G.fs")
    e.key("enter")
    e.type("exit()")
    e.key("enter")
    shot(e, "07_moved_resized")

    # maximise by double-clicking the title, restore with the button
    x, y = e.find(" Shell")
    e.double_click(x + 4, y)
    check(e.find(" Shell") == (1, 1), "double-clicking the title maximises")
    shot(e, "08_maximised")
    e.click(e.w - 4, 1)
    check(e.find(" Shell") == (x, y), "the title-bar button restores it")

    # taskbar: minimise and bring back
    row = e.screen()[e.h - 1]
    bx = row.find(" Shell") + 2
    e.click(bx, e.h)
    check(e.find("lua") is None or "Phoenix OS Shell" not in text(e), "clicking the active taskbar button minimises")
    e.click(bx, e.h)
    check(e.find(" Shell") == (x, y), "clicking it again restores")

    # sandbox: a program can't reach the real globals or write outside its window
    e.type("lua")
    e.key("enter")
    e.type("term.native() == term.current(), phoenix.user()")
    e.key("enter")
    check("true" in text(e), "term.native() is the program's own window")
    e.type("exit()")
    e.key("enter")

    # close with the X
    e.click(x + 34, y, settle=0.3)  # resized to 36 wide, so the X is at +33..+35
    check(" Shell" not in e.screen()[e.h - 1], "the close button closes the window")

    # ---- settings: change desktop colour, it persists
    menu(e, "Settings")
    check("Edition" in text(e), "Settings opens")
    shot(e, "09_settings")
    p = e.find("Personalise")
    e.click(p[0], p[1], settle=0.3)
    p = e.find("Desktop colour")
    e.click(p[0] + 10, p[1] + 2)  # blue swatch (row 2, 4th)
    shot(e, "10_personalise")
    cfg = os.path.join(root, "usr", "aaron", ".config", "phoenix.cfg")
    check(os.path.isfile(cfg) and "desktop.colour" in open(cfg).read(), "desktop colour is saved per user")
    p = e.find(" Users")
    e.click(p[0] + 1, p[1], settle=0.3)
    check("aaron  (administrator)" in text(e), "Users page lists accounts")
    # add a standard user through the dialogs
    p = e.find(" Add ")
    e.click(p[0] + 1, p[1], settle=0.3)
    e.type("olivia")
    e.key("enter", settle=0.3)
    e.type("pw123")
    e.key("enter", settle=0.3)
    check("administrator?" in text(e), "add-user asks about administrator rights")
    shot(e, "11_add_user")
    e.key("enter", settle=0.5)  # default button: No
    check("olivia" in text(e), "new user appears in the list")

    # ---- task manager
    menu(e, "Tasks")
    e.run(1.2)
    check("Settings" in text(e) and "Tasks" in text(e) and "running" in text(e), "Tasks lists running programs")
    shot(e, "12_tasks")

    # ---- editor (CraftOS edit in a window)
    menu(e, "Editor")
    check("File to open or create" in text(e), "Editor asks for a file name")
    e.key("enter", settle=0.5)
    e.type("Hello from Phoenix OS")
    check("Hello from Phoenix OS" in text(e) and "untitled.txt - Editor" in text(e), "typing in the editor works")
    shot(e, "13_editor")
    e.key("leftCtrl")
    e.key("enter", settle=0.3)  # Save
    saved = os.path.join(root, "usr", "aaron", "documents", "untitled.txt")
    check(os.path.isfile(saved) and "Hello from Phoenix OS" in open(saved).read(), "editor saves into the user's documents")
    e.click(e.w - 1, 1, settle=0.3)

    # ---- a crashing program shows an error window and gets logged
    with open(os.path.join(root, "usr", "aaron", "documents", "boom.lua"), "w") as f:
        f.write('print("about to fail")\nerror("kaboom", 0)\n')
    with open(os.path.join(root, "usr", "aaron", "documents", "hello.lua"), "w") as f:
        f.write('print("Hello, " .. phoenix.user())\n')
    menu(e, "Files")
    check(e.find("aaron - Files"), "Files opens from the Start menu")
    p = e.find("documents")
    e.double_click(p[0] + 1, p[1], settle=0.3)
    p = e.find("boom.lua")
    check(p, "Files shows the new scripts")
    e.click(p[0], p[1])
    p = e.find(" Run ")
    e.click(p[0] + 1, p[1], settle=0.5)
    check("stopped working" in text(e) and "kaboom" in text(e), "a crash shows an error window")
    shot(e, "14_crash")
    p = e.find(" OK ")
    e.click(p[0] + 1, p[1], settle=0.3)
    check("kaboom" in open(os.path.join(root, "etc", "events.log")).read(), "the crash is in the event log")
    p = e.find("hello.lua")
    e.click(p[0], p[1])
    p = e.find(" Run ")
    e.click(p[0] + 1, p[1], settle=0.5)
    check("Hello, aaron" in text(e) and "Press any key to close" in text(e), "running a script opens it in its own window")
    e.key("space", settle=0.3)

    # ---- lock and unlock (programs stay open)
    menu(e, "Lock")
    check("Locked" in text(e) and "Unlock" in text(e), "Lock shows the lock screen")
    shot(e, "15_locked")
    e.type("wrong")
    e.key("enter", settle=0.5)
    check("Wrong password" in text(e), "wrong password is refused")
    e.type("hunter2")
    e.key("enter", settle=0.5)
    check(desktop(e) and "Setting" in e.screen()[e.h - 1], "unlocking returns to the desktop with windows intact")

    # ---- sign out, sign in as the standard user
    menu(e, "Sign out")
    check("Sign in" in text(e), "Sign out returns to the sign-in screen")
    shot(e, "16_sign_in")
    e.type("olivia")
    e.key("enter")
    e.type("bad")
    e.key("enter", settle=0.5)
    check("Wrong username or password" in text(e), "bad sign-in is refused")
    e.key("tab")  # focus is on password; go round to username via the buttons
    e.key("tab")
    e.key("tab")
    e.key("tab")
    for _ in range(10):
        e.key("backspace", settle=0.01)
    sign_in(e, "olivia", "pw123")
    check(desktop(e), "standard user reaches the desktop")
    e.click(3, e.h)
    check("olivia" in text(e) and "(admin)" not in text(e), "Start menu shows a standard user")
    e.click(40, 5)

    menu(e, "Shell")
    e.type("ls /")
    e.key("enter")
    scr = text(e)
    check("system" not in scr and "etc" not in scr and "usr" in scr, "standard user can't see /system or /etc")
    e.type("ls /usr")
    e.key("enter")
    check("aaron" not in "\n".join(e.screen()[-6:]).replace("olivia", ""), "nor other users' home folders")
    e.type("lua")
    e.key("enter")
    e.type("fs.open('/etc/users.db','r')")
    e.key("enter")
    check("Access denied" in text(e), "reading the account database is denied")
    e.type("fs.open('/startup.lua','w')")
    e.key("enter")
    e.type("pcall(fs.delete, '/system')")
    e.key("enter")
    check(text(e).count("Access denied") >= 3, "writing to system files is denied")
    e.type("select(2, phoenix.users.add('evil','x',true))")
    e.key("enter")
    check("Administrator rights needed" in text(e), "standard user can't add accounts")
    e.type("io.open('/tmp/a.txt','w'):write('hi'):close() return fs.exists('/tmp/a.txt')")
    e.key("enter")
    check(any(r.strip("# ") == "true" for r in e.screen()), "but can write to /tmp and their own folder")
    shot(e, "17_standard_user")
    check(os.path.isfile(os.path.join(root, "startup.lua")) and os.path.isdir(os.path.join(root, "system")), "system files untouched")

    # ---- restart from the Start menu comes back to sign-in
    e.type("exit()")
    e.key("enter")
    boots = e.E.boots or 0
    menu(e, "Restart")
    e.run(3)
    check((e.E.boots or 0) == boots + 1 and "Sign in" in text(e), "Restart reboots to the sign-in screen")
    sign_in(e, "aaron", "hunter2")
    check(desktop(e), "administrator signs in after reboot")
    shot(e, "18_after_reboot")
    menu(e, "Shut down")
    e.run(1)
    check(not e.powered, "Shut down turns the computer off")

    # ---- the one-line installer, on a blank computer, served from this repo
    blank = os.path.join(tmp, "blank")
    os.makedirs(blank)
    e = Emu(LUA, blank, http_dir=REPO, http_prefix="https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/")
    e.boot()
    e.run(1)
    e.type("wget run https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/install.lua")
    e.key("enter", settle=1)
    check("Install Phoenix OS" in text(e) and "Cancel" in text(e), "installer asks before installing")
    shot(e, "19_installer_confirm")
    e.key("enter", settle=0.5)
    check("of 22 files" in text(e), "installer shows a progress bar with a file count")
    check("Phoenix OS" in text(e) and "installed" in text(e), "installer downloads everything")
    shot(e, "19_installer")
    e.run(5)
    check("Create the administrator account" in text(e), "and restarts into first-run setup")

    # ---- updating: publish a "newer" build and update from the shell
    remote = os.path.join(tmp, "remote")
    shutil.copytree(REPO, remote, ignore=shutil.ignore_patterns(".git", "tools", "shots"))
    os.makedirs(os.path.join(remote, "apps", "hello"))
    with open(os.path.join(remote, "apps", "hello", "app.cfg"), "w") as f:
        f.write('{ name = "Hello", order = 99 }\n')
    with open(os.path.join(remote, "apps", "hello", "main.lua"), "w") as f:
        f.write('print("hi")\n')
    manifest = open(os.path.join(REPO, "manifest.txt")).read()
    manifest = manifest.replace("# build = ", "# build = new") + "apps/hello/app.cfg\napps/hello/main.lua\n"
    with open(os.path.join(remote, "manifest.txt"), "w") as f:
        f.write(manifest)
    # pretend the installed version had a file that's since been removed
    os.makedirs(os.path.join(blank, "apps", "old"))
    with open(os.path.join(blank, "apps", "old", "main.lua"), "w") as f:
        f.write("-- old\n")
    with open(os.path.join(blank, "system", "manifest.txt"), "a") as f:
        f.write("apps/old/main.lua\n")

    e = Emu(LUA, blank, http_dir=remote, http_prefix="https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/")
    e.boot()
    e.run(2)
    e.type("admin")
    e.key("enter")
    e.type("pw")
    e.key("enter")
    e.type("pw")
    e.key("enter", settle=1)
    check("Update available" not in text(e), "no update notification straight away")
    e.run(4)
    check("Update available" in text(e) and "ready to" in text(e), "update notification appears after an admin signs in")
    shot(e, "20_update_notification")
    p = e.find(" Later ")
    e.click(p[0] + 1, p[1], settle=0.3)
    check("Update available" not in text(e), "Later closes the notification")
    # sign out and back in: it asks again, and Update goes to Settings ready to install
    menu(e, "Sign out")
    sign_in(e, "admin", "pw")
    e.run(4)
    check("Update available" in text(e), "the notification comes back at the next sign-in")
    p = e.find(" Update   Later ")  # the button row, not the "Update available" title
    e.click(p[0] + 2, p[1], settle=1)
    check("Install 0.1" in text(e) and "restarts afterwards" in text(e), "Update opens Settings and asks to install")
    shot(e, "21_update_from_notification")
    p = e.find(" Cancel ")
    e.click(p[0] + 1, p[1], settle=0.3)
    check("An update is available" in text(e), "cancelling leaves Settings on the Updates page")
    menu(e, "Shell")
    e.type("update")
    e.key("enter", settle=1)
    check("Available:" in text(e) and "Install it and restart?" in text(e), "shell update finds the new build")
    shot(e, "22_update_shell")
    e.type("y")
    e.key("enter", settle=1)
    check("Updated. Restarting" in text(e), "update downloads and installs")
    boots = e.E.boots or 0
    e.run(4)
    check((e.E.boots or 0) == boots + 1 and "Sign in" in text(e), "and restarts")
    check(os.path.isfile(os.path.join(blank, "apps", "hello", "main.lua")), "new files arrive")
    check(not os.path.exists(os.path.join(blank, "apps", "old", "main.lua")), "files dropped from the OS are removed")
    check("# build = new" in open(os.path.join(blank, "system", "manifest.txt")).read(), "installed build is recorded")
    check(os.path.isfile(os.path.join(blank, "etc", "users.db")), "accounts survive the update")
    sign_in(e, "admin", "pw")
    menu(e, "Settings")
    p = e.find("Updates")
    e.click(p[0], p[1], settle=0.3)
    check("[x] Check when I sign in" in text(e), "automatic update check is on by default")
    p = e.find(" Check   Update ")  # the button, not the tick-box
    e.click(p[0] + 2, p[1], settle=1)
    check("up to date" in text(e), "Settings says it's up to date after updating")
    shot(e, "23_update_settings")

    log = open(os.path.join(root, "etc", "events.log")).read()
    check("aaron signed in" in log and "Failed sign-in" in log and "Shutting down" in log, "event log records sign-ins and power")
    used = os.path.getsize(os.path.join(REPO, "startup.lua")) + sum(
        os.path.getsize(os.path.join(base, f))
        for item in ("system", "lib", "apps") for base, _dirs, files in os.walk(os.path.join(REPO, item)) for f in files)
    print(f"all {passed} checks passed; Phoenix OS takes {used / 1024:.0f} KB of the computer's 976 KB")
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
