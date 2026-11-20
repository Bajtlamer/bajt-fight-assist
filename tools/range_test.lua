-- Offline tests for the range engine. Runs the new core (Log, Core, Range + Hunter module) on scenarios taken
-- from real client logs, and compares it with the old Target Ranger 0.1.16 when that repository is next to this one.
-- Usage: luajit range_test.lua <repo root>
local root = arg[1]
local oldPath = root .. "/../target-ranger/TargetRanger/Core.lua"

-- WoW API stubs ------------------------------------------------------------
local mt = {}
local function stub() return setmetatable({}, mt) end
mt.__index = function() return function() return stub() end end
function CreateFrame() return stub() end
UIParent = stub()
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
wipe = function(t) for k in pairs(t) do t[k] = nil end end
date = os.date
GetTime = os.clock

local W = { known = {}, spells = {}, interact = {}, items = {} }
local SPELLDB = {
    [75] = { "Auto Shot", 8, 35 }, [3044] = { "Arcane Shot", 8, 35 }, [1978] = { "Serpent Sting", 8, 35 },
    [5116] = { "Concussive Shot", 8, 35 }, [1130] = { "Hunter's Mark", 0, 100 }, [20736] = { "Distracting Shot", 8, 35 },
}
function GetSpellInfo(id)
    local s = SPELLDB[id]
    if not s then return nil end
    return s[1], nil, "icon", 0, s[2], s[3], id
end
function IsPlayerSpell(id) return W.known[id] or false end
function IsSpellInRange(name)
    local v = W.spells[name]
    if v == nil then return nil end
    return v and 1 or 0
end
function CheckInteractDistance(_, idx) return W.interact[idx] and true or false end
function IsItemInRange(id) local v = W.items[id]; if v == nil then return nil end return v and 1 or 0 end

-- Load the implementations ----------------------------------------------------
local function load(path, ...) return assert(loadfile(path))(...) end

local BFA = {}
load(root .. "/BajtFightAssist/Log.lua", "BajtFightAssist", BFA)
load(root .. "/BajtFightAssist/Core.lua", "BajtFightAssist", BFA)
load(root .. "/BajtFightAssist/Range.lua", "BajtFightAssist", BFA)
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
load(root .. "/BajtFightAssist_Hunter/Hunter.lua", "BajtFightAssist_Hunter", {})

local haveOld = io.open(oldPath, "r") ~= nil
if haveOld then load(oldPath) end

local function newMeasure()
    BFA.Range.Rebuild()
    local s, label, bracket, ranged = BFA.Range.Measure("target")
    return { s, label, bracket, ranged }
end
local function oldMeasure()
    TargetRanger.Rebuild()
    local s, _, label, bracket, ranged = TargetRanger.Measure("target")
    return { s, label, bracket, ranged }
end
local function fmt(r) return table.concat({ tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]) }, " | ") end

-- Scenarios -----------------------------------------------------------------------
local HUNTER = { 75, 3044, 1978, 5116, 1130, 20736 }
local RANGE_SPELLS = { "Auto Shot", "Arcane Shot", "Serpent Sting", "Concussive Shot", "Distracting Shot" }
local function items(v) return { [835] = v, [7734] = v, [18904] = v } end
local function hunter(auto, mark, interact, it)
    local sp = { ["Hunter's Mark"] = mark }
    for _, n in ipairs(RANGE_SPELLS) do sp[n] = auto end
    return { known = HUNTER, spells = sp, interact = interact, items = it }
end
local NONE = { [3] = false, [2] = false, [4] = false }
local I28 = { [3] = false, [2] = false, [4] = true }
local ALL = { [3] = true, [2] = true, [4] = true }

