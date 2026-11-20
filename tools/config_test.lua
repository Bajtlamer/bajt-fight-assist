-- Offline tests for the configuration logic, the window build, the minimap button and the layout migration.
-- Usage: luajit config_test.lua <repo root>
local root = arg[1]

local mt = {}
local function stub() return setmetatable({}, mt) end
mt.__index = function() return function() return stub() end end
function CreateFrame() return stub() end
UIParent = stub()
Minimap = setmetatable({ GetWidth = function() return 140 end, GetCenter = function() return 50, 50 end,
    GetEffectiveScale = function() return 1 end }, mt)
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
wipe = function(t) for k in pairs(t) do t[k] = nil end end
date = os.date
GetTime = function() return 1000 end
function GetCursorPosition() return 100, 100 end
function IsPlayerSpell() return false end
function GetSpellInfo() return nil end

local fails = 0
local function check(cond, text)
    print((cond and "PASS " or "FAIL ") .. text)
    if not cond then fails = fails + 1 end
end

local BFA = {}
local function load(path, ...) return assert(loadfile(path))(...) end
-- An old saved layout from before layout version 2
BajtFightAssistDB = { rowX = 24, rowY = -3 }
for _, f in ipairs({ "Log", "Core", "Range", "UI", "Driver", "Loader", "Config", "Minimap", "Settings" }) do
    load(root .. "/BajtFightAssist/" .. f .. ".lua", "BajtFightAssist", BFA)
end
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
local db = BFA.db

check(db.rowX == 4 and db.layout == 2, "old row offset 24 is replaced by the aligned default 4")
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
db.rowX = 10
-- the migration must run only once: a value the player chose later survives
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
check(db.rowX == 10, "a player-chosen row offset survives the next load")

load(root .. "/BajtFightAssist_Hunter/Hunter.lua", "BajtFightAssist_Hunter", {})

-- Indicator choices
local def = BFA.indicators[1].def
local key = BFA.indicators[1].module .. "." .. def.id
check(BFA:IndicatorOnPlate(key, { onPlate = true }) == true, "module default: on nameplate")
check(BFA:IndicatorOnPlate(key, { onPlate = false }) == false, "module default: not on nameplate")
BFA.Config.SetPlate(key, false)
check(BFA:IndicatorOnPlate(key, { onPlate = true }) == false, "player choice beats the module default (off)")
BFA.Config.SetPlate(key, true)
check(BFA:IndicatorOnPlate(key, { onPlate = false }) == true, "player choice beats the module default (on)")
BFA.Config.SetIndicator(key, false)
check(db.indicators[key] == false, "indicator switched off")
BFA.Config.SetIndicator(key, true)
check(db.indicators[key] == true, "indicator switched on")

-- Anchor cycling
db.anchor = "both"
local seen = {}
for _ = 1, 4 do seen[#seen + 1] = BFA.Config.CycleAnchor() end
check(table.concat(seen, ",") == "target,nameplate,screen,both", "anchor cycles through all four modes and returns to start")

-- Minimap
BFA.Config.SetMinimapShown(false)
check(db.minimap.hide == true, "minimap button hidden by the setting")
BFA.Config.SetMinimapShown(true)
check(db.minimap.hide == false, "minimap button shown by the setting")

-- Layout reset
db.scale, db.rowX = 2, 99
BFA.Config.ResetLayout()
check(db.scale == 1 and db.rowX == 4, "reset layout restores the defaults")

-- Window build and minimap button creation must not raise errors
local okW, errW = pcall(function() BFA.Config.Show() BFA.Config.Toggle() BFA.Config.Toggle() end)
check(okW, "configuration window builds and toggles" .. (okW and "" or (": " .. tostring(errW))))
local okM, errM = pcall(function() BFA.Minimap.Create() BFA.Minimap.Refresh() end)
check(okM, "minimap button creates" .. (okM and "" or (": " .. tostring(errM))))

-- Slash command opens the window without error
local okS, errS = pcall(function() SlashCmdList["BAJTFIGHTASSIST"]("") SlashCmdList["BAJTFIGHTASSIST"]("row 10 -5") end)
check(okS and db.rowX == 10 and db.rowY == -5, "/bfa opens the window and /bfa row sets the offsets" ..
    (okS and "" or (": " .. tostring(errS))))

if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("ALL PASS (config)")
