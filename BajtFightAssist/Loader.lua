-- Bajt's Fight Assist: loads the modules that belong to the current character.
-- Module TOC fields: X-BFA-Class (HUNTER, ROGUE, ... or ALL for role modules), X-BFA-API.
-- Class modules are LoadOnDemand, so only the matching one ever runs.
local ADDON, BFA = ...

local function NumAddOns() return (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)() end
local function AddOnName(i) return (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i) end
local function Loaded(name) return (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(name) end
local function Load(name) return (C_AddOns and C_AddOns.LoadAddOn or LoadAddOn)(name) end

function BFA.LoadModules()
    local _, class = UnitClass("player")
    local found = 0
    for i = 1, NumAddOns() do
        local name = AddOnName(i)
        local cls = name and name ~= ADDON and BFA.Meta(name, "X-BFA-Class")
        if cls then
            found = found + 1
            local wanted = (cls == class) or (cls == "ALL" and BFA.db.roleModules[name])
            if wanted then
                local api = tonumber(BFA.Meta(name, "X-BFA-API"))
                if api ~= BFA.API_VERSION then
                    BFA:Log("Loader", string.format("%s not loaded: api %s, core api %d", name, tostring(api), BFA.API_VERSION))
                    BFA:Say(string.format("%s needs API %s but Core has API %d. Update the addons.", name,
                        tostring(api), BFA.API_VERSION))
                elseif Loaded(name) then
                    BFA:Log("Loader", name .. " already loaded")
                else
                    Load(name)
                    BFA:Log("Loader", name .. (Loaded(name) and " loaded" or " FAILED to load"))
                end
            end
        end
    end
    BFA:Log("Loader", string.format("class %s, %d module addons installed, %d modules registered", tostring(class),
        found, #BFA.moduleOrder))
    if #BFA.moduleOrder == 0 then BFA.Range.Rebuild() end
end

BFA:OnLogin(BFA.LoadModules)
