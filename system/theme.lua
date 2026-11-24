-- Phoenix OS look: palette and the colors each part of the desktop uses.
local c = colors
return {
    -- The 16 colors, retuned a little. Each stays "itself" so normal CC programs still look right.
    palette = {
        [c.white] = 0xF4F5F7, [c.orange] = 0xEE7A1C, [c.magenta] = 0xD95FC7, [c.lightBlue] = 0xBFE3EA,
        [c.yellow] = 0xF2C744, [c.lime] = 0x6CC644, [c.pink] = 0xF5A9C8, [c.gray] = 0x3B4252,
        [c.lightGray] = 0xB4BAC4, [c.cyan] = 0x1F8A9E, [c.purple] = 0x9B59D0, [c.blue] = 0x2563C9,
        [c.brown] = 0x7A5A3C, [c.green] = 0x3E9B4F, [c.red] = 0xD64541, [c.black] = 0x15171C,
    },
    desktop = c.cyan,
    desktopText = c.lightBlue,
    titleActive = c.blue,
    titleActiveText = c.white,
    titleInactive = c.gray,
    titleInactiveText = c.lightGray,
    frame = c.lightGray,
    close = c.red,
    taskbar = c.gray,
    taskbarText = c.white,
    start = c.orange,
    startText = c.white,
    menu = c.white,
    menuText = c.black,
    select = c.blue,
    selectText = c.white,
}
