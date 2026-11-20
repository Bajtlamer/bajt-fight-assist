-- Offline tests for the Hunter indicators with mocked client APIs.
-- Usage: luajit hunter_test.lua <repo root>
local root = arg[1]

local mt = {}
local function stub() return setmetatable({}, mt) end
mt.__index = function() return function() return stub() end end
function CreateFrame() return stub() end
UIParent = stub()
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
wipe = function(t) for k in pairs(t) do t[k] = nil end end
date = os.date
GetTime = function() return 1000 end

-- World ------------------------------------------------------------------------
local W
local function reset()
    W = { known = { [1130] = true, [13165] = true, [883] = true }, inv = {}, invCount = {}, itemCount = {},
          buffs = {}, debuffs = {}, pet = nil }
end
reset()
local ITEMS = {
    bow = { "i", 2, 2 }, gun = { "i", 2, 3 }, xbow = { "i", 2, 18 }, wand = { "i", 2, 19 }, unknownWeapon = nil,
    arrow = { "arrowicon", 6, 2 }, bullet = { "bulleticon", 6, 3 },
}
local SPELLS = { [1130] = "Hunter's Mark", [13165] = "Aspect of the Hawk", [883] = "Call Pet" }
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
function UnitBuff(_, i) return aura(W.buffs, i) end
function UnitDebuff(_, i) return aura(W.debuffs, i) end
function UnitExists(u) return u ~= "pet" or W.pet ~= nil end
function UnitIsDead() return W.pet and W.pet.dead or false end
function UnitHealth() return W.pet and W.pet.hp or 0 end
function UnitHealthMax() return W.pet and W.pet.max or 0 end
function UnitName() return "Boar" end
function GetPetHappiness() return W.pet and W.pet.happy end

-- Load -----------------------------------------------------------------------------
local BFA = {}
local function load(path, ...) return assert(loadfile(path))(...) end
load(root .. "/BajtFightAssist/Log.lua", "BajtFightAssist", BFA)
load(root .. "/BajtFightAssist/Core.lua", "BajtFightAssist", BFA)
load(root .. "/BajtFightAssist/Range.lua", "BajtFightAssist", BFA)
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
load(root .. "/BajtFightAssist_Hunter/Hunter.lua", "BajtFightAssist_Hunter", {})

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

-- Aspect ----------------------------------------------------------------------------------------
reset(); W.known[13165] = false; expect("aspect: none learned", "aspect", nil, nil)
reset(); expect("aspect: none active", "aspect", "warn", "!")
reset(); W.buffs = { { name = "Mark of the Wild" }, { name = "Aspect of the Hawk" } }; expect("aspect: hawk active", "aspect", "ok", nil)

-- Pet ---------------------------------------------------------------------------------------------
reset(); W.known[883] = false; expect("pet: no Call Pet", "pet", nil, nil)
reset(); expect("pet: missing", "pet", "warn", "!")
reset(); W.pet = { dead = true }; expect("pet: dead", "pet", "bad", "X")
reset(); W.pet = { hp = 100, max = 100, happy = 3 }; expect("pet: healthy", "pet", "ok", "100%")
reset(); W.pet = { hp = 20, max = 100, happy = 3 }; expect("pet: low health", "pet", "warn", "20%")
reset(); W.pet = { hp = 100, max = 100, happy = 1 }; expect("pet: unhappy", "pet", "bad", "100%")
reset(); W.pet = { hp = 50, max = 100 }; expect("pet: happiness unknown still shown", "pet", "ok", "50%")

-- Smoke test of the display code with stub frames: must not raise errors.
load(root .. "/BajtFightAssist/UI.lua", "BajtFightAssist", BFA)
local okUI, errUI = pcall(function()
    BFA.UI.ShowIndicators({ { state = "ok", icon = "i", text = "1.2k", tip = "t" }, { state = "warn" }, { state = "bad", text = "X" } })
    BFA.UI.ShowIndicators({})
    BFA.UI.HideIndicators()
    BFA.UI.ApplyBadge(BFA.UI.badges.target, "CLOSE", "MELEE ATTACK", "icon")
    BFA.UI.Float("FAR")
end)
print((okUI and "PASS " or "FAIL ") .. "UI smoke test" .. (okUI and "" or (": " .. tostring(errUI))))
if not okUI then fails = fails + 1 end

if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("ALL PASS (hunter indicators)")
