-- Bajt's Fight Assist: Rogue module, exploration build.
-- The range badge uses Throw. The module also logs what the client reports for the things a Rogue wants to watch
-- (range probes, poisons, Sap, Pick Pocket, combo points) so that reliable sources can be chosen from the log.
local BFA = _G.BajtFightAssist

local function Log(text) BFA:Log("Rogue", text) end
local last = {}
local function LogChange(key, text)
    if last[key] ~= text then
        last[key] = text
        Log(key .. " raw: " .. text)
    end
end

-- A secret value is unknown to us (combat restrictions).
local function Readable(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return "secret" end
    return v
end
local function Raw(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then return "error" end
    local out = {}
    for i = 2, #r do out[#out + 1] = tostring(Readable(r[i])) end
    return #out > 0 and table.concat(out, "/") or "nil"
end

local function Usable(spell)
    if C_Spell and C_Spell.IsSpellUsable then return Raw(C_Spell.IsSpellUsable, spell) end
    if IsUsableSpell then return Raw(IsUsableSpell, spell) end
    return "n/a"
end

local SAP, PICK_POCKET, STEALTH = 6770, 921, 1784

-- Hidden indicator: it only logs. Runs every 0.25 s while an attackable target exists.
local function Diagnose(unit)
    local parts = {}
    parts[#parts + 1] = "stealth=" .. Raw(IsStealthed or function() return "n/a" end)
    parts[#parts + 1] = "combo=" .. Raw(GetComboPoints or function() return "n/a" end, "player", unit)
    parts[#parts + 1] = "weaponEnchant=" .. Raw(GetWeaponEnchantInfo or function() return "n/a" end)
    parts[#parts + 1] = "creature=" .. Raw(UnitCreatureType, unit)
    parts[#parts + 1] = "targetInCombat=" .. Raw(UnitAffectingCombat, unit)
    parts[#parts + 1] = "playerInCombat=" .. Raw(UnitAffectingCombat, "player")
    parts[#parts + 1] = "sapUsable=" .. Usable(SAP)
    parts[#parts + 1] = "pickPocketUsable=" .. Usable(PICK_POCKET)
    parts[#parts + 1] = "mainHand=" .. Raw(GetInventoryItemID or function() return "n/a" end, "player", 16)
    parts[#parts + 1] = "offHand=" .. Raw(GetInventoryItemID or function() return "n/a" end, "player", 17)
    parts[#parts + 1] = "ranged=" .. Raw(GetInventoryItemID or function() return "n/a" end, "player", 18)
    LogChange("diag", table.concat(parts, " "))
    return nil
end

BFA:RegisterModule("Rogue", {
    apiVersion = 1,
    -- Throw is the ranged attack: the badge says THROW IN RANGE while it reaches the target, MELEE ATTACK when the target
    -- is closer than its minimum range and OUT OF RANGE beyond it. Range 5-30 yd is the fallback when the client gives none
    -- (the minimum is not confirmed: the log shows Throw "in" only from about 8 yd and "out" at 30-35 yd).
    ranged = {
        { id = 2764, primary = true, fmin = 5, fmax = 30, label = "THROW IN RANGE" },
    },
    -- Exploration probes: logged as x:<spell> in every range sample, never used for the state.
    explore = {
        { id = 1752 }, -- Sinister Strike (melee)
        { id = 53 },   -- Backstab (melee)
        { id = 1776 }, -- Gouge (melee)
        { id = 1766 }, -- Kick (melee)
        { id = 1833 }, -- Cheap Shot (melee)
        { id = 703 },  -- Garrote (melee)
        { id = 921 },  -- Pick Pocket
        { id = 6770 }, -- Sap
        { id = 2480 }, -- Shoot Bow
        { id = 7918 }, -- Shoot Gun
        { id = 7919 }, -- Shoot Crossbow
    },
    indicators = {
        { id = "diag", title = "Diagnostics (hidden)", order = 1000, Update = Diagnose },
    },
})
