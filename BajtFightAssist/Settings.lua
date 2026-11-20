-- Bajt's Fight Assist: slash commands. Every output also goes to the log (BFA:Say).
local ADDON, BFA = ...

local function Debug()
    local R, D = BFA.Range, BFA.Driver
    if not UnitExists("target") then BFA:Say("No target.") return end
    BFA:Say(string.format("player=%s faction=%s race=%s canAttack=%s eligible=%s", tostring(UnitIsPlayer("target")),
        tostring(UnitFactionGroup("target")), tostring((select(2, UnitRace("target")))),
        tostring(UnitCanAttack("player", "target")), tostring(D.Eligible("target"))))
    BFA:Say("Log lines stored: " .. (BFA.db.logLines and #BFA.db.logLines or 0) .. ". Use /reload to flush them to disk.")
    for _, c in ipairs(R.checkers) do
        local r = c.test("target")
        BFA:Say(string.format("%s api=%s-%s used=%s-%s primary=%s -> %s", c.name, tostring(c.apiMin), tostring(c.apiMax),
            tostring(c.min), tostring(c.max), tostring(c.primary or false), r == nil and "n/a" or (r and "in" or "out")))
    end
    local s, sub, br, ranged = R.Measure("target")
    if not s then BFA:Say("Result: unknown (no usable answer, badge hidden)") else
        BFA:Say(string.format("Result: %s [%s] %s ranged=%s", s, br, sub, tostring(ranged)))
    end
    BFA:Say("Items: " .. R.ItemDump("target"))
    for _, entry in ipairs(BFA.indicators) do
        local ok, state, _, text = pcall(entry.def.Update, "target")
        BFA:Say(string.format("Indicator %s.%s: %s", entry.module, entry.def.id,
            ok and (state and (state .. " " .. tostring(text)) or "hidden (unknown)") or ("error " .. tostring(state))))
    end
end

SLASH_BAJTFIGHTASSIST1 = "/bfa"
SlashCmdList["BAJTFIGHTASSIST"] = function(msg)
    local db = BFA.db
    if not db then return end
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        BFA:Say("Addon " .. cmd)
    elseif cmd == "anchor" and (arg == "target" or arg == "nameplate" or arg == "both" or arg == "screen") then
        db.anchor = arg
        BFA:Say("Anchor: " .. arg)
    elseif cmd == "text" and (arg == "on" or arg == "off") then
        db.floatingText = (arg == "on")
        BFA:Say("Floating text " .. arg)
    elseif cmd == "scale" and tonumber(arg) then
        db.scale = math.max(0.5, math.min(3, tonumber(arg)))
        BFA:Say("Scale: " .. db.scale)
    elseif cmd == "npc" and (arg == "on" or arg == "off") then
        db.npcs = (arg == "on")
        BFA:Say("NPC targets " .. (db.npcs and "tracked" or "ignored"))
    elseif cmd == "sameside" and (arg == "on" or arg == "off") then
        db.sameSide = (arg == "on")
        BFA:Say("Same faction or race players " .. (db.sameSide and "tracked" or "ignored"))
    elseif cmd == "bg" and (arg == "on" or arg == "off") then
        db.inBattleground = (arg == "on")
        BFA:Say("Battlegrounds: addon " .. (db.inBattleground and "active" or "disabled"))
    elseif cmd == "log" and (arg == "on" or arg == "off" or arg == "clear") then
        if arg == "clear" then db.logLines = {} else db.log = (arg == "on") end
        BFA:Say("Log " .. arg .. ". Entries are written to disk on /reload or logout.")
    elseif cmd == "mark" then
        local R = BFA.Range
        local state, sub, bracket
        if UnitExists("target") then state, sub, bracket = R.Measure("target") end
        BFA:Log("MARK", "user reports the badge is wrong now: " .. tostring(state) .. " " .. tostring(bracket) .. " | " ..
            (UnitExists("target") and R.ProbeDump("target") or "no target"))
        BFA:Say("Marked in the log. Use /reload later to write it to disk.")
    elseif cmd == "indicator" then
        -- /bfa indicator Hunter.ammo off
        local key, onoff = arg:match("^(%S+)%s+(%S+)$")
        if key and (onoff == "on" or onoff == "off") then
            db.indicators[key] = (onoff == "on") and true or false
            BFA:Say("Indicator " .. key .. " " .. onoff)
        else
            BFA:Say("/bfa indicator <Module.id> on|off")
        end
    elseif cmd == "row" then
        local x, y = arg:match("^(-?%d+%.?%d*)%s+(-?%d+%.?%d*)$")
        if x then
            db.rowX, db.rowY = tonumber(x), tonumber(y)
            BFA:Say(string.format("Indicator row offset: %s, %s", x, y))
        else
            BFA:Say(string.format("Indicator row offset is %s, %s. Usage: /bfa row X Y (X right, Y up; default 24 -3)",
                tostring(db.rowX), tostring(db.rowY)))
        end
    elseif cmd == "modules" then
        BFA:Say("Core " .. BFA.version .. " api " .. BFA.API_VERSION .. ", modules: " ..
            (#BFA.moduleOrder > 0 and table.concat(BFA.moduleOrder, ", ") or "none"))
        for _, entry in ipairs(BFA.indicators) do BFA:Say("  indicator " .. entry.module .. "." .. entry.def.id) end
    elseif cmd == "unlock" then
        db.locked = false
        db.anchor = "screen"
        BFA.UI.badges.screen:EnableMouse(true)
        BFA:Say("Screen badge unlocked. Drag it, then type /bfa lock. Use /bfa test to see it.")
    elseif cmd == "lock" then
        db.locked = true
        BFA.UI.badges.screen:EnableMouse(false)
        BFA:Say("Locked.")
    elseif cmd == "scan" then
        BFA.Range.StartScan()
    elseif cmd == "test" then
        BFA.Driver.StartTest()
        BFA:Say("Test sequence running.")
    elseif cmd == "debug" then
        Debug()
    elseif cmd == "reset" then
        for k, v in pairs(BFA.DEFAULTS) do
            if type(v) == "table" then db[k] = { unpack(v) } else db[k] = v end
        end
        BFA.UI.PlaceScreenBadge()
        BFA:Say("Settings reset.")
    else
        BFA:Say("/bfa on|off | anchor target|nameplate|both|screen | text on|off | mark | log on|off|clear | npc on|off | sameside on|off | bg on|off | indicator <Module.id> on|off | row X Y | modules | scan | scale N | unlock | lock | test | debug | reset")
    end
end
