-- Bajt's Fight Assist: display. State badge, indicator row, floating text.
local ADDON, BFA = ...
local UI = {}
BFA.UI = UI

local FONT = "Fonts\\FRIZQT__.TTF"
local FALLBACK_ICON = "Interface\\Icons\\Ability_Marksmanship"
local COLORS, SHORT = BFA.COLORS, BFA.SHORT
local BADGE_MIN_WIDTH, BADGE_HEIGHT = 86, 34
local BADGE_ICON_SIZE, BADGE_ICON_LEFT, BADGE_TEXT_GAP, BADGE_TEXT_RIGHT = 28, 3, 4, 7
local BADGE_TITLE_SIZE, BADGE_SUB_SIZE = 16, 9

-- Measure on an independent frame so nameplate restrictions do not affect text sizing.
local measureFrame = CreateFrame("Frame", nil, UIParent)
measureFrame:Hide()
local measureText = measureFrame:CreateFontString(nil, "OVERLAY")

local function BadgeTextWidth(text, size)
    measureText:SetFont(FONT, size, "OUTLINE")
    measureText:SetText(text)
    return measureText:GetStringWidth()
end

---------------------------------------------------------------------------
-- Badge
---------------------------------------------------------------------------
local function CreateBadge(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(BADGE_MIN_WIDTH, BADGE_HEIGHT)
    f:SetFrameStrata("HIGH")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.55)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(BADGE_ICON_SIZE, BADGE_ICON_SIZE)
    f.icon:SetPoint("LEFT", BADGE_ICON_LEFT, 0)
    f.icon:SetTexture(FALLBACK_ICON)
    f.number = f:CreateFontString(nil, "OVERLAY")
    f.number:SetFont(FONT, BADGE_TITLE_SIZE, "OUTLINE")
    f.number:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", BADGE_TEXT_GAP, 0)
    f.sub = f:CreateFontString(nil, "OVERLAY")
    f.sub:SetFont(FONT, BADGE_SUB_SIZE, "OUTLINE")
    f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", BADGE_TEXT_GAP, 0)
    f:Hide()
    return f
end

local badges = {
    target = CreateBadge("BajtFightAssistTargetBadge"),
    plate = CreateBadge("BajtFightAssistPlateBadge"),
    screen = CreateBadge("BajtFightAssistScreenBadge"),
}
UI.badges = badges

function UI.PlaceScreenBadge()
    local p = BFA.db.point
    badges.screen:ClearAllPoints()
    badges.screen:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

function UI.SetupScreenBadge()
    local f = badges.screen
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not BFA.db.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        BFA.db.point = { p, "UIParent", rp, x, y }
    end)
    UI.PlaceScreenBadge()
end

function UI.ApplyBadge(f, state, sub, iconTex, tone)
    local c = COLORS[tone or state]
    local title = SHORT[state]
    if f.badgeTitle ~= title or f.badgeSub ~= sub then
        local textWidth = math.max(BadgeTextWidth(title, BADGE_TITLE_SIZE), BadgeTextWidth(sub, BADGE_SUB_SIZE))
        local width = BADGE_ICON_LEFT + BADGE_ICON_SIZE + BADGE_TEXT_GAP + textWidth + BADGE_TEXT_RIGHT
        f:SetWidth(math.max(BADGE_MIN_WIDTH, math.ceil(width)))
        f.badgeTitle, f.badgeSub = title, sub
    end
    f.number:SetText(title)
    f.number:SetTextColor(c[1], c[2], c[3])
    f.sub:SetText(sub)
    f.sub:SetTextColor(c[1], c[2], c[3])
    f.bg:SetColorTexture(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.65)
    f.icon:SetTexture(iconTex or FALLBACK_ICON)
    f:SetScale(BFA.db.scale)
    f:Show()
end

function UI.HideBadges()
    for _, f in pairs(badges) do f:Hide() end
end

