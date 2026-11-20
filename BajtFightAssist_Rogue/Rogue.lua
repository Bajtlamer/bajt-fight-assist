-- Bajt's Fight Assist: Rogue module.
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

---------------------------------------------------------------------------
-- Poisons on the weapons and combo points
---------------------------------------------------------------------------
local MAIN_HAND, OFF_HAND, POISONS, EVISCERATE = 16, 17, 2842, 2098
local FALLBACK_ICON = "Interface\\Icons\\INV_Weapon_ShortBlade_01"
local COMBO_ICON = "Interface\\Icons\\Ability_Rogue_Eviscerate"
local expiresAt = {} -- slot -> GetTime() when the poison runs out, from the last readable value

local function IsSecret(v) return v ~= nil and issecretvalue and issecretvalue(v) or false end

local function KnowsPoisons()
    return (IsPlayerSpell and IsPlayerSpell(POISONS)) or (IsSpellKnown and IsSpellKnown(POISONS)) or false
end

local function Duration(seconds)
    if seconds >= 3600 then return string.format("%dh", seconds / 3600) end
    if seconds >= 60 then return string.format("%dm", seconds / 60) end
    return string.format("%ds", math.max(seconds, 0))
end

-- Indicator for the poison on one weapon: time left as text, the weapon as icon. During combat the client may hide
-- the values: then the last readable expiry keeps counting on our own clock.
local function PoisonUpdate(slot)
    if not (GetInventoryItemID and GetInventoryItemID("player", slot)) then return nil end
    local hand = slot == MAIN_HAND and "Main hand" or "Off hand"
    local icon = (GetInventoryItemTexture and GetInventoryItemTexture("player", slot)) or FALLBACK_ICON
    local ok, hasMain, mainExp, mainCharges, _, hasOff, offExp, offCharges = pcall(GetWeaponEnchantInfo)
    local has, exp, charges = hasMain, mainExp, mainCharges
    if slot == OFF_HAND then has, exp, charges = hasOff, offExp, offCharges end
    local readable = ok and not IsSecret(has) and not IsSecret(exp)
    if readable then
        expiresAt[slot] = (has and type(exp) == "number") and (GetTime() + exp / 1000) or nil
    end
    local remaining = expiresAt[slot] and (expiresAt[slot] - GetTime()) or nil
    if remaining == nil or remaining <= 0 then
        -- no poison (or it ran out): say so only for a Rogue who has learned Poisons; unknown while the values are hidden
        if (readable or remaining ~= nil) and KnowsPoisons() then return "bad", icon, "!", hand .. ": no poison" end
        return nil
    end
    local state = remaining > 300 and "ok" or (remaining >= 60 and "warn" or "bad")
    local tip = string.format("%s poison: %s left", hand, Duration(remaining))
    if type(charges) == "number" and not IsSecret(charges) and charges > 0 then tip = tip .. string.format(", %d charges", charges) end
    return state, icon, Duration(remaining), tip
end

local function ComboUpdate(unit)
    if not GetComboPoints then return nil end
    local ok, points = pcall(GetComboPoints, "player", unit)
    if not ok or IsSecret(points) or type(points) ~= "number" or points <= 0 then return nil end
    local icon = COMBO_ICON
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(EVISCERATE)
        if info and info.iconID then icon = info.iconID end
    elseif GetSpellInfo then
        local _, _, spellIcon = GetSpellInfo(EVISCERATE)
        if spellIcon then icon = spellIcon end
    end
    return points >= 5 and "warn" or "ok", icon, tostring(points), string.format("%d combo points", points)
end

BFA:RegisterModule("Rogue", {
    apiVersion = 1,
    -- Throw is the ranged attack: the badge says THROW IN RANGE while it reaches the target, MELEE ATTACK when the target
    -- is closer than its minimum range and OUT OF RANGE beyond it. Range 5-30 yd is the fallback when the client gives none
    -- (the minimum is not confirmed: the log shows Throw "in" only from about 8 yd and "out" at 30-35 yd).
    ranged = {
        { id = 2764, primary = true, fmin = 5, fmax = 30, label = "THROW IN RANGE", closeTone = "IN" },
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
        { id = "poisonMain", title = "Main hand poison", order = 10, Update = function() return PoisonUpdate(MAIN_HAND) end },
        { id = "poisonOff", title = "Off hand poison", order = 20, Update = function() return PoisonUpdate(OFF_HAND) end },
        { id = "combo", title = "Combo points", order = 30, onPlate = true, Update = ComboUpdate },
        { id = "diag", title = "Diagnostics (hidden)", order = 1000, Update = Diagnose },
    },
})
