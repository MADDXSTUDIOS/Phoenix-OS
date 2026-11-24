-- Phoenix OS starts here. The real boot code is /system/boot.lua.
if fs.exists("/system/boot.lua") then
    shell.run("/system/boot.lua")
else
    printError("Phoenix OS: /system/boot.lua is missing. Run the installer again.")
end
