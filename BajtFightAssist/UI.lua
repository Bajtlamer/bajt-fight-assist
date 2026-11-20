-- Bajt's Fight Assist: display. State badge, indicator row, floating text.
local ADDON, BFA = ...
local UI = {}
BFA.UI = UI

local FONT = "Fonts\\FRIZQT__.TTF"
local FALLBACK_ICON = "Interface\\Icons\\Ability_Marksmanship"
local COLORS, SHORT = BFA.COLORS, BFA.SHORT

---------------------------------------------------------------------------
-- Badge
---------------------------------------------------------------------------
local function CreateBadge(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(86, 34)
    f:SetFrameStrata("HIGH")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.55)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", 3, 0)
    f.icon:SetTexture(FALLBACK_ICON)
    f.number = f:CreateFontString(nil, "OVERLAY")
    f.number:SetFont(FONT, 16, "OUTLINE")
    f.number:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 4, 0)
    f.sub = f:CreateFontString(nil, "OVERLAY")
    f.sub:SetFont(FONT, 9, "OUTLINE")
    f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 4, 0)
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

function UI.ApplyBadge(f, state, sub, iconTex)
    local c = COLORS[state]
    f.number:SetText(SHORT[state])
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
-- Indicator row: icons with a colored border and optional short text, one slot per visible indicator
---------------------------------------------------------------------------
local row = CreateFrame("Frame", "BajtFightAssistRow", UIParent)
row:SetSize(10, 24)
row:SetFrameStrata("HIGH")
row:Hide()
local slots = {}

local function Slot(i)
    local s = slots[i]
    if s then return s end
    s = CreateFrame("Frame", nil, row)
    s:SetSize(24, 24)
    s:EnableMouse(true)
    s.border = s:CreateTexture(nil, "BACKGROUND")
    s.border:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 2, -2)
    s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    s.text = s:CreateFontString(nil, "OVERLAY")
    s.text:SetFont(FONT, 10, "OUTLINE")
    s.text:SetPoint("BOTTOMRIGHT", 2, -1)
    s:SetScript("OnEnter", function(self)
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip)
            GameTooltip:Show()
        end
    end)
    s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    slots[i] = s
    return s
end

function UI.PlaceRow()
    row:ClearAllPoints()
    if TargetFrame and TargetFrame:IsShown() then
        row:SetPoint("BOTTOMLEFT", TargetFrame, "TOPLEFT", 8, -6)
    else
        local p = BFA.db.point
        row:SetPoint("BOTTOM", UIParent, p[3], p[4], p[5] + 40)
    end
    row:SetScale(BFA.db.scale)
end

-- items: array of { state = "ok"|"warn"|"bad", icon = texture, text = string|nil, tip = string|nil }
function UI.ShowIndicators(items)
    if #items == 0 then
        row:Hide()
        return
    end
    UI.PlaceRow()
    for i, item in ipairs(items) do
        local s = Slot(i)
        local c = COLORS[item.state] or COLORS.ok
        s:ClearAllPoints()
        s:SetPoint("LEFT", row, "LEFT", (i - 1) * 26, 0)
        s.border:SetColorTexture(c[1], c[2], c[3], 1)
        s.icon:SetTexture(item.icon or FALLBACK_ICON)
        s.text:SetText(item.text or "")
        s.text:SetTextColor(c[1], c[2], c[3])
        s.tip = item.tip
        s:Show()
    end
    for i = #items + 1, #slots do slots[i]:Hide() end
    row:SetWidth(#items * 26)
    row:Show()
end

function UI.HideIndicators() row:Hide() end

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
function UI.Float(state)
    if not BFA.db.floatingText then return end
    local now = GetTime()
    if now - lastFloat < 0.6 then return end
    lastFloat = now
    local c = COLORS[state]
    BFA:Log("UI", "FLOAT " .. BFA.LABELS[state])
    float.text:SetText(BFA.LABELS[state])
    float.text:SetTextColor(c[1], c[2], c[3])
    floatElapsed = 0
    float:SetAlpha(1)
    float:Show()
end

BFA:OnLogin(UI.SetupScreenBadge)
