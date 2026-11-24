#!/usr/bin/env python3
"""Rebuild manifest.txt (the installer's and updater's file list).

Run this before every commit that changes the OS. The version comes from
system/boot.lua; the build is a fingerprint of every file, so it changes
whenever anything does and computers see it as an update.
"""
import hashlib
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = ["startup.lua"]
for top in ("system", "lib", "apps"):
    for base, dirs, names in os.walk(os.path.join(REPO, top)):
        dirs.sort()
        for name in sorted(names):
            files.append(os.path.relpath(os.path.join(base, name), REPO).replace(os.sep, "/"))

digest = hashlib.sha256()
for path in files:
    digest.update(path.encode() + b"\0")
    with open(os.path.join(REPO, path), "rb") as f:
        digest.update(f.read() + b"\0")
with open(os.path.join(REPO, "system", "boot.lua")) as f:
    version = re.search(r'local VERSION = "([^"]+)"', f.read()).group(1)

with open(os.path.join(REPO, "manifest.txt"), "w") as f:
    f.write("# Files the installer and updater download. Rebuild with: python3 tools/mkmanifest.py\n")
    f.write(f"# version = {version}\n# build = {digest.hexdigest()[:16]}\n")
    f.write("\n".join(files) + "\n")
print(f"{len(files)} files, version {version}, build {digest.hexdigest()[:16]}")
