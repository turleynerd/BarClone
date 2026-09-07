-------------------------------------------------------------------------------
-- BarClone - core
-- Saves the 120 action slots (spells, items, macros) into named profiles that
-- live in an account-wide SavedVariable, so any character can load them.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
_G.BarClone = ns

local NUM_SLOTS = 120
local DB_VERSION = 1
local QUESTION_MARK_ICON = 134400
local MAX_NAME_LEN = 40

local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS or 18

-- Container API compatibility (C_Container exists on this client, but keep the fallback).
local GetContainerNumSlots_ = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemID_ = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local PickupContainerItem_ = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

local PET_BOOK = BOOKTYPE_PET or "pet"

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------
local function Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        msg = fmt:format(...)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BarClone:|r " .. tostring(msg))
end
ns.Print = Print

local function Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
ns.Trim = Trim

function ns.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        local hex = c.colorStr and ("|c" .. c.colorStr)
            or ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
        return c.r, c.g, c.b, hex
    end
    return 1, 1, 1, "|cffffffff"
end

function ns.FormatDate(ts)
    if not ts then return "?" end
    return date("%Y-%m-%d %H:%M", ts)
end

-------------------------------------------------------------------------------
-- Database
-------------------------------------------------------------------------------
local DEFAULT_OPTIONS = {
    clearBeforeLoad = true,     -- empty every slot that is empty in the profile
    createMissingMacros = true, -- create macros the loading character does not have
    onlyMyClass = true,         -- UI list filter
}

local function InitDB()
    if type(BarCloneDB) ~= "table" then
        BarCloneDB = {}
    end
    BarCloneDB.version = BarCloneDB.version or DB_VERSION
    BarCloneDB.profiles = BarCloneDB.profiles or {}
    BarCloneDB.options = BarCloneDB.options or {}
    for k, v in pairs(DEFAULT_OPTIONS) do
        if BarCloneDB.options[k] == nil then
            BarCloneDB.options[k] = v
        end
    end
    ns.db = BarCloneDB
end

local function InitCharacter()
    local name = UnitName("player")
    local realm = GetRealmName()
    ns.charName = name
    ns.charKey = name .. "-" .. realm
    ns.classLocalized, ns.class = UnitClass("player")
end

function ns.GetProfile(name)
    return ns.db and ns.db.profiles[name]
end

-- Sorted list of profile names, optionally restricted to the current class.
function ns.GetProfileNames(onlyMyClass)
    local names = {}
    for name, p in pairs(ns.db.profiles) do
        if not onlyMyClass or p.class == ns.class then
            names[#names + 1] = name
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function ns.ValidateName(name)
    name = Trim(name)
    if name == "" then
        return nil, "Profile name cannot be empty."
    end
    if #name > MAX_NAME_LEN then
        return nil, ("Profile name is too long (max %d characters)."):format(MAX_NAME_LEN)
    end
    return name
end

local function NotifyUI()
    if ns.RefreshUI then
        ns.RefreshUI()
    end
end

-------------------------------------------------------------------------------
-- Capture
-------------------------------------------------------------------------------
local function CaptureSlot(slot)
    if not HasAction(slot) then
        return nil
    end
    local actionType, id, subType = GetActionInfo(slot)
    if not actionType then
        return nil
    end

    if actionType == "spell" then
        if not id or id == 0 then return nil end
        local name, rank = GetSpellInfo(id)
        return { type = "spell", id = id, name = name, rank = rank, sub = subType }
    elseif actionType == "item" then
        if not id or id == 0 then return nil end
        local name = GetItemInfo(id) -- may be nil when the item is not cached; fine
        return { type = "item", id = id, name = name }
    elseif actionType == "macro" then
        local name, icon, body = GetMacroInfo(id)
        if not name then return nil end
        return {
            type = "macro",
            name = name,
            icon = icon,
            body = body,
            perChar = (id > MAX_ACCOUNT_MACROS),
        }
    end

    -- Anything else (companion, equipmentset, flyout...) is not expected on this
    -- client, but keep it so the slot is at least described in the profile.
    return { type = actionType, id = id, sub = subType }
end

function ns.SaveProfile(rawName)
    local name, err = ns.ValidateName(rawName)
    if not name then
        Print(err)
        return false
    end

    local slots, counts = {}, { spell = 0, item = 0, macro = 0, other = 0, total = 0 }
    for slot = 1, NUM_SLOTS do
        local data = CaptureSlot(slot)
        if data then
            slots[slot] = data
            counts.total = counts.total + 1
            local key = counts[data.type] and data.type or "other"
            counts[key] = counts[key] + 1
        end
    end

    local existing = ns.db.profiles[name]
    local profile = existing or { created = time() }
    profile.name = name
    profile.slots = slots
    profile.counts = counts
    profile.class = ns.class
    profile.classLocalized = ns.classLocalized
    profile.character = ns.charKey
    profile.level = UnitLevel("player")
    profile.updated = time()
    ns.db.profiles[name] = profile

    Print("%s profile |cffffff00%s|r (%d slots: %d spells, %d items, %d macros).",
        existing and "Updated" or "Saved", name, counts.total, counts.spell, counts.item, counts.macro)
    NotifyUI()
    return true
end

function ns.DeleteProfile(name)
    if not ns.db.profiles[name] then
        Print("No profile named |cffffff00%s|r.", tostring(name))
        return false
    end
    ns.db.profiles[name] = nil
    Print("Deleted profile |cffffff00%s|r.", name)
    NotifyUI()
    return true
end

function ns.RenameProfile(oldName, rawNewName)
    local p = ns.db.profiles[oldName]
    if not p then
        Print("No profile named |cffffff00%s|r.", tostring(oldName))
        return false
    end
    local newName, err = ns.ValidateName(rawNewName)
    if not newName then
        Print(err)
        return false
    end
    if newName == oldName then
        return true
    end
    if ns.db.profiles[newName] then
        Print("A profile named |cffffff00%s|r already exists.", newName)
        return false
    end
    ns.db.profiles[newName] = p
    ns.db.profiles[oldName] = nil
    p.name = newName
    Print("Renamed |cffffff00%s|r to |cffffff00%s|r.", oldName, newName)
    NotifyUI()
    return true
end

-------------------------------------------------------------------------------
-- Restore helpers: each returns true when something is on the cursor
-------------------------------------------------------------------------------
local function CursorType()
    return (GetCursorInfo())
end

local function IsKnownSpell(id)
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id) then return true end
    if IsSpellKnown and (IsSpellKnown(id) or IsSpellKnown(id, true)) then return true end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return false
