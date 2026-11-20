-- Bajt's Fight Assist: range engine.
-- Probes (spells from modules, verified items, interact checks) give brackets of yards, never an exact distance.
-- Result: state IN | CLOSE | FAR, or nil when unknown or contradictory (then nothing is shown).
local ADDON, BFA = ...
local R = {}
BFA.Range = R
local checkers = {}
R.checkers = checkers

local function Log(text) BFA:Log("Range", text) end

-- Harmful items whose IsItemInRange answers were consistent with Auto Shot in several logged sessions: id, yards.
-- A scan of item ids 1..30000 on a hostile target found only these 4 answering (835, 7734, 8149, 18904).
local VERIFIED_ITEMS = { { 835, 30 }, { 7734, 30 }, { 18904, 35 } }
-- Logged next to every sample for diagnostics (8149 answers near 8 yd, friendly bandages never answer on enemies).
local ITEM_PROBES = {
    { 1251, 15, "f" }, { 3530, 15, "f" }, { 6450, 15, "f" }, { 14529, 15, "f" },
    { 8149, 8, "h" }, { 835, 30, "h" }, { 7734, 30, "h" }, { 18904, 35, "h" },
}
-- CheckInteractDistance fallbacks: index, yards
local INTERACT = { { 3, 9.9 }, { 2, 11.11 }, { 4, 28 } }
local MELEE_RANGE = 5
local FIGHT_RANGE = 12

