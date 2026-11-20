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
GetTime = function() return 1000 end

local SECRET = setmetatable({}, { __add = function() error("secret") end })
function issecretvalue(v) return v == SECRET end
local mode = "normal"
function IsStealthed() return true end
function GetComboPoints() if mode == "error" then error("combo restricted") end return 3 end
function GetWeaponEnchantInfo() if mode == "secret" then return SECRET, SECRET end return true, 1800000, 85, 7, false end
function UnitCreatureType() return "Humanoid" end
function UnitAffectingCombat() return false end
function IsUsableSpell() return true, false end
function GetInventoryItemID(_, slot) return 1000 + slot end
function IsPlayerSpell() return false end
function GetSpellInfo() return nil end

local BFA = {}
local function load(path, ...) return assert(loadfile(path))(...) end
for _, f in ipairs({ "Log", "Core", "Range" }) do load(root .. "/BajtFightAssist/" .. f .. ".lua", "BajtFightAssist", BFA) end
BFA.OnEvent("ADDON_LOADED", "BajtFightAssist")
load(root .. "/BajtFightAssist_Rogue/Rogue.lua", "BajtFightAssist_Rogue", {})

local fails = 0
local function check(cond, text) print((cond and "PASS " or "FAIL ") .. text) if not cond then fails = fails + 1 end end

check(BFA.modules.Rogue ~= nil, "Rogue module registered")
local diag = BFA.indicators[1].def.Update
for _, m in ipairs({ "normal", "secret", "error" }) do
    mode = m
    local ok, a, b, c, d = pcall(diag, "target")
    check(ok and a == nil, "diagnostics never show an indicator and do not raise errors (" .. m .. ")")
end
local text = table.concat(BFA.db.logLines or {}, "\n")
check(text:find("diag raw:", 1, true) ~= nil, "raw values are written to the log")
check(text:find("weaponEnchant=true/1800000/85/7/false", 1, true) ~= nil, "weapon enchant values are logged")
check(text:find("combo=error", 1, true) ~= nil, "a failing API is logged as error")
check(text:find("weaponEnchant=secret/secret", 1, true) ~= nil, "secret values are logged as secret")

if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("ALL PASS (rogue exploration)")
