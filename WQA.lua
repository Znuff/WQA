local ADDON_NAME, ns = ...

-- Defaults
local defaults = {
    trackedQuests = {},
    sound = 311509, -- false to disable, or soundkit ID
}

-- Local references
local frame = CreateFrame("Frame")
local activeQuests = {}
local notifiedQuests = {} -- Track quests we've already notified about

-- Colors for output
local ADDON_COLOR = "|cff00ccff"
local ERROR_COLOR = "|cffff4444"
local SUCCESS_COLOR = "|cff44ff44"
local INFO_COLOR = "|cffffff00"

local function Print(...)
    print(ADDON_COLOR .. "[WQA]|r", ...)
end

local function PrintError(msg)
    Print(ERROR_COLOR .. msg .. "|r")
end

local function PrintSuccess(msg)
    Print(SUCCESS_COLOR .. msg .. "|r")
end

local function PrintInfo(msg)
    Print(INFO_COLOR .. msg .. "|r")
end

-- Toast notification system
local toastPool = {}
local activeToasts = {}
local TOAST_WIDTH = 300
local TOAST_HEIGHT = 60
local TOAST_SPACING = 5
local TOAST_DURATION = 10

local function RepositionToasts()
    local yOffset = 0
    for i, toast in ipairs(activeToasts) do
        toast:ClearAllPoints()
        toast:SetPoint("TOP", UIParent, "TOP", 0, -100 - yOffset)
        yOffset = yOffset + TOAST_HEIGHT + TOAST_SPACING
    end
end

local function ReleaseToast(toast)
    toast:Hide()
    toast:SetScript("OnUpdate", nil)
    for i, t in ipairs(activeToasts) do
        if t == toast then
            table.remove(activeToasts, i)
            break
        end
    end
    table.insert(toastPool, toast)
    RepositionToasts()
end

local function CreateToast()
    local toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    toast:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    toast:SetFrameStrata("DIALOG")
    toast:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    toast:SetBackdropColor(0, 0, 0, 0.9)
    toast:SetBackdropBorderColor(0, 0.8, 1, 1)
    
    -- Title
    toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.title:SetPoint("TOPLEFT", 10, -8)
    toast.title:SetText("World Quest Active!")
    toast.title:SetTextColor(0, 0.8, 1)
    
    -- Quest text
    toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.text:SetPoint("TOPLEFT", 10, -28)
    toast.text:SetPoint("RIGHT", -30, 0)
    toast.text:SetJustifyH("LEFT")
    toast.text:SetWordWrap(true)
    
    -- Close button
    toast.close = CreateFrame("Button", nil, toast, "UIPanelCloseButton")
    toast.close:SetPoint("TOPRIGHT", 2, 2)
    toast.close:SetSize(24, 24)
    toast.close:SetScript("OnClick", function()
        ReleaseToast(toast)
    end)
    
    -- Click to dismiss
    toast:EnableMouse(true)
    toast:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ReleaseToast(toast)
        end
    end)
    
    return toast
end

local function ShowToast(questText, questID)
    local toast = table.remove(toastPool) or CreateToast()
    toast.text:SetText(questText .. "\n|cff888888ID: " .. questID .. " (right-click to dismiss)|r")
    
    -- Auto-hide timer
    toast.elapsed = 0
    toast:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= TOAST_DURATION then
            ReleaseToast(self)
        end
    end)
    
    toast:Show()
    table.insert(activeToasts, toast)
    RepositionToasts()
    
    -- Play sound if enabled
    if WQADB.sound then
        PlaySound(WQADB.sound)
    end
end

-- Check for active world quests
local function CheckWorldQuests()
    local currentActive = {}
    
    for questID, questData in pairs(WQADB.trackedQuests) do
        questID = tonumber(questID)
        
        if questID and questID > 0 then
            local questTitle = C_TaskQuest.GetQuestInfoByQuestID(questID)
            local mapID = C_TaskQuest.GetQuestZoneID(questID)
            
            if mapID then
                local questsActive = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
                local mapInfo = C_Map.GetMapInfo(mapID)
                
                if questsActive and mapInfo then
                    for _, questInfo in ipairs(questsActive) do
                        if questInfo.questID == questID then
                            local description = (questData.desc and questData.desc ~= "") and questData.desc or questTitle or ("Quest " .. questID)
                            local text = description .. " - " .. mapInfo.name
                            
                            currentActive[questID] = true
                            
                            -- Only notify if we haven't already
                            if not notifiedQuests[questID] then
                                notifiedQuests[questID] = true
                                ShowToast(text, questID)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Clear notification flags for quests that are no longer active
    for questID in pairs(notifiedQuests) do
        if not currentActive[questID] then
            notifiedQuests[questID] = nil
        end
    end
end

-- Slash command: Add quest
local function AddQuest(questID, description)
    questID = tonumber(questID)
    
    if not questID or questID <= 0 then
        PrintError("Invalid quest ID. Usage: /wqa add <questID> [description]")
        return
    end
    
    if WQADB.trackedQuests[questID] then
        PrintError("Quest " .. questID .. " is already being tracked.")
        return
    end
    
    WQADB.trackedQuests[questID] = {
        id = questID,
        desc = description or ""
    }
    
    local questTitle = C_TaskQuest.GetQuestInfoByQuestID(questID)
    local displayName = description and description ~= "" and description or (questTitle or "Unknown Quest")
    
    PrintSuccess("Now tracking: " .. displayName .. " (ID: " .. questID .. ")")
    
    -- Check immediately
    CheckWorldQuests()