---------------------------------------------------------------------------
-- API helpers (work with both the table and the multi-return GetSpellInfo)
---------------------------------------------------------------------------
local function GetSpellData(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if info then return info.name, info.minRange or 0, info.maxRange or 0, info.iconID, info.spellID end
        return nil
    end
    if GetSpellInfo then
        local name, _, icon, _, minRange, maxRange, spellID = GetSpellInfo(spell)
        if name then return name, minRange or 0, maxRange or 0, icon, spellID end
    end
end

local function IsKnown(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

local function SpellInRange(name, unit)
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        r = C_Spell.IsSpellInRange(name, unit)
    elseif IsSpellInRange then
        r = IsSpellInRange(name, unit)
    end
    if r == true or r == 1 then return true end
    if r == false or r == 0 then return false end
    return nil
end

local function ItemInRange(id, unit)
    local fn = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    if not fn then return nil end
    local ok, r = pcall(fn, id, unit)
    if not ok then return nil end
    if r == true or r == 1 then return true end
    if r == false or r == 0 then return false end
    return nil
end
R.ItemInRange = ItemInRange

---------------------------------------------------------------------------
-- Probe list: spells from all registered modules, then shared items and interact checks
---------------------------------------------------------------------------
function R.Rebuild()
    wipe(checkers)
    local seenPrimary = false
    local seenSpell = {}
    for _, modName in ipairs(BFA.moduleOrder) do
        for _, p in ipairs(BFA.modules[modName].ranged or {}) do
            local name, minR, maxR, icon = GetSpellData(p.id)
            if name and IsKnown(p.id) and not seenSpell[p.id] then
                seenSpell[p.id] = true
                local melee = false
                local apiMin, apiMax = minR, maxR
                -- Weapon and shot ranges are unreliable in the spell data: never trust less than the fallback.
                if p.fmax and maxR < p.fmax then maxR = 0 end
                if maxR <= 0 then
                    if p.melee then
                        melee, minR, maxR = true, 0, MELEE_RANGE
                    elseif p.fmax then
                        minR, maxR = p.fmin or 0, p.fmax
                    else
                        maxR = nil
                    end
                end
                if maxR then
                    local c = {
                        name = name, min = minR, max = maxR, apiMin = apiMin, apiMax = apiMax,
                        melee = melee, icon = icon, module = modName,
                        primary = p.primary and not seenPrimary or false,
                    }
                    if c.primary then seenPrimary = true end
                    c.test = function(unit) return SpellInRange(name, unit) end
                    checkers[#checkers + 1] = c
                end
            end
        end
    end
    for _, it in ipairs(VERIFIED_ITEMS) do
        local id, yards = it[1], it[2]
        checkers[#checkers + 1] = {
            name = "Item" .. id, min = 0, max = yards, item = true,
            test = function(unit) return ItemInRange(id, unit) end,
        }
    end
    for _, i in ipairs(INTERACT) do
        local idx, yards = i[1], i[2]
        checkers[#checkers + 1] = {
            name = "Interact" .. idx, min = 0, max = yards, interact = true,
            test = function(unit) return not not CheckInteractDistance(unit, idx) end,
        }
    end
    if BFA.db then
        Log("rebuilt: " .. #checkers .. " probes")
        for _, c in ipairs(checkers) do
            Log(string.format("PROBE %s api=%s-%s used=%s-%s primary=%s", c.name, tostring(c.apiMin),
                tostring(c.apiMax), tostring(c.min), tostring(c.max), tostring(c.primary or false)))
        end
    end
end

---------------------------------------------------------------------------
-- Measurement
---------------------------------------------------------------------------
-- Returns state ("IN"|"CLOSE"|"FAR") or nil when unknown, label, bracket text (for the log only), ranged flag.
-- No distance number is ever returned: probes only give wide brackets, a number would be an estimate.
function R.Measure(unit)
    local hi, lo = nil, 0
    local primary, primaryIn
    local answered = 0
    for _, c in ipairs(checkers) do
        local ok = c.test(unit)
        if ok ~= nil then
            answered = answered + 1
            if ok then
                if not hi or c.max < hi then hi = c.max end
                if c.min > lo then lo = c.min end -- a passing probe means at least its minimum range
            elseif c.min == 0 and not c.interact and c.max > lo then
                lo = c.max -- interact checks are unreliable on NPCs: only a positive answer counts
            end
            if c.primary and primaryIn == nil then primary, primaryIn = c, ok end
        end
    end

    local function bracket(l, h)
        if h and l > 0 then return string.format("%d-%d yd", l + 0.5, h + 0.5) end
        if h then return string.format("<= %d yd", h + 0.5) end
        return string.format("> %d yd", l + 0.5)
    end

    -- No probe answered, or the answers contradict each other: we do not know, so say nothing.
    if answered == 0 or (hi and lo > hi) then return nil end

    -- No ranged attack known (Rogue, Warrior, ...): judge against fight range instead.
    local hasRanged = false
    for _, c in ipairs(checkers) do if c.primary then hasRanged = true break end end
    if not hasRanged then
        if hi and hi <= FIGHT_RANGE then
            return "IN", "FIGHT RANGE", bracket(lo < hi and lo or 0, hi), false
        end
        return "FAR", "OUT OF REACH", bracket(lo, hi), false
    end

    if primaryIn == nil then primaryIn = hi ~= nil end
    -- The primary attack did not answer and nothing positive or non-interact is known: we know nothing.
    -- (Target Ranger 0.1.16 showed "FAR > 0 yd" here, a claim without evidence.)
    if not primaryIn and primary == nil and lo == 0 then return nil end
    local pmax = primary and primary.max or 0
    if primaryIn then
        local top = hi or pmax
        return "IN", BFA.LABELS.IN, bracket(lo < top and lo or 0, top), true
    end
    -- Primary attack is out of range, yet a positive probe puts the target inside its maximum range:
    -- the only way both are true is that the target is closer than the attack's minimum range.
    if hi and primary and primary.min > 0 and hi <= pmax then
        return "CLOSE", BFA.LABELS.CLOSE, bracket(0, primary.min), true
    end
    local far = lo > pmax and lo or pmax
    if hi and far > hi then return nil end -- e.g. out of Auto Shot but inside an interact check: contradiction
    return "FAR", BFA.LABELS.FAR, bracket(far, hi), true
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
function R.ProbeDump(unit)
    local out = {}
    for _, c in ipairs(checkers) do
        local r = c.test(unit)
        out[#out + 1] = c.name .. "=" .. (r == nil and "na" or (r and "in" or "out"))
    end
    return table.concat(out, " ")
end

function R.ItemDump(unit)
    local out = {}
    for _, p in ipairs(ITEM_PROBES) do
        local r = ItemInRange(p[1], unit)
        out[#out + 1] = string.format("%d@%d%s=%s", p[1], p[2], p[3], r == nil and "na" or (r and "in" or "out"))
    end
    local hits = BFA.db and BFA.db.scanHits
    if hits and #hits > 0 then
        local chars = {}
        for i, id in ipairs(hits) do
            local r = ItemInRange(id, unit)
            chars[i] = r == nil and "-" or (r and "i" or "o")
        end
        out[#out + 1] = "S=" .. table.concat(chars)
    end
    return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Item scan: finds every item id for which IsItemInRange answers on the current target.
-- Slow on purpose: a fast scan makes every item query answer nil while it runs (seen in the log).
-- Hits are stored in db.scanHits and written to the log.
---------------------------------------------------------------------------
local SCAN_MAX, SCAN_STEP, SCAN_PASSES = 30000, 25, 3
local scanner = CreateFrame("Frame")
local scanId, scanSeen, scanList, scanPass, scanNew, scanStart

local function ScanFinish()
    scanner:SetScript("OnUpdate", nil)
    BFA.db.scanHits = scanList
    Log("SCANLIST " .. table.concat(scanList, ","))
    Log(string.format("SCAN done: %d ids answer on this target, %.0f s", #scanList, GetTime() - scanStart))
    BFA:Say("scan done, " .. #scanList .. " items. /reload to write the log.")
end

function R.StartScan()
    Log("SCAN command received")
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        BFA:Say("scan needs an attackable target.")
        Log("SCAN refused: needs an attackable target (exists=" .. tostring(UnitExists("target")) .. ")")
        return
    end
    scanId, scanSeen, scanList, scanPass, scanNew, scanStart = 0, {}, {}, 1, 0, GetTime()
    Log("SCAN start on " .. tostring(UnitName("target")) .. ", up to " .. SCAN_PASSES .. " slow passes")
    BFA:Say("scan running (about a minute). Keep the target selected and stand still.")
    scanner:SetScript("OnUpdate", function()
        if not UnitExists("target") then
            scanner:SetScript("OnUpdate", nil)
            Log("SCAN aborted: target lost at pass " .. scanPass .. " id " .. scanId)
            return
        end
        for _ = 1, SCAN_STEP do
            scanId = scanId + 1
            if scanId > SCAN_MAX then
                Log(string.format("SCAN pass %d done, %d new, %d total", scanPass, scanNew, #scanList))
                if scanPass >= SCAN_PASSES or (scanPass > 1 and scanNew == 0) then ScanFinish() return end
                scanPass, scanId, scanNew = scanPass + 1, 0, 0
                return
            end
            local r = ItemInRange(scanId, "target")
            if r ~= nil and not scanSeen[scanId] then
                scanSeen[scanId] = true
                scanList[#scanList + 1] = scanId
                scanNew = scanNew + 1
                local name = GetItemInfo and GetItemInfo(scanId)
                Log(string.format("SCAN hit %d %s %s pass %d", scanId, r and "in" or "out", tostring(name), scanPass))
            end
        end
    end)
end