local function PlateFor(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        return C_NamePlate.GetNamePlateForUnit(unit)
    end
end

-- Places the badges for the current anchor mode. Returns which of target, plate, screen are shown.
function UI.Anchor()
    local a = BFA.db.anchor
    local showTarget = (a == "target" or a == "both")
    local showPlate = (a == "nameplate" or a == "both")
    local showScreen = (a == "screen")

    if showTarget and TargetFrame and TargetFrame:IsShown() then
        badges.target:ClearAllPoints()
        badges.target:SetPoint("LEFT", TargetFrame, "RIGHT", -22, 8)
    else
        showTarget = false
    end
    local plate = showPlate and PlateFor("target")
    if plate then
        badges.plate:ClearAllPoints()
        badges.plate:SetPoint("BOTTOM", plate, "TOP", 0, 6)
    else
        showPlate = false
    end
    return showTarget, showPlate, showScreen
end

---------------------------------------------------------------------------
-- Indicator rows: round icons with a colored ring and optional short text.
-- "main" sits by the target badge (or screen badge), "plate" left of the nameplate badge and shows only the
-- indicators the player allows there (everything when the badge is nameplate-only).
---------------------------------------------------------------------------
local SLOT = 26
local STEP = 30
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function CreateRow(name)
    local row = CreateFrame("Frame", name, UIParent)
    row:SetSize(10, SLOT)
    row:SetFrameStrata("HIGH")
    row:Hide()
    row.slots = {}
    return row
end
local rows = { main = CreateRow("BajtFightAssistRow"), plate = CreateRow("BajtFightAssistPlateRow") }

local function Slot(row, i)
    local s = row.slots[i]
    if s then return s end
    s = CreateFrame("Frame", nil, row)
    s:SetSize(SLOT, SLOT)
    s:EnableMouse(true)
    s.ring = s:CreateTexture(nil, "BACKGROUND")
    s.ring:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 2, -2)
    s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if s.CreateMaskTexture then
        local ringMask = s:CreateMaskTexture()
        ringMask:SetTexture(MASK)
        ringMask:SetAllPoints(s.ring)
        s.ring:AddMaskTexture(ringMask)
        local iconMask = s:CreateMaskTexture()
        iconMask:SetTexture(MASK)
        iconMask:SetAllPoints(s.icon)
        s.icon:AddMaskTexture(iconMask)
    end
    s.text = s:CreateFontString(nil, "OVERLAY")
    s.text:SetFont(FONT, 10, "OUTLINE")
    s.text:SetPoint("TOP", s, "BOTTOM", 0, -1)
    s:SetScript("OnEnter", function(self)
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip)
            GameTooltip:Show()
        end
    end)
    s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.slots[i] = s
    return s
end

-- Where the main row goes. Never above the target frame: that is at the top edge of the screen on many layouts.
local function PlaceMain(row)
    local db = BFA.db
    row:ClearAllPoints()
    local what
    if badges.target:IsShown() then
        row:SetPoint("TOPLEFT", badges.target, "BOTTOMLEFT", db.rowX, db.rowY)
        what = "target badge"
    elseif badges.screen:IsShown() then
        row:SetPoint("TOPLEFT", badges.screen, "BOTTOMLEFT", db.rowX, db.rowY)
        what = "screen badge"
    elseif TargetFrame and TargetFrame:IsShown() then
        row:SetPoint("TOPLEFT", TargetFrame, "BOTTOMRIGHT", -40 + db.rowX, 30)
        what = "target frame"
    else
        return nil
    end
    return what
end

local function PlacePlate(row)
    local db = BFA.db
    if not badges.plate:IsShown() then return nil end
    row:ClearAllPoints()
    -- To the left of the badge, on its line (the count text sits under each icon).
    row:SetPoint("RIGHT", badges.plate, "LEFT", -4, 0)
    return "plate badge"
end