end

-- Slash command: List quests
local function ListQuests()
    local count = 0
    
    for questID, questData in pairs(WQADB.trackedQuests) do
        count = count + 1
    end
    
    if count == 0 then
        PrintInfo("No quests being tracked. Use /wqa add <questID> [description] to add one.")
        return
    end
    
    PrintInfo("Tracked quests (" .. count .. "):")
    
    for questID, questData in pairs(WQADB.trackedQuests) do
        questID = tonumber(questID)
        local questTitle = C_TaskQuest.GetQuestInfoByQuestID(questID)
        local questLink = GetQuestLink(questID)
        local displayName = questData.desc and questData.desc ~= "" and questData.desc or (questTitle or "Unknown")
        
        local status = ""
        local mapID = C_TaskQuest.GetQuestZoneID(questID)
        if mapID then
            local questsActive = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
            if questsActive then
                for _, questInfo in ipairs(questsActive) do
                    if questInfo.questID == questID then
                        status = SUCCESS_COLOR .. " [ACTIVE]|r"
                        break
                    end
                end
            end
        end
        
        local idStr = "|cff888888[" .. questID .. "]|r "
        if questLink then
            Print("  " .. idStr .. questLink .. " - " .. displayName .. status)
        else
            Print("  " .. idStr .. displayName .. status)
        end
    end
end

-- Slash command: Delete quest
local function DeleteQuest(questID)
    questID = tonumber(questID)
    
    if not questID then
        PrintError("Invalid quest ID. Usage: /wqa delete <questID>")
        return
    end
    
    if not WQADB.trackedQuests[questID] then
        PrintError("Quest " .. questID .. " is not being tracked.")
        return
    end
    
    local questData = WQADB.trackedQuests[questID]
    local displayName = questData.desc and questData.desc ~= "" and questData.desc or ("Quest " .. questID)
    
    WQADB.trackedQuests[questID] = nil
    notifiedQuests[questID] = nil
    
    PrintSuccess("Removed: " .. displayName .. " (ID: " .. questID .. ")")
end

-- Slash command: Sound settings
local function SetSound(arg)
    if not arg or arg == "" then
        -- Show current status
        if WQADB.sound then
            PrintInfo("Sound is enabled (ID: " .. WQADB.sound .. ")")
        else
            PrintInfo("Sound is disabled")
        end
        return
    end
    
    local lower = arg:lower()
    
    if lower == "off" or lower == "false" or lower == "0" then
        WQADB.sound = false
        PrintSuccess("Sound disabled")
    elseif lower == "on" or lower == "true" then
        WQADB.sound = 311394
        PrintSuccess("Sound enabled (default: 311394)")
    else
        local soundID = tonumber(arg)
        if soundID and soundID > 0 then
            WQADB.sound = soundID
            PrintSuccess("Sound set to ID: " .. soundID)
            PlaySound(soundID)
        else
            PrintError("Invalid sound ID. Use a number, 'on', or 'off'")
        end
    end
end

-- Slash command: Show help
local function ShowHelp()
    PrintInfo("WQA - World Quest Alert Commands:")
    Print("  /wqa add <questID> [description] - Add a quest to track")
    Print("  /wqa list - List all tracked quests")
    Print("  /wqa delete <questID> - Remove a quest from tracking")
    Print("  /wqa check - Manually check for active quests")
    Print("  /wqa sound [on/off/soundID] - Toggle or set notification sound")
    Print("  /wqa help - Show this help message")
end

-- Slash command handler
local function SlashHandler(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    
    local cmd = args[1] and args[1]:lower() or ""
    
    if cmd == "add" then
        local questID = args[2]
        -- Join remaining args as description
        local description = ""
        if #args > 2 then
            description = table.concat(args, " ", 3)
        end
        AddQuest(questID, description)
        
    elseif cmd == "list" then
        ListQuests()
        
    elseif cmd == "delete" or cmd == "del" or cmd == "remove" then
        DeleteQuest(args[2])
        
    elseif cmd == "check" then
        -- Reset notifications so check always shows active quests
        wipe(notifiedQuests)
        CheckWorldQuests()
        
    elseif cmd == "sound" then
        SetSound(args[2])
        
    elseif cmd == "help" or cmd == "" then
        ShowHelp()
        
    else
        PrintError("Unknown command: " .. cmd)
        ShowHelp()
    end
end

-- Event handler
local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Initialize SavedVariables
        if not WQADB then
            WQADB = {}
        end
        
        for k, v in pairs(defaults) do
            if WQADB[k] == nil then
                WQADB[k] = v
            end
        end
        
        -- Register slash commands
        SLASH_WQA1 = "/wqa"
        SlashCmdList["WQA"] = SlashHandler
        
        Print("Loaded. Type /wqa help for commands.")
        
        frame:UnregisterEvent("ADDON_LOADED")
        
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        CheckWorldQuests()
        
    elseif event == "QUEST_LOG_UPDATE" then
        CheckWorldQuests()
    end
end

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("QUEST_LOG_UPDATE")

frame:SetScript("OnEvent", OnEvent)
