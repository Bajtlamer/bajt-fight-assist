-- Bajt's Fight Assist: Hunter module.
-- The addon vararg table is private to each addon, so the shared core is reached through its global.
local BFA = _G.BajtFightAssist

local function Log(text) BFA:Log("Hunter", text) end
local last = {}
-- Log raw values only when they change, so the log shows what the client really returned.
local function LogChange(key, text)
    if last[key] ~= text then
        last[key] = text
        Log(key .. " raw: " .. text)
    end
end

---------------------------------------------------------------------------
-- API helpers (Classic and newer clients)
---------------------------------------------------------------------------
local function Known(id)
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

local function SpellNameIcon(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C_Spell.GetSpellInfo(id)
        if i then return i.name, i.iconID end
        return nil
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(id)
        return name, icon
    end
end

local function ItemInfo(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return nil end
    local _, _, _, _, icon, classID, subClassID = fn(id)
    return icon, classID, subClassID
end

-- Returns name, icon, duration, expirationTime, source of aura number index, or nil at the end of the list.
local function Aura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not a then return nil end
        return a.name, a.icon, a.duration, a.expirationTime, a.sourceUnit
    end
    local fn = (filter == "HARMFUL") and UnitDebuff or UnitBuff
    local name, icon, _, _, duration, expirationTime, source = fn(unit, index)
    return name, icon, duration, expirationTime, source
end

local function FindAura(unit, filter, wanted)
    for i = 1, 40 do
        local name, icon, duration, expirationTime, source = Aura(unit, i, filter)
        if not name then return nil end
        if wanted(name) then return name, icon, duration, expirationTime, source end
    end
end

local function Short(n)
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Ammo: the ammo slot against the ranged weapon in hand
---------------------------------------------------------------------------
local AMMO_SLOT, RANGED_SLOT = 0, 18
-- weapon class 2: subclass 2 bow, 3 gun, 18 crossbow. Projectile class 6: subclass 2 arrow, 3 bullet.
local NEEDS = { [2] = { 2, "arrows" }, [18] = { 2, "arrows" }, [3] = { 3, "bullets" } }
local AMMO_FALLBACK = { arrows = "Interface\\Icons\\INV_Misc_Ammo_Arrow_01", bullets = "Interface\\Icons\\INV_Misc_Ammo_Bullet_01" }

local function AmmoUpdate()
    local db = BFA.modules.Hunter.db
    local weaponId = GetInventoryItemID and GetInventoryItemID("player", RANGED_SLOT)
    if not weaponId then return nil end
    local _, wClass, wSub = ItemInfo(weaponId)
    local need = wClass == 2 and NEEDS[wSub]
    if not need then return nil end -- thrown weapon, wand or not yet known: no ammo to watch

    local ammoId = GetInventoryItemID("player", AMMO_SLOT)
    local inv = GetInventoryItemCount and GetInventoryItemCount("player", AMMO_SLOT)
    local bag = ammoId and GetItemCount and GetItemCount(ammoId)
    LogChange("ammo", string.format("weapon=%s sub=%s ammo=%s slotCount=%s bagCount=%s", tostring(weaponId),
        tostring(wSub), tostring(ammoId), tostring(inv), tostring(bag)))
    if not ammoId then
        return "bad", AMMO_FALLBACK[need[2]], "0", "No ammo equipped (" .. need[2] .. ")"
    end
    local icon, aClass, aSub = ItemInfo(ammoId)
    if aClass == 6 and aSub ~= need[1] then
        return "bad", icon, "!", "Equipped ammo does not fit your ranged weapon (needs " .. need[2] .. ")"
    end
    if not inv then return nil end
    local state = "ok"
    if inv < db.ammoBad then state = "bad" elseif inv < db.ammoWarn then state = "warn" end
    return state, icon, Short(inv), string.format("%d %s", inv, need[2])
end

---------------------------------------------------------------------------
-- Hunter's Mark on the target
---------------------------------------------------------------------------
local MARK = 1130
local function MarkUpdate(unit)
    if not Known(MARK) then return nil end
    local markName, markIcon = SpellNameIcon(MARK)
    if not markName then return nil end
    local name, icon, duration, expires, source = FindAura(unit, "HARMFUL", function(n) return n == markName end)
    if not name then
        return "warn", markIcon, nil, "Hunter's Mark is not on the target"
    end
    LogChange("mark", string.format("duration=%s expires=%s source=%s", tostring(duration), tostring(expires), tostring(source)))
    local text
    -- Classic often reports no duration for other units: show a time only when the client gives one.
    if duration and duration > 0 and expires and expires > 0 then
        local left = math.max(0, math.floor(expires - GetTime() + 0.5))
        text = string.format("%d:%02d", math.floor(left / 60), left % 60)
    end
    return "ok", icon or markIcon, text, "Hunter's Mark is on the target"
end

---------------------------------------------------------------------------
-- Aspect
---------------------------------------------------------------------------
local ASPECT_IDS = { 13165, 13163, 5118, 13161, 20043, 13159 } -- Hawk, Monkey, Cheetah, Beast, Wild, Pack
local function AspectUpdate()
    if not Known(13165) then return nil end -- no aspects learned yet
    local names = {}
    for _, id in ipairs(ASPECT_IDS) do
        local n = SpellNameIcon(id)
        if n then names[n] = true end
    end
    local name, icon = FindAura("player", "HELPFUL", function(n) return names[n] end)
    if name then
        LogChange("aspect", name)
        return "ok", icon, nil, name
    end
    LogChange("aspect", "none")
    local _, hawkIcon = SpellNameIcon(13165)
    return "warn", hawkIcon, "!", "No aspect active"
end

---------------------------------------------------------------------------
-- Pet
---------------------------------------------------------------------------
local CALL_PET = 883
local function PetUpdate()
    if not Known(CALL_PET) then return nil end
    local _, icon = SpellNameIcon(CALL_PET)
    if not UnitExists("pet") then
        LogChange("pet", "missing")
        return "warn", icon, "!", "No pet summoned"
    end
    if UnitIsDead("pet") then
        LogChange("pet", "dead")
        return "bad", icon, "X", "Pet is dead"
    end
    local happy = GetPetHappiness and GetPetHappiness()
    local maxHp = UnitHealthMax("pet")
    local hp = maxHp and maxHp > 0 and math.floor(UnitHealth("pet") / maxHp * 100 + 0.5) or nil
    LogChange("pet", string.format("alive hp=%s happiness=%s", tostring(hp), tostring(happy)))
    if happy == 1 then return "bad", icon, hp and (hp .. "%") or nil, "Pet is unhappy" end
    local state = (hp and hp < 30) and "warn" or "ok"
    local tip = (UnitName("pet") or "Pet") .. (hp and (", health " .. hp .. "%") or "")
    return state, icon, hp and (hp .. "%") or nil, tip
end

BFA:RegisterModule("Hunter", {
    apiVersion = 1,
    defaults = { ammoWarn = 200, ammoBad = 50 },
    -- Spell probes for range. primary = the attack the state is judged against (first known wins).
    -- Melee spells are deliberately not probed: their range check reported "in range" at any distance on this client.
    ranged = {
        { id = 75, primary = true, fmin = 5, fmax = 35 },   -- Auto Shot
        { id = 3044, primary = true, fmin = 5, fmax = 35 }, -- Arcane Shot
        { id = 1978, primary = true, fmin = 5, fmax = 35 }, -- Serpent Sting
        { id = 5116, fmin = 5, fmax = 35 },                 -- Concussive Shot
        { id = 1130, fmin = 0, fmax = 100 },                -- Hunter's Mark
        { id = 1513 },                                      -- Scare Beast
        { id = 19503 },                                     -- Scatter Shot
        { id = 20736 },                                     -- Distracting Shot
    },
    -- Update returns state ("ok"|"warn"|"bad"), icon, short text, tooltip; nil hides the indicator (unknown or irrelevant).
    indicators = {
        { id = "ammo", order = 10, Update = AmmoUpdate },
        { id = "mark", order = 20, Update = MarkUpdate },
        { id = "aspect", order = 30, Update = AspectUpdate },
        { id = "pet", order = 40, Update = PetUpdate },
    },
})
