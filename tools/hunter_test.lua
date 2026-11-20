-- Offline tests for the Hunter indicators with mocked client APIs.
-- Usage: luajit hunter_test.lua <repo root>
local root = arg[1]

local mt = {}
local function stub() return setmetatable({}, mt) end
RESTRICTED = false
mt.__index = function(_, k)
    if RESTRICTED and (k == "GetLeft" or k == "GetBottom") then
        return function() error("Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
    end
    return function() return stub() end
end
function CreateFrame() return stub() end
UIParent = stub()
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
wipe = function(t) for k in pairs(t) do t[k] = nil end end
date = os.date
local NOW = 1000
GetTime = function() return NOW end

-- World ------------------------------------------------------------------------
local W
BFA_MODULE = nil
local function reset()
    NOW, GUID = 1000, "G1"
    if BFA_MODULE and BFA_MODULE.ResetTracking then BFA_MODULE.ResetTracking() end
    W = { known = { [1130] = true, [13165] = true, [883] = true }, inv = {}, invCount = {}, itemCount = {},
          buffs = {}, debuffs = {}, pet = nil }
end
reset()
local ITEMS = {
    bow = { "i", 2, 2 }, gun = { "i", 2, 3 }, xbow = { "i", 2, 18 }, wand = { "i", 2, 19 }, unknownWeapon = nil,
    arrow = { "arrowicon", 6, 2 }, bullet = { "bulleticon", 6, 3 },
}
local SPELLS = { [1130] = "Hunter's Mark", [14323] = "Hunter's Mark", [13165] = "Aspect of the Hawk",
    [5118] = "Aspect of the Cheetah", [883] = "Call Pet", [75] = "Auto Shot" }
local GUID = "G1"
function UnitGUID() return GUID end
function IsPlayerSpell(id) return W.known[id] or false end
function GetSpellInfo(id) local n = SPELLS[id] if not n then return nil end return n, nil, "icon" .. id end
function GetInventoryItemID(_, slot) return W.inv[slot] end
function GetInventoryItemCount(_, slot) return W.invCount[slot] end
function GetItemCount(id) return W.itemCount[id] end
function GetItemInfoInstant(id) local t = ITEMS[id] if not t then return nil end return id, "x", "y", "z", t[1], t[2], t[3] end
local function aura(list, i)
    local a = list[i]
    if not a then return nil end
    return a.name, a.icon or "auraicon", 1, "magic", a.duration or 0, a.expires or 0, a.source
end
function UnitBuff(_, i)
    if W.aurasHidden then error("Auras cannot be accessed when secret while tainted") end
    return aura(W.buffs, i)
end
function UnitDebuff(_, i)
    if W.aurasHidden then error("Auras cannot be accessed when secret while tainted") end
    return aura(W.debuffs, i)
end
function UnitExists(u) return u ~= "pet" or W.pet ~= nil end
function UnitIsDead() return W.pet and W.pet.dead or false end
function UnitHealth() return W.pet and W.pet.hp or 0 end
function UnitHealthMax() return W.pet and W.pet.max or 0 end
function UnitName() return "Boar" end
function GetPetHappiness() return W.pet and W.pet.happy end

-- Secret values: any arithmetic or comparison raises an error, like the client does during combat.
local SECRET = setmetatable({}, {
    __add = function() error("attempt to perform arithmetic on a secret number value") end,
    __sub = function() error("attempt to perform arithmetic on a secret number value") end,
    __mul = function() error("attempt to perform arithmetic on a secret number value") end,
    __div = function() error("attempt to perform arithmetic on a secret number value") end,
    __lt = function() error("attempt to compare a secret number value") end,
    __le = function() error("attempt to compare a secret number value") end,
})
function issecretvalue(v) return v == SECRET end

-- Load -----------------------------------------------------------------------------
local BFA = {}
local function load(path, ...) return assert(loadfile(path))(...) end
load(root .. "/BajtFightAssist/Log.lua", "BajtFightAssist", BFA)
load(root .. "/BajtFightAssist/Core.lua", "BajtFightAssist", BFA)
load(root .. "/BajtFightAssist/Range.lua", "BajtFightAssist", BFA)
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
load(root .. "/BajtFightAssist_Hunter/Hunter.lua", "BajtFightAssist_Hunter", {})

BFA_MODULE = BFA.modules.Hunter
local ind = {}
for _, e in ipairs(BFA.indicators) do ind[e.def.id] = e.def.Update end

local fails = 0
local function expect(name, id, state, text)
    local s, _, t = ind[id]("target")
    local ok = s == state and t == text
    print((ok and "PASS " or "FAIL ") .. name .. " -> " .. tostring(s) .. " " .. tostring(t) ..
        (ok and "" or ("   expected " .. tostring(state) .. " " .. tostring(text))))
    if not ok then fails = fails + 1 end
end

-- Ammo ---------------------------------------------------------------------------------
reset(); expect("ammo: no ranged weapon", "ammo", nil, nil)
reset(); W.inv[18] = "wand"; expect("ammo: wand needs none", "ammo", nil, nil)
reset(); W.inv[18] = "unknownWeapon"; expect("ammo: unknown weapon info hides", "ammo", nil, nil)
reset(); W.inv[18] = "bow"; expect("ammo: bow without ammo", "ammo", "bad", "0")
reset(); W.inv[18] = "bow"; W.inv[0] = "bullet"; W.invCount[0] = 400; expect("ammo: bullets with a bow", "ammo", "bad", "!")
reset(); W.inv[18] = "gun"; W.inv[0] = "arrow"; W.invCount[0] = 400; expect("ammo: arrows with a gun", "ammo", "bad", "!")
reset(); W.inv[18] = "bow"; W.inv[0] = "arrow"; W.invCount[0] = 1200; expect("ammo: 1200 arrows", "ammo", "ok", "1.2k")
reset(); W.inv[18] = "xbow"; W.inv[0] = "arrow"; W.invCount[0] = 120; expect("ammo: 120 arrows warn", "ammo", "warn", "120")
reset(); W.inv[18] = "gun"; W.inv[0] = "bullet"; W.invCount[0] = 30; expect("ammo: 30 bullets bad", "ammo", "bad", "30")
reset(); W.inv[18] = "gun"; W.inv[0] = "bullet"; W.invCount[0] = 400; expect("ammo: 400 bullets ok", "ammo", "ok", "400")
reset(); W.inv[18] = "bow"; W.inv[0] = "arrow"; expect("ammo: count unknown hides", "ammo", nil, nil)

-- Hunter's Mark -----------------------------------------------------------------------------
reset(); W.known[1130] = false; expect("mark: spell not known", "mark", nil, nil)
reset(); expect("mark: missing", "mark", "warn", nil)
reset(); W.debuffs = { { name = "Hunter's Mark" } }; expect("mark: present, no duration from client", "mark", "ok", nil)
reset(); W.debuffs = { { name = "Sunder Armor" }, { name = "Hunter's Mark", duration = 120, expires = 1102 } }
expect("mark: present with remaining time", "mark", "ok", "1:42")

reset(); W.aurasHidden = true; expect("mark: auras hidden in combat", "mark", nil, nil)
reset(); W.debuffs = { { name = "Hunter's Mark", duration = SECRET, expires = SECRET } }
expect("mark: present, time is secret", "mark", "ok", nil)
reset(); W.debuffs = { { name = SECRET } }; expect("mark: secret aura name is unknown", "mark", nil, nil)

-- Aspect ----------------------------------------------------------------------------------------
reset(); W.known[13165] = false; expect("aspect: none learned", "aspect", nil, nil)
reset(); expect("aspect: none active", "aspect", "warn", "!")
reset(); W.buffs = { { name = "Mark of the Wild" }, { name = "Aspect of the Hawk" } }; expect("aspect: hawk active", "aspect", "ok", nil)

reset(); W.aurasHidden = true; expect("aspect: auras hidden in combat", "aspect", nil, nil)

-- Pet ---------------------------------------------------------------------------------------------
reset(); W.known[883] = false; expect("pet: no Call Pet", "pet", nil, nil)
reset(); expect("pet: missing", "pet", "warn", "!")
reset(); W.pet = { dead = true }; expect("pet: dead", "pet", "bad", "X")
reset(); W.pet = { hp = 100, max = 100 }; expect("pet: alive, no percentage", "pet", "ok", nil)
reset(); W.pet = { hp = SECRET, max = 100 }; expect("pet: secret health does not matter", "pet", "ok", nil)



-- Tracking from your own casts (auras are hidden in combat) ---------------------------------------------------
local function cast(id) BFA_MODULE.OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cg", id) end
local function peek(id) local st, _, tx, tip = ind[id]("target") return st, tx, tip end
local function expectState(name, id, state)
    local st = peek(id)
    local ok = st == state
    print((ok and "PASS " or "FAIL ") .. name .. " -> " .. tostring(st) .. (ok and "" or ("   expected " .. tostring(state))))
    if not ok then fails = fails + 1 end
end

reset(); W.aurasHidden = true; expectState("track: never observed, hidden in combat", "mark", nil)
reset(); expectState("track: absent seen out of combat", "mark", "warn")
W.aurasHidden = true; expectState("track: absent seen, then combat: still warn", "mark", "warn")
cast(1130); expectState("track: cast in combat marks the target", "mark", "ok")
GUID = "G2"; expectState("track: another target is unknown", "mark", nil)
GUID = "G1"; expectState("track: back on the marked target", "mark", "ok")
NOW = 1000 + 121; expectState("track: mark expires after the tracked duration", "mark", "warn")
reset(); W.debuffs = { { name = "Hunter's Mark" } }; expectState("track: mark seen on target", "mark", "ok")
W.aurasHidden = true; expectState("track: seen mark stays after combat starts", "mark", "ok")
reset(); expectState("track: absent seen", "mark", "warn")
cast(14323); expectState("track: cast of a higher rank counts", "mark", "ok")
NOW = 1001; expectState("track: aura not visible yet right after the cast", "mark", "ok")
NOW = 1010; expectState("track: aura still missing 10 s later corrects the tracking", "mark", "warn")
reset(); GUID = SECRET; W.aurasHidden = true; expectState("track: secret guid is unknown", "mark", nil)

reset(); expectState("track: aspect none seen", "aspect", "warn")
W.aurasHidden = true; cast(5118); expectState("track: aspect cast in combat", "aspect", "ok")
BFA_MODULE.OnEvent("PLAYER_DEAD"); expectState("track: death clears the tracked aspect", "aspect", nil)
reset(); W.buffs = { { name = "Aspect of the Hawk" } }; expectState("track: aspect seen", "aspect", "ok")
W.aurasHidden = true; expectState("track: seen aspect stays in combat", "aspect", "ok")

-- Smoke test of the display code with stub frames: must not raise errors.
load(root .. "/BajtFightAssist/UI.lua", "BajtFightAssist", BFA)
local okUI, errUI = pcall(function()
    BFA.UI.ShowIndicators({ { state = "ok", icon = "i", text = "1.2k", tip = "t", plate = true }, { state = "warn" }, { state = "bad", text = "X" } })
    BFA.UI.ShowIndicators({})
    BFA.UI.HideIndicators()
    BFA.UI.ApplyBadge(BFA.UI.badges.target, "CLOSE", "MELEE ATTACK", "icon")
    BFA.UI.Float("FAR")
end)
print((okUI and "PASS " or "FAIL ") .. "UI smoke test" .. (okUI and "" or (": " .. tostring(errUI))))
if not okUI then fails = fails + 1 end

-- Frames anchored to a nameplate are restricted regions: measuring them raises an error, which must not escape.
RESTRICTED = true
BFA.UI.lastRowSig = nil
local okR, errR = pcall(function()
    BFA.UI.ShowIndicators({ { state = "ok", icon = "i", text = "1.2k", plate = true }, { state = "warn" } })
end)
RESTRICTED = false
print((okR and "PASS " or "FAIL ") .. "restricted regions are not measured in a way that breaks the display" ..
    (okR and "" or (": " .. tostring(errR))))
if not okR then fails = fails + 1 end

if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("ALL PASS (hunter indicators)")
