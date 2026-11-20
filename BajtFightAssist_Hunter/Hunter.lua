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
-- During combat the client hides some values from addons ("secret values"). A secret value is unknown to us.
local function Readable(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Calls fn; returns ok, results. Not ok when the call raised an error (for example secret aura data).
local function Try(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then return false end
    for i = 2, #r do r[i] = Readable(r[i]) end
    return true, unpack(r, 2)
end

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
local function RawAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not a then return nil end
        return a.name, a.icon, a.duration, a.expirationTime, a.sourceUnit
    end
    local fn = (filter == "HARMFUL") and UnitDebuff or UnitBuff
    local name, icon, _, _, duration, expirationTime, source = fn(unit, index)
    return name, icon, duration, expirationTime, source
end

-- Returns readable, name, icon, duration, expirationTime, source. readable is false when the client hides
-- the auras (combat restrictions): then nothing is known. name is nil when the aura is simply not there.
local function FindAura(unit, filter, wanted)
    for i = 1, 40 do
        local ok, name, icon, duration, expirationTime, source = Try(RawAura, unit, i, filter)
        if not ok then return false end
        if name == nil then
            -- end of the list, or a secret name: only the end of the list proves the aura is absent
            local ok2, probe = pcall(RawAura, unit, i, filter)
            if ok2 and probe == nil then return true end
            return false
        end
        if wanted(name) then return true, name, icon, duration, expirationTime, source end
    end
    return true
end

-- Diagnostics: what the client says about secrecy (logged when it changes, nothing here drives the display).
local function Secrecy()
    local C = C_Secrets
    if type(C) ~= "table" then return "no C_Secrets" end
    local function call(name, ...)
        local f = C[name]
        if type(f) ~= "function" then return "n/a" end
        local ok, r = pcall(f, ...)
        return ok and tostring(r) or "err"
    end
    return string.format("restrictions=%s aurasSecret=%s markAura=%s hawkAura=%s auraIndex=%s petHealthMax=%s identity=%s",
        call("HasSecretRestrictions"), call("ShouldAurasBeSecret"), call("GetSpellAuraSecrecy", 1130),
        call("GetSpellAuraSecrecy", 13165), call("ShouldUnitAuraIndexBeSecret", "target", 1),
        call("ShouldUnitHealthMaxBeSecret", "pet"), call("ShouldUnitIdentityBeSecret", "target"))
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
-- Tracking from your own casts. During combat the client hides auras from addons, so the state of Hunter's Mark
-- and of the aspect is kept from what was seen when auras were readable and from your own successful casts.
-- trackedMarks[guid] = { marked = bool, at = time, expires = time|nil, src = "cast"|"seen"|"expired" }
-- trackedAspect = { name, icon, src } (an aspect), false (seen: none) or nil (never observed: unknown)
---------------------------------------------------------------------------
-- Hunter's Mark: instant, 100 yd, "Lasts for 2 min" (spellbook tooltip of Rank 1, so markDuration defaults to 120 s;
-- higher ranks are not confirmed, the log line "mark gone N s after the cast" will show it).
local MARK = 1130
local ASPECT_IDS = { 13165, 13163, 5118, 13161, 20043, 13159 } -- Hawk, Monkey, Cheetah, Beast, Wild, Pack
local trackedMarks = {}
local trackedAspect

local function TargetGuid(unit)
    local ok, g = Try(UnitGUID, unit)
    return ok and g or nil
end

local function MarkName()
    return (SpellNameIcon(MARK))
end

local function AspectNames()
    local names = {}
    for _, id in ipairs(ASPECT_IDS) do
        local n = SpellNameIcon(id)
        if n then names[n] = true end
    end
    return names
end

local function Prune(now)
    local n = 0
    for _ in pairs(trackedMarks) do n = n + 1 end
    if n < 60 then return end
    for guid, t in pairs(trackedMarks) do
        if t.expires and now > t.expires + 60 then trackedMarks[guid] = nil end
    end
end

-- Called for every successful cast of the player.
local function OnCast(spellID)
    local name, icon = SpellNameIcon(spellID)
    if not name then return end
    local now = GetTime()
    if name == MarkName() then
        local guid = TargetGuid("target")
        local db = BFA.modules.Hunter.db
        Log(string.format("cast Hunter's Mark spell=%s guid=%s", tostring(spellID), tostring(guid)))
        if guid then
            Prune(now)
            trackedMarks[guid] = { marked = true, at = now, expires = now + db.markDuration, src = "cast" }
        end
    elseif AspectNames()[name] then
        Log(string.format("cast aspect %s spell=%s", name, tostring(spellID)))
        trackedAspect = { name = name, icon = icon, src = "cast" }
    end
end

---------------------------------------------------------------------------
-- Hunter's Mark on the target
---------------------------------------------------------------------------
local function MarkUpdate(unit)
    if not Known(MARK) then return nil end
    local markName, markIcon = SpellNameIcon(MARK)
    if not markName then return nil end
    local now = GetTime()
    local guid = TargetGuid(unit)
    local readable, name, icon, duration, expires, source = FindAura(unit, "HARMFUL", function(n) return n == markName end)

    if readable then
        -- The auras can be read: this is the truth, and it also corrects the tracked state.
        local t = guid and trackedMarks[guid]
        if name then
            if guid and not (t and t.marked) then
                trackedMarks[guid] = { marked = true, at = now, expires = now + BFA.modules.Hunter.db.markDuration, src = "seen" }
            end
        elseif guid then
            if t and t.marked and t.src == "cast" and now - t.at > 2 then
                -- Learning the real duration: the aura is gone although the tracking thought it was still on.
                Log(string.format("mark gone %.0f s after the cast (tracked duration %s s)", now - t.at,
                    tostring(BFA.modules.Hunter.db.markDuration)))
            end
            if not (t and t.marked and now - t.at <= 2) then -- right after a cast the aura may not show yet
                trackedMarks[guid] = { marked = false, at = now, src = "seen" }
            end
        end
        if not name then
            if guid and trackedMarks[guid] and trackedMarks[guid].marked then
                return "ok", markIcon, nil, "Hunter's Mark was just cast on the target"
            end
            return "warn", markIcon, nil, "Hunter's Mark is not on the target"
        end
        LogChange("mark", string.format("duration=%s expires=%s source=%s", tostring(duration), tostring(expires), tostring(source)))
        local text
        -- Classic often reports no duration for other units: show a time only when the client gives one.
        local okT, shown = pcall(function()
            if duration and duration > 0 and expires and expires > 0 then
                local left = math.max(0, math.floor(expires - GetTime() + 0.5))
                return string.format("%d:%02d", math.floor(left / 60), left % 60)
            end
        end)
        if okT then text = shown end
        return "ok", icon or markIcon, text, "Hunter's Mark is on the target"
    end

    -- Auras are hidden (combat): fall back to what was seen or cast for this very target.
    LogChange("secrecy", Secrecy())
    local t = guid and trackedMarks[guid]
    if not t then return nil end
    if t.marked and t.expires and now >= t.expires then
        trackedMarks[guid] = { marked = false, at = now, src = "expired" }
        t = trackedMarks[guid]
    end
    LogChange("mark", "tracked marked=" .. tostring(t.marked) .. " src=" .. t.src)
    if t.marked then
        return "ok", markIcon, nil, "Hunter's Mark (tracked from your cast)"
    end
    return "warn", markIcon, nil, "No Hunter's Mark (tracked, auras are hidden in combat)"
end

---------------------------------------------------------------------------
-- Aspect
---------------------------------------------------------------------------
local function AspectUpdate()
    if not Known(13165) then return nil end -- no aspects learned yet
    local names = AspectNames()
    local _, hawkIcon = SpellNameIcon(13165)
    local readable, name, icon = FindAura("player", "HELPFUL", function(n) return names[n] end)
    if readable then
        trackedAspect = name and { name = name, icon = icon, src = "seen" } or false
        LogChange("aspect", name or "none")
        if name then return "ok", icon, nil, name end
        return "warn", hawkIcon, "!", "No aspect active"
    end
    -- hidden in combat: what we last saw or cast
    LogChange("secrecy", Secrecy())
    if trackedAspect then
        LogChange("aspect", "tracked " .. trackedAspect.name .. " src=" .. trackedAspect.src)
        return "ok", trackedAspect.icon, nil, trackedAspect.name .. " (tracked)"
    elseif trackedAspect == false then
        LogChange("aspect", "tracked none")
        return "warn", hawkIcon, "!", "No aspect active (tracked, auras are hidden in combat)"
    end
    return nil
end

---------------------------------------------------------------------------
-- Pet
---------------------------------------------------------------------------
local CALL_PET = 883
-- Findings from the logs: this client has no pet happiness (GetPetHappiness returns nil) and UnitHealth of the pet
-- is a secret value at all times, so only "missing", "dead" and "alive" can be shown truthfully.
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
    LogChange("pet", "alive")
    return "ok", icon, nil, UnitName("pet") or "Pet"
end

local function ResetTracking()
    trackedMarks = {}
    trackedAspect = nil
end

local function OnEvent(event, unit, castGUID, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(spellID)
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        trackedAspect = nil -- death and loading screens remove buffs
    end
end

local events = CreateFrame("Frame")
if events.RegisterUnitEvent then events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    local ok, err = pcall(OnEvent, event, unit, castGUID, spellID)
    if not ok then Log("event error: " .. tostring(err)) end
end)

BFA:RegisterModule("Hunter", {
    OnEvent = OnEvent,           -- exposed for the offline tests
    ResetTracking = ResetTracking,
    apiVersion = 1,
    defaults = { ammoWarn = 200, ammoBad = 50, markDuration = 120 },
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
        { id = "ammo", order = 10, onPlate = true, Update = AmmoUpdate }, -- also shown by the nameplate badge
        { id = "mark", order = 20, Update = MarkUpdate },
        { id = "aspect", order = 30, Update = AspectUpdate },
        { id = "pet", order = 40, Update = PetUpdate },
    },
})