end

local function TryPickupSpell(data, report)
    local candidates = {}
    if data.id and data.id > 0 and IsKnownSpell(data.id) then
        candidates[#candidates + 1] = data.id
    end
    if data.name then
        -- GetSpellInfo(name) resolves to the highest rank this character knows,
        -- which covers lower level characters and different rank choices.
        local knownID = select(7, GetSpellInfo(data.name))
        if knownID and knownID ~= data.id then
            candidates[#candidates + 1] = knownID
        end
    end

    for _, spellID in ipairs(candidates) do
        ClearCursor()
        PickupSpell(spellID)
        if CursorType() == "spell" then
            if spellID ~= data.id then
                report.rankFallback = report.rankFallback + 1
            end
            return true
        end
    end

    -- Pet abilities live in the pet spellbook; match by name.
    if data.name then
        local numPet = HasPetSpells()
        if numPet then
            for i = 1, numPet do
                local petName = GetSpellBookItemName(i, PET_BOOK)
                if petName == data.name then
                    ClearCursor()
                    PickupSpellBookItem(i, PET_BOOK)
                    if CursorType() then
                        return true
                    end
                end
            end
        end
    end

    ClearCursor()
    return false, "spell not known"
end

local function TryPickupItem(data)
    ClearCursor()
    PickupItem(data.id)
    if CursorType() == "item" then return true end

    for bag = 0, 4 do
        local n = GetContainerNumSlots_(bag) or 0
        for bagSlot = 1, n do
            if GetContainerItemID_(bag, bagSlot) == data.id then
                ClearCursor()
                PickupContainerItem_(bag, bagSlot)
                if CursorType() == "item" then return true end
            end
        end
    end

    for inv = 1, 19 do
        if GetInventoryItemID("player", inv) == data.id then
            ClearCursor()
            PickupInventoryItem(inv)
            if CursorType() == "item" then return true end
        end
    end

    ClearCursor()
    return false, "item not in bags or equipped"
end

local function TryPickupMacro(data, opts, report)
    local index = GetMacroIndexByName(data.name) or 0

    if index == 0 and opts.createMissingMacros and data.body then
        local numGlobal, numChar = GetNumMacros()
        local perChar = data.perChar and true or false
        -- Fall back to whichever macro pool still has room.
        if perChar and numChar >= MAX_CHARACTER_MACROS then perChar = false end
        if not perChar and numGlobal >= MAX_ACCOUNT_MACROS then perChar = true end
        local hasRoom = (perChar and numChar < MAX_CHARACTER_MACROS)
            or (not perChar and numGlobal < MAX_ACCOUNT_MACROS)
        if hasRoom then
            index = CreateMacro(data.name, data.icon or QUESTION_MARK_ICON, data.body, perChar) or 0
            if index > 0 then
                report.macrosCreated = report.macrosCreated + 1
            end
        else
            return false, "macro missing and no free macro slots"
        end
    end

    if index > 0 then
        ClearCursor()
        PickupMacro(index)
        if CursorType() == "macro" then return true end
    end

    ClearCursor()
    return false, "macro not found"
end

local function PickupForSlot(data, opts, report)
    if data.type == "spell" then
        return TryPickupSpell(data, report)
    elseif data.type == "item" then
        return TryPickupItem(data)
    elseif data.type == "macro" then
        return TryPickupMacro(data, opts, report)
    end
    return false, "unsupported action type '" .. tostring(data.type) .. "'"
end

local function ClearSlot(slot)
    if HasAction(slot) then
        ClearCursor()
        PickupAction(slot)
        ClearCursor()
    end
end

local function DescribeSlotData(data)
    if data.type == "spell" then
        local s = data.name or ("spell " .. tostring(data.id))
        if data.rank and data.rank ~= "" then s = s .. " (" .. data.rank .. ")" end
        return s
    elseif data.type == "item" then
        return (data.name or GetItemInfo(data.id or 0) or ("item " .. tostring(data.id)))
    elseif data.type == "macro" then
        return "macro \"" .. tostring(data.name) .. "\""
    end
    return tostring(data.type) .. " " .. tostring(data.id)
end
ns.DescribeSlotData = DescribeSlotData

-------------------------------------------------------------------------------
-- Load
-------------------------------------------------------------------------------
local function DoLoad(name)
    local profile = ns.db.profiles[name]
    local opts = ns.db.options
    local report = { placed = 0, cleared = 0, skipped = {}, macrosCreated = 0, rankFallback = 0 }

    ClearCursor()
    for slot = 1, NUM_SLOTS do
        local data = profile.slots[slot]
        if data then
            ClearSlot(slot)
            local ok, reason = PickupForSlot(data, opts, report)
            if ok then
                PlaceAction(slot)
                ClearCursor()
                if HasAction(slot) then
                    report.placed = report.placed + 1
                else
                    report.skipped[#report.skipped + 1] = { slot = slot, data = data, reason = "could not be placed" }
                end
            else
                report.skipped[#report.skipped + 1] = { slot = slot, data = data, reason = reason }
            end
        elseif opts.clearBeforeLoad and HasAction(slot) then
            ClearSlot(slot)
            report.cleared = report.cleared + 1
        end
    end
    ClearCursor()

    ns.db.lastLoaded = ns.db.lastLoaded or {}
    ns.db.lastLoaded[ns.charKey] = name

    Print("Loaded |cffffff00%s|r: %d slots placed, %d skipped.", name, report.placed, #report.skipped)
    if report.macrosCreated > 0 then
        Print("Created %d missing macro(s).", report.macrosCreated)
    end
    if report.rankFallback > 0 then
        Print("%d spell(s) were placed using the highest rank this character knows.", report.rankFallback)
    end
    for _, s in ipairs(report.skipped) do
        Print("  slot %d: %s - %s", s.slot, DescribeSlotData(s.data), s.reason)
    end
    NotifyUI()
    return report
end

function ns.LoadProfile(name)
    local profile = ns.db.profiles[name]
    if not profile then
        Print("No profile named |cffffff00%s|r.", tostring(name))
        return false
    end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        ns.pendingLoad = name
        Print("You are in combat. |cffffff00%s|r will be loaded when combat ends.", name)
        return false
    end
    if profile.class and profile.class ~= ns.class then
        Print("Note: |cffffff00%s|r was saved on a %s. Abilities this character does not know will be skipped.",
            name, profile.classLocalized or profile.class)
    end
    return DoLoad(name)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        InitCharacter()
        if not ns.db then InitDB() end
        NotifyUI()
    elseif event == "PLAYER_REGEN_ENABLED" and ns.pendingLoad then
        local name = ns.pendingLoad
        ns.pendingLoad = nil
        ns.LoadProfile(name)
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function ShowHelp()
    Print("Commands:")
    Print("  /bc  - open the profile window")
    Print("  /bc save <name>  - save current bars as <name> (overwrites)")
    Print("  /bc load <name>  - load <name> onto your bars")
    Print("  /bc delete <name>  - delete <name>")
    Print("  /bc list  - list all profiles")
end

SLASH_BARCLONE1 = "/barclone"
SLASH_BARCLONE2 = "/bc"
SlashCmdList.BARCLONE = function(msg)
    msg = Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    rest = Trim(rest)

    if cmd == "" then
        if ns.ToggleUI then ns.ToggleUI() else ShowHelp() end
    elseif cmd == "save" then
        ns.SaveProfile(rest)
    elseif cmd == "load" then
        ns.LoadProfile(rest)
    elseif cmd == "delete" or cmd == "del" then
        ns.DeleteProfile(rest)
    elseif cmd == "list" then
        local names = ns.GetProfileNames(false)
        if #names == 0 then
            Print("No profiles saved yet.")
        else
            Print("%d profile(s):", #names)
            for _, n in ipairs(names) do
                local p = ns.db.profiles[n]
                local _, _, _, hex = ns.ClassColor(p.class)
                Print("  |cffffff00%s|r  %s%s|r  %s  (%d slots)", n, hex, p.classLocalized or p.class or "?",
                    p.character or "?", p.counts and p.counts.total or 0)
            end
        end
    else
        ShowHelp()
    end
end
