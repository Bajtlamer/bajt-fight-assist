-- Bajt's Fight Assist: logging. Everything goes to BajtFightAssistDB.logLines (written to disk on /reload or logout).
local ADDON, BFA = ...

local LOG_MAX = 6000
local pre = {} -- lines logged before the saved variables are available

local function Add(self, tag, text)
    local line = date("%H:%M:%S") .. " [" .. tag .. "] " .. text
    local db = self.db
    if not db then
        if #pre < 200 then pre[#pre + 1] = line end
        return
    end
    if not db.log then return end
    db.logLines = db.logLines or {}
    local lines = db.logLines
    lines[#lines + 1] = line
    if #lines > LOG_MAX then table.remove(lines, 1) end
end

function BFA:Log(tag, text) Add(self, tag, tostring(text)) end

-- Called by Core once the database exists.
function BFA:FlushPreLog()
    for _, line in ipairs(pre) do
        if self.db.log then
            self.db.logLines = self.db.logLines or {}
            self.db.logLines[#self.db.logLines + 1] = line
        end
    end
    wipe(pre)
end

function BFA:Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBajtFightAssist:|r " .. msg)
    self:Log("SAY", msg)
end
