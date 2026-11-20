-- Offline test of the Rogue exploration module: it must log, never show anything and never raise errors.
-- Usage: luajit rogue_test.lua <repo root>
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
local NOW = 1000
GetTime = function() return NOW end

local SECRET = setmetatable({}, { __add = function() error("secret") end })
function issecretvalue(v) return v == SECRET end
local mode = "normal"
local W = { poison = { true, 1800000, 0, 7, false }, combo = 3, known = {} }
function IsStealthed() return true end
function GetComboPoints() if mode == "error" then error("combo restricted") end return W.combo end
function GetWeaponEnchantInfo() if mode == "secret" then return SECRET, SECRET end return unpack(W.poison) end
function GetInventoryItemTexture(_, slot) return "tex" .. slot end
function UnitCreatureType() return "Humanoid" end
function UnitAffectingCombat() return false end
function IsUsableSpell() return true, false end
function GetInventoryItemID(_, slot) return 1000 + slot end
function IsPlayerSpell(id) return W.known[id] or false end
function GetSpellInfo() return nil end

local BFA = {}
local function load(path, ...) return assert(loadfile(path))(...) end
for _, f in ipairs({ "Log", "Core", "Range" }) do load(root .. "/BajtFightAssist/" .. f .. ".lua", "BajtFightAssist", BFA) end
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
load(root .. "/BajtFightAssist_Rogue/Rogue.lua", "BajtFightAssist_Rogue", {})

local fails = 0
local function check(cond, text) print((cond and "PASS " or "FAIL ") .. text) if not cond then fails = fails + 1 end end

check(BFA.modules.Rogue ~= nil, "Rogue module registered")
local throw = BFA.modules.Rogue.ranged[1]
check(throw and throw.id == 2764 and throw.primary, "Throw is the primary ranged attack")
check(throw and throw.label == "THROW IN RANGE", "the badge says THROW IN RANGE while Throw reaches the target")
local byId = {}
for _, e in ipairs(BFA.indicators) do byId[e.def.id] = e.def end
local diag = byId.diag.Update
for _, m in ipairs({ "normal", "secret", "error" }) do
    mode = m
    local ok, a, b, c, d = pcall(diag, "target")
    check(ok and a == nil, "diagnostics never show an indicator and do not raise errors (" .. m .. ")")
end
local text = table.concat(BFA.db.logLines or {}, "\n")
check(text:find("diag raw:", 1, true) ~= nil, "raw values are written to the log")
check(text:find("weaponEnchant=true/1800000/0/7/false", 1, true) ~= nil, "weapon enchant values are logged")
check(text:find("combo=error", 1, true) ~= nil, "a failing API is logged as error")
check(text:find("weaponEnchant=secret/secret", 1, true) ~= nil, "secret values are logged as secret")

-- Poison timers on the weapons ------------------------------------------------------------------
mode = "normal"
local function ind(id) return byId[id] and byId[id].Update("target") end
local function full(id) if not byId[id] then return nil end return byId[id].Update("target") end
check(byId.poisonMain ~= nil and byId.poisonOff ~= nil and byId.combo ~= nil, "poison and combo point indicators are registered")
local st, icon, text = full("poisonMain")
check(st == "ok" and icon == "tex16" and text == "30m", "main hand poison with 30 min left: ok, weapon icon, 30m")
W.poison = { true, 200000, 0, 7, true, 45000, 0, 8 }
st, icon, text = full("poisonMain"); check(st == "warn" and text == "3m", "under 5 minutes warns")
st, icon, text = full("poisonOff"); check(st == "bad" and icon == "tex17" and text == "45s", "off hand under 1 minute is bad and counts seconds")
W.poison = { true, 5400000, 0, 7, false }
st, icon, text = full("poisonMain"); check(text == "1h", "an hour or more shows hours")
W.poison = { false, nil, nil, nil, false }
st, icon, text = full("poisonMain"); check(st == nil, "no poison and poisons not learned: hidden")
W.known[2842] = true
st, icon, text = full("poisonMain"); check(st == "bad" and text == "!", "no poison although Poisons is learned: bad")
GetInventoryItemID_old = GetInventoryItemID
function GetInventoryItemID(_, slot) if slot == 17 then return nil end return 1000 + slot end
st = full("poisonOff"); check(st == nil, "no off hand weapon: nothing for the off hand")
GetInventoryItemID = GetInventoryItemID_old
-- Secret values in combat: the last readable expiry keeps counting on our own clock.
W.poison = { true, 100000, 0, 7, false }
full("poisonMain")
mode = "secret"; NOW = NOW + 30
st, icon, text = full("poisonMain"); check(st == "warn" and text == "1m", "secret values: expiry counted from the last readable value (70 s left)")
NOW = NOW + 80
st, icon, text = full("poisonMain"); check(st == "bad" and text == "!", "secret values: expired on our clock reads bad")
mode = "normal"

check(byId.combo.onPlate == true, "combo points are also shown next to the nameplate")
check(not byId.poisonMain.onPlate and not byId.poisonOff.onPlate, "poison timers stay out of the nameplate")

-- Combo points ----------------------------------------------------------------------------------
W.combo = 3
st, icon, text = full("combo"); check(st == "ok" and text == "3", "3 combo points: ok, number 3")
W.combo = 5
st, icon, text = full("combo"); check(st == "warn" and text == "5", "5 combo points: warn, spend them")
W.combo = 0
st = full("combo"); check(st == nil, "no combo points: hidden")
mode = "error"
local okc, stc = pcall(byId.combo.Update, "target"); check(okc and stc == nil, "a failing combo point API hides the indicator")
mode = "normal"

if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("ALL PASS (rogue exploration)")