local function Fill(row, items)
    if #items == 0 then row:Hide() return end
    row:SetScale(BFA.db.scale)
    for i, item in ipairs(items) do
        local s = Slot(row, i)
        local c = COLORS[item.state] or COLORS.ok
        s:ClearAllPoints()
        s:SetPoint("LEFT", row, "LEFT", (i - 1) * STEP, 0)
        s.ring:SetColorTexture(c[1], c[2], c[3], 1)
        s.icon:SetTexture(item.icon or FALLBACK_ICON)
        s.text:SetText(item.text or "")
        s.text:SetTextColor(c[1], c[2], c[3])
        s.tip = item.tip
        s:Show()
    end
    for i = #items + 1, #row.slots do row.slots[i]:Hide() end
    row:SetWidth(#items * STEP)
    row:Show()
end

-- items: array of { state = a key of BFA.COLORS ("ok"|"warn"|"bad"|"yellow"|"lime"), icon = texture, text = string|nil, tip = string|nil, plate = bool|nil }
function UI.ShowIndicators(items)
    local db = BFA.db
    local plateOnly = (db.anchor == "nameplate")
    local plateItems = {}
    for _, item in ipairs(items) do
        if plateOnly or item.plate then plateItems[#plateItems + 1] = item end
    end

    local mainWhere = (not plateOnly) and #items > 0 and PlaceMain(rows.main) or nil
    Fill(rows.main, mainWhere and items or {})

    local plateWhere = #plateItems > 0 and PlacePlate(rows.plate) or nil
    Fill(rows.plate, plateWhere and plateItems or {})

    -- Log where the rows are, so a position problem can be verified from the log. Frames anchored to a nameplate
    -- are restricted regions that addons may not measure (GetLeft raises an error), hence the pcall and no
    -- measurement of the plate row at all.
    local function rect(row)
        local ok, l, b = pcall(function() return row:GetLeft(), row:GetBottom() end)
        return ok and (tostring(l) .. "," .. tostring(b)) or "unmeasurable"
    end
    local okS, sig = pcall(function()
        return string.format("main=%s(%s) plate=%s screen=%sx%s offset=%s,%s", tostring(mainWhere),
            mainWhere and rect(rows.main) or "-", tostring(plateWhere), tostring(UIParent:GetWidth()),
            tostring(UIParent:GetHeight()), tostring(db.rowX), tostring(db.rowY))
    end)
    if okS and sig ~= UI.lastRowSig then
        UI.lastRowSig = sig
        BFA:Log("UI", "indicator rows: " .. sig)
    end
end

function UI.HideIndicators()
    rows.main:Hide()
    rows.plate:Hide()
end

---------------------------------------------------------------------------
-- Floating text
---------------------------------------------------------------------------
local float = CreateFrame("Frame", "BajtFightAssistFloat", UIParent)
float:SetSize(300, 40)
float:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
float:SetFrameStrata("HIGH")
float.text = float:CreateFontString(nil, "OVERLAY")
float.text:SetFont(FONT, 26, "OUTLINE")
float.text:SetPoint("CENTER")
float:Hide()
local floatElapsed = 0
float:SetScript("OnUpdate", function(self, dt)
    floatElapsed = floatElapsed + dt
    if floatElapsed >= 1.4 then self:Hide() return end
    self:SetAlpha(floatElapsed < 0.7 and 1 or (1.4 - floatElapsed) / 0.7)
    self:SetPoint("CENTER", UIParent, "CENTER", 0, 140 + floatElapsed * 25)
end)

local lastFloat = 0
function UI.Float(state, label, tone)
    if not BFA.db.floatingText then return end
    local now = GetTime()
    if now - lastFloat < 0.6 then return end
    lastFloat = now
    local c = COLORS[tone or state]
    label = label or BFA.LABELS[state]
    BFA:Log("UI", "FLOAT " .. label)
    float.text:SetText(label)
    float.text:SetTextColor(c[1], c[2], c[3])
    floatElapsed = 0
    float:SetAlpha(1)
    float:Show()
end

BFA:OnLogin(UI.SetupScreenBadge)
