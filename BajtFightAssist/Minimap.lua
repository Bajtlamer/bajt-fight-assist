-- Bajt's Fight Assist: minimap button. Left click opens the settings, right click switches the addon on or off,
-- dragging moves the button around the minimap edge. Position and visibility are saved.
local ADDON, BFA = ...
local M = {}
BFA.Minimap = M

local ICON = "Interface\\Icons\\Ability_Marksmanship"
local button

local function Position()
    local angle = math.rad(BFA.db.minimap.angle or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Dragging()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    BFA.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    Position()
end

function M.Refresh()
    if not button then return end
    if BFA.db.minimap.hide then button:Hide() else Position() button:Show() end
end

local function Create()
    button = CreateFrame("Button", "BajtFightAssistMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then
            BFA.db.enabled = not BFA.db.enabled
            BFA:Say("Addon " .. (BFA.db.enabled and "on" or "off"))
        else
            BFA.Config.Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Dragging) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Bajt's Fight Assist")
        GameTooltip:AddLine("Left click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right click: " .. (BFA.db.enabled and "switch off" or "switch on"), 1, 1, 1)
        GameTooltip:AddLine("Drag: move the button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    M.Refresh()
end

M.Create = Create
BFA:OnLogin(Create)
