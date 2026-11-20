-- Bajt's Fight Assist: update loop. Range state every 0.1 s, module indicators every 0.25 s.
local ADDON, BFA = ...
local D = {}
BFA.Driver = D
local R, UI

local lastState, pendingState, pendingTicks
local rawState, lastSample = nil, 0
local testStep, testNext = nil, 0
local TEST = {
    { "IN", "IN RANGE" }, { "CLOSE", "MELEE ATTACK" }, { "FAR", "OUT OF RANGE" },
}
local indAcc = 0
local indLast = {}   -- indicator key -> last logged "state|text"
local indErr = {}    -- indicator key -> last error text (an error means "unreadable now", it is retried)

function D.ResetState()
    lastState, pendingState = nil, nil
end

function D.StartTest()
    testStep, testNext = 0, 0
end

local function InBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

function D.Eligible(unit)
    local db = BFA.db
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAttack("player", unit) then
        return false
    end
    if not db.inBattleground and InBattleground() then return false end
    if not UnitIsPlayer(unit) then return db.npcs end
    if db.sameSide then return true end
    local myFaction, theirFaction = UnitFactionGroup("player"), UnitFactionGroup(unit)
    if myFaction and theirFaction and myFaction == theirFaction then return false end
    local _, myRace = UnitRace("player")
    local _, theirRace = UnitRace(unit)
    if myRace and theirRace and myRace == theirRace then return false end
    return true
end

-- Indicators are shown for any living attackable target, independent of the NPC filter of the range badge.
local function UpdateIndicators()
    local db = BFA.db
    if not (UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")) then
        UI.HideIndicators()
        return
    end
    local items = {}
    for _, entry in ipairs(BFA.indicators) do
        local id, def = entry.def.id, entry.def
        local key = entry.module .. "." .. id
        if db.indicators[key] ~= false then
            local ok, state, icon, text, tip = pcall(def.Update, "target")
            if not ok then
                -- e.g. aura or health data is secret during combat: unknown right now, so hide and retry next tick
                local msg = tostring(state):gsub("\n.*", ""):sub(1, 140)
                if indErr[key] ~= msg then
                    indErr[key] = msg
                    BFA:Log("Driver", string.format("indicator %s unreadable (combat=%s): %s", key,
                        tostring(InCombatLockdown and InCombatLockdown()), msg))
                end
            else
                if indErr[key] then
                    indErr[key] = nil
                    BFA:Log("Driver", "indicator " .. key .. " readable again")
                end
                if state then items[#items + 1] = { state = state, icon = icon, text = text, tip = tip, plate = def.onPlate } end
            end
            local sig = ok and tostring(state) .. "|" .. tostring(text) or "unreadable"
            if indLast[key] ~= sig then
                indLast[key] = sig
                BFA:Log(entry.module, "IND " .. id .. " " .. sig)
            end
        end
    end
    local okShow, errShow = pcall(UI.ShowIndicators, items)
    if not okShow then
        local msg = tostring(errShow):gsub("\n.*", ""):sub(1, 160)
        if D.lastShowError ~= msg then
            D.lastShowError = msg
            BFA:Log("Driver", "ShowIndicators error: " .. msg)
        end
    end
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
    local db = BFA.db
    R, UI = BFA.Range, BFA.UI
    acc = acc + dt
    if acc < 0.1 then return end
    acc = 0
    if not db or not db.enabled then
        if UI then UI.HideBadges() UI.HideIndicators() end
        return
    end

    indAcc = indAcc + 0.1
    if indAcc >= 0.25 then
        indAcc = 0
        UpdateIndicators()
    end

    local state, sub
    if testStep then
        if GetTime() >= testNext then
            testStep = testStep + 1
            testNext = GetTime() + 1.6
            if testStep > #TEST then testStep = nil UI.HideBadges() lastState = nil return end
            UI.Float(TEST[testStep][1])
        end
        state, sub = TEST[testStep][1], TEST[testStep][2]
    else
        if not D.Eligible("target") then
            UI.HideBadges() lastState = nil pendingState = nil
            if rawState ~= "HIDDEN" then
                rawState = "HIDDEN"
                BFA:Log("Range", "HIDDEN " .. (UnitExists("target") and string.format(
                    "name=%s player=%s faction=%s race=%s canAttack=%s",
                    tostring(UnitName("target")), tostring(UnitIsPlayer("target")), tostring(UnitFactionGroup("target")),
                    tostring((select(2, UnitRace("target")))), tostring(UnitCanAttack("player", "target"))) or "no target"))
            end
            return
        end
        local bracket
        state, sub, bracket = R.Measure("target")
        local now = GetTime()
        if not state then
            -- unknown: show nothing rather than something that may be false
            UI.HideBadges() lastState = nil pendingState = nil
            if rawState ~= "UNKNOWN" or now - lastSample >= 1 then
                BFA:Log("Range", "UNKNOWN no usable answer | " .. R.ProbeDump("target") .. " | " .. R.ItemDump("target"))
                rawState, lastSample = "UNKNOWN", now
            end
            return
        end
        if state ~= rawState or now - lastSample >= 1 then
            BFA:Log("Range", string.format("%s %s [%s] %s | %s | %s", state ~= rawState and "CHANGE" or "sample", state,
                bracket, sub, R.ProbeDump("target"), R.ItemDump("target")))
            rawState, lastSample = state, now
        end
        -- debounce state changes for the floating text (2 stable ticks)
        if state ~= lastState then
            if pendingState == state then
                pendingTicks = pendingTicks + 1
                if pendingTicks >= 2 then
                    if lastState ~= nil then UI.Float(state) end
                    lastState = state
                end
            else
                pendingState, pendingTicks = state, 1
                if lastState == nil then lastState = state end
            end
        else
            pendingState = nil
        end
    end

    local first = R.checkers[1] and R.checkers[1].icon
    local sT, sP, sS = UI.Anchor()
    if testStep and not sT and not sP then sS = true end
    local b = UI.badges
    if sT then UI.ApplyBadge(b.target, state, sub, first) else b.target:Hide() end
    if sP then UI.ApplyBadge(b.plate, state, sub, first) else b.plate:Hide() end
    if sS then UI.ApplyBadge(b.screen, state, sub, first) else b.screen:Hide() end
end)
