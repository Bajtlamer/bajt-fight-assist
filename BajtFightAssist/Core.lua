-- Bajt's Fight Assist: core. Database, module registry, events.
-- Modules register with BajtFightAssist:RegisterModule(name, definition), see the plan for the definition format.
local ADDON, BFA = ...
_G.BajtFightAssist = BFA

BFA.API_VERSION = 1
BFA.modules = {}
BFA.moduleOrder = {}
BFA.indicators = {} -- { module = name, def = indicator definition }, sorted by def.order

BFA.COLORS = {
    IN = { 0.15, 1.0, 0.25 },
    CLOSE = { 1.0, 0.6, 0.1 },
    FAR = { 1.0, 0.2, 0.2 },
    ok = { 0.15, 1.0, 0.25 },
    warn = { 1.0, 0.6, 0.1 },
    bad = { 1.0, 0.2, 0.2 },
    -- In-between steps for indicators that grade a count (Rogue combo points: red, orange, yellow, lime, green).
    yellow = { 1.0, 0.9, 0.2 },
    lime = { 0.6, 1.0, 0.2 },
}
BFA.SHORT = { IN = "IN", CLOSE = "MELEE", FAR = "FAR" }
BFA.LABELS = { IN = "IN RANGE", CLOSE = "MELEE ATTACK", FAR = "OUT OF RANGE" }

BFA.DEFAULTS = {
    enabled = true,
    anchor = "both", -- target | nameplate | both | screen
    floatingText = true,
    scale = 1,
    npcs = false,        -- false: ignore NPC targets for the range badge
    sameSide = false,    -- false: ignore players of your own faction or race
    log = true,
    inBattleground = true,
    locked = true,
    rowX = 4,            -- indicator row offset from the badge (to the right), see /bfa row. 4 = under the range icon
    rowY = -3,
    minimap = { hide = false, angle = 225 },
    point = { "CENTER", "UIParent", "CENTER", 0, -150 },
}

function BFA.Meta(addon, field)
    local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return fn and fn(addon, field) or nil
end
BFA.version = BFA.Meta(ADDON, "Version") or "?"

local loginHooks = {}
function BFA:OnLogin(fn) loginHooks[#loginHooks + 1] = fn end

-- Does this indicator also appear next to the nameplate? The player's choice wins over the module default.
function BFA:IndicatorOnPlate(key, def)
    local v = self.db.plate[key]
    if v == nil then return def.onPlate and true or false end
    return v
end

function BFA:RegisterModule(name, def)
    if self.modules[name] then
        self:Log("Core", "module " .. name .. " registered twice, ignored")
        return false
    end
    if def.apiVersion ~= self.API_VERSION then
        self:Log("Core", string.format("module %s refused: api %s, core api %d", name, tostring(def.apiVersion), self.API_VERSION))
        self:Say(string.format("Module %s needs API %s but Core has API %d. Update the addons.", name,
            tostring(def.apiVersion), self.API_VERSION))
        return false
    end
    local db = self.db
    db.modules[name] = db.modules[name] or {}
    for k, v in pairs(def.defaults or {}) do
        if db.modules[name][k] == nil then db.modules[name][k] = v end
    end
    def.name = name
    def.db = db.modules[name]
    self.modules[name] = def
    self.moduleOrder[#self.moduleOrder + 1] = name
    for _, ind in ipairs(def.indicators or {}) do
        self.indicators[#self.indicators + 1] = { module = name, def = ind }
    end
    table.sort(self.indicators, function(a, b) return (a.def.order or 100) < (b.def.order or 100) end)
    self:Log("Core", string.format("module %s registered: %d probes, %d indicators", name,
        #(def.ranged or {}), #(def.indicators or {})))
    if def.OnRegister then
        local ok, err = pcall(def.OnRegister, def)
        if not ok then self:Log("Core", "module " .. name .. " OnRegister error: " .. tostring(err)) end
    end
    if self.Range then self.Range.Rebuild() end
    return true
end

function BFA.OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        BajtFightAssistDB = BajtFightAssistDB or {}
        local db = BajtFightAssistDB
        BFA.db = db
        for k, v in pairs(BFA.DEFAULTS) do
            if db[k] == nil then
                if type(v) == "table" then db[k] = { unpack(v) } else db[k] = v end
            end
        end
        -- Layout version 2: the row is aligned with the range icon (default rowX 4, was 24). Older saved offsets are replaced.
        if (db.layout or 0) < 2 then
            db.rowX, db.rowY = BFA.DEFAULTS.rowX, BFA.DEFAULTS.rowY
            db.layout = 2
        end
        db.modules = db.modules or {}
        db.roleModules = db.roleModules or {}
        db.plate = db.plate or {}
        db.minimap = db.minimap or { hide = false, angle = 225 }
        db.indicators = db.indicators or {}
        BFA:FlushPreLog()
    elseif event == "PLAYER_LOGIN" then
        local db = BFA.db
        -- One-time import of the Target Ranger settings (the old addon is not touched).
        if not db.migrated and TargetRangerDB then
            for k in pairs(BFA.DEFAULTS) do
                if TargetRangerDB[k] ~= nil then db[k] = TargetRangerDB[k] end
            end
            db.scanHits = db.scanHits or TargetRangerDB.scanHits
            db.migrated = true
            BFA:Log("Core", "MIGRATE settings imported from TargetRangerDB")
        end
        BFA:Log("Core", "LOGIN core " .. BFA.version .. " api " .. BFA.API_VERSION)
        local names = {}
        if type(C_Secrets) == "table" then
            for k, v in pairs(C_Secrets) do if type(v) == "function" then names[#names + 1] = k end end
            table.sort(names)
        end
        BFA:Log("Core", string.format("secret values api: issecretvalue=%s C_Secrets=%s [%s]", type(issecretvalue),
            type(C_Secrets), table.concat(names, ",")))
        for _, fn in ipairs(loginHooks) do
            local ok, err = pcall(fn)
            if not ok then BFA:Log("Core", "login hook error: " .. tostring(err)) end
        end
    elseif event == "SPELLS_CHANGED" then
        if BFA.db and BFA.Range then BFA.Range.Rebuild() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if BFA.Driver then BFA.Driver.ResetState() end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:SetScript("OnEvent", function(_, event, arg1) BFA.OnEvent(event, arg1) end)
