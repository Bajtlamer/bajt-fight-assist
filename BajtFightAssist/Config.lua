-- Bajt's Fight Assist: configuration window (/bfa, or the minimap button).
-- Plain client frames only. The setters below hold the logic and are tested offline.
local ADDON, BFA = ...
local C = {}
BFA.Config = C

local ANCHORS = { "both", "target", "nameplate", "screen" }
local ANCHOR_LABEL = {
    both = "Target frame and nameplate", target = "Target frame only",
    nameplate = "Nameplate only", screen = "Screen position",
}

---------------------------------------------------------------------------
-- Logic (no frames)
---------------------------------------------------------------------------
function C.SetFlag(key, value)
    BFA.db[key] = value
    BFA:Log("Config", key .. " = " .. tostring(value))
end

function C.CycleAnchor()
    local db = BFA.db
    local at = 1
    for i, a in ipairs(ANCHORS) do if a == db.anchor then at = i end end
    db.anchor = ANCHORS[at % #ANCHORS + 1]
    BFA:Log("Config", "anchor = " .. db.anchor)
    return db.anchor
end

function C.SetIndicator(key, shown)
    BFA.db.indicators[key] = shown and true or false
    BFA:Log("Config", "indicator " .. key .. " shown = " .. tostring(shown and true or false))
end

function C.SetPlate(key, onPlate)
    BFA.db.plate[key] = onPlate and true or false
    BFA:Log("Config", "indicator " .. key .. " on nameplate = " .. tostring(onPlate and true or false))
end

function C.SetMinimapShown(shown)
    BFA.db.minimap.hide = not shown
    BFA:Log("Config", "minimap button shown = " .. tostring(shown and true or false))
    if BFA.Minimap then BFA.Minimap.Refresh() end
end

function C.ResetLayout()
    local d = BFA.DEFAULTS
    BFA.db.rowX, BFA.db.rowY, BFA.db.scale, BFA.db.anchor = d.rowX, d.rowY, d.scale, d.anchor
    BFA:Log("Config", "layout reset")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local FONT = "Fonts\\FRIZQT__.TTF"
local frame
local refreshers = {}

local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function CheckBox(parent, text, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    if type(cb.Text) == "table" and cb.Text.SetText then cb.Text:SetText("") end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    return cb, fs
end

local function Slider(parent, text, x, y, minV, maxV, step, get, set)
    local label = Label(parent, text, x, y)
    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetSize(260, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    for _, k in ipairs({ "Text", "Low", "High" }) do
        local r = s[k]
        if type(r) == "table" and r.SetText then r:SetText("") end
    end
    valueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    local updating = false
    s:SetScript("OnValueChanged", function(self, value)
        if updating then return end
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(string.format(step < 1 and "%.1f" or "%d", value))
        set(value)
    end)
    refreshers[#refreshers + 1] = function()
        updating = true
        local v = get()
        s:SetValue(v)
        valueText:SetText(string.format(step < 1 and "%.1f" or "%d", v))
        updating = false
    end
    return s
end

local function Button(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Build()
    local db = BFA.db
    local f = CreateFrame("Frame", "BajtFightAssistConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetPoint("CENTER")
    if type(f.TitleText) == "table" and f.TitleText.SetText then
        f.TitleText:SetText("Bajt's Fight Assist")
    else
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOP", 0, -6)
        t:SetText("Bajt's Fight Assist")
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "BajtFightAssistConfig") end

    local x, y = 16, -34
    Label(f, "Display", x, y, "GameFontNormal"); y = y - 22
    CheckBox(f, "Addon enabled", x, y, function() return db.enabled end, function(v) C.SetFlag("enabled", v) end)
    CheckBox(f, "Floating text on state change", x + 190, y, function() return db.floatingText end,
        function(v) C.SetFlag("floatingText", v) end); y = y - 26
    CheckBox(f, "Show NPC targets", x, y, function() return db.npcs end, function(v) C.SetFlag("npcs", v) end)
    CheckBox(f, "Players of my faction or race", x + 190, y, function() return db.sameSide end,
        function(v) C.SetFlag("sameSide", v) end); y = y - 26
    CheckBox(f, "Active in battlegrounds", x, y, function() return db.inBattleground end,
        function(v) C.SetFlag("inBattleground", v) end)
    CheckBox(f, "Minimap button", x + 190, y, function() return not db.minimap.hide end,
        function(v) C.SetMinimapShown(v) end); y = y - 34

    Label(f, "Range badge", x, y, "GameFontNormal"); y = y - 22
    local anchorLabel = Label(f, "", x, y)
    local anchorBtn = Button(f, "Change", x + 250, y + 5, 90, function()
        C.CycleAnchor()
        for _, r in ipairs(refreshers) do r() end
    end)
    refreshers[#refreshers + 1] = function() anchorLabel:SetText("Shown at: " .. (ANCHOR_LABEL[db.anchor] or db.anchor)) end
    y = y - 32
    Slider(f, "Scale", x, y, 0.5, 3, 0.1, function() return db.scale end, function(v) db.scale = v end); y = y - 48
    Slider(f, "Indicator row: shift right", x, y, -100, 200, 1, function() return db.rowX end,
        function(v) db.rowX = v end); y = y - 48
    Slider(f, "Indicator row: shift up", x, y, -100, 100, 1, function() return db.rowY end,
        function(v) db.rowY = v end); y = y - 52

    Label(f, "Indicators", x, y, "GameFontNormal")
    Label(f, "Show", x + 230, y, "GameFontNormalSmall")
    Label(f, "Nameplate", x + 280, y, "GameFontNormalSmall"); y = y - 22
    if #BFA.indicators == 0 then
        Label(f, "No class module loaded.", x, y); y = y - 22
    end
    for _, entry in ipairs(BFA.indicators) do
        local key = entry.module .. "." .. entry.def.id
        local def = entry.def
        Label(f, entry.module .. ": " .. (def.title or def.id), x + 4, y - 4)
        CheckBox(f, "", x + 232, y, function() return db.indicators[key] ~= false end,
            function(v) C.SetIndicator(key, v) end)
        CheckBox(f, "", x + 292, y, function() return BFA:IndicatorOnPlate(key, def) end,
            function(v) C.SetPlate(key, v) end)
        y = y - 26
    end
    y = y - 10
    Button(f, "Test", x, y, 80, function() BFA.Driver.StartTest() end)
    Button(f, "Reset layout", x + 90, y, 110, function()
        C.ResetLayout()
        for _, r in ipairs(refreshers) do r() end
    end)
    y = y - 40

    f:SetSize(400, -y + 10)
    f:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
    f:Hide()
    return f
end

function C.Toggle()
    if not frame then frame = Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function C.Show()
    if not frame then frame = Build() end
    frame:Show()
end