local scenarios = {
    { "hunter in range 8-28", hunter(true, true, I28, items(true)), { "IN", "IN RANGE", "8-28 yd", true } },
    { "hunter in range 8-30", hunter(true, true, NONE, items(true)), { "IN", "IN RANGE", "8-30 yd", true } },
    { "hunter in range 30-35", hunter(true, true, NONE, { [835] = false, [7734] = false, [18904] = true }),
        { "IN", "IN RANGE", "30-35 yd", true } },
    { "hunter far", hunter(false, true, NONE, items(false)), { "FAR", "OUT OF RANGE", "35-100 yd", true } },
    { "hunter too close", hunter(false, true, ALL, items(true)), { "CLOSE", "MELEE ATTACK", "<= 8 yd", true } },
    { "hunter too close, interact flicker", hunter(false, true, I28, items(true)),
        { "CLOSE", "MELEE ATTACK", "<= 8 yd", true } },
    { "hunter contradiction", hunter(true, true, { [3] = false, [2] = false, [4] = true },
        { [835] = false, [7734] = false, [18904] = true }), {} },
    { "no ranged, melee distance", { known = {}, spells = {}, interact = ALL, items = items(true) },
        { "IN", "FIGHT RANGE", "<= 10 yd", false } },
    { "no ranged, far", { known = {}, spells = {}, interact = NONE, items = items(false) },
        { "FAR", "OUT OF REACH", "> 35 yd", false } },
    { "no ranged, mid", { known = {}, spells = {}, interact = I28, items = items(true) },
        { "FAR", "OUT OF REACH", "<= 28 yd", false } },
    -- Intentional difference: with only negative interact answers the old version claimed "FAR > 0 yd" (seen 144 times
    -- in the logs). Nothing positive is known, so the new core says nothing.
    { "hunter, primary silent, only interact negatives", hunter(nil, nil, NONE, {}), {}, true },
}

local fails = 0
for _, sc in ipairs(scenarios) do
    local name, world, expect, intentional = sc[1], sc[2], sc[3], sc[4]
    W.known = {}
    for _, id in ipairs(world.known) do W.known[id] = true end
    W.spells, W.interact, W.items = world.spells, world.interact, world.items
    local n = newMeasure()
    local want = fmt({ expect[1], expect[2], expect[3], expect[4] })
    local ok = fmt(n) == want
    local line = (ok and "PASS " or "FAIL ") .. name .. " -> " .. fmt(n)
    if not ok then fails = fails + 1 line = line .. "   expected " .. want end
    if haveOld then
        local o = oldMeasure()
        if fmt(o) ~= fmt(n) then
            if intentional then
                line = line .. "   (differs from 0.1.16 on purpose: " .. fmt(o) .. ")"
            else
                fails = fails + 1
                line = line .. "   FAIL parity with 0.1.16: " .. fmt(o)
            end
        end
    end
    print(line)
end

-- Exploration probes are logged but never change the state ------------------------------------------
BFA:RegisterModule("Explorer", { apiVersion = 1, explore = { { id = 75 } } })
W.known = {}
for _, id in ipairs(HUNTER) do W.known[id] = true end
W.spells, W.interact, W.items = hunter(true, true, I28, items(true)).spells, I28, items(true)
W.spells["Auto Shot"] = true
BFA.Range.Rebuild()
local withExplore = fmt({ BFA.Range.Measure("target") })
W.spells["Auto Shot"] = false
BFA.Range.Rebuild()
local dump = BFA.Range.ProbeDump("target")
print((dump:find("x:Auto Shot=out", 1, true) and "PASS " or "FAIL ") .. "exploration probe appears in the probe dump: " .. dump:sub(-40))
if not dump:find("x:Auto Shot=out", 1, true) then fails = fails + 1 end
local stateIn = BFA.Range.Measure("target")
print((withExplore:find("IN", 1, true) and "PASS " or "FAIL ") .. "state unaffected by exploration probes (in range stays in range)")
if not withExplore:find("IN", 1, true) then fails = fails + 1 end

-- Module API ----------------------------------------------------------------------
local function check(cond, text)
    print((cond and "PASS " or "FAIL ") .. text)
    if not cond then fails = fails + 1 end
end
check(BFA.modules.Hunter ~= nil, "Hunter module registered")
check(BFA:RegisterModule("Bad", { apiVersion = 99 }) == false, "module with wrong api version refused")
check(BFA.modules.Bad == nil, "refused module not stored")
check(BFA:RegisterModule("Hunter", { apiVersion = 1 }) == false, "duplicate module refused")
BFA:RegisterModule("Test", { apiVersion = 1, indicators = {
    { id = "b", order = 20, Update = function() return "ok" end },
    { id = "a", order = 10, Update = function() return nil end },
} })
local pos = {}
for i, e in ipairs(BFA.indicators) do pos[e.module .. "." .. e.def.id] = i end
check(pos["Test.a"] and pos["Test.b"] and pos["Test.a"] < pos["Test.b"], "indicators sorted by order")

print(haveOld and "(parity with 0.1.16 checked)" or "(old target-ranger not found, parity skipped)")
if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("ALL PASS")
