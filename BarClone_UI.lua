-------------------------------------------------------------------------------
-- BarClone - profile window
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local NUM_ROWS = 12
local ROW_HEIGHT = 20
local FRAME_W, FRAME_H = 420, 500

local selected -- currently selected profile name

-------------------------------------------------------------------------------
-- Confirmation popups
-------------------------------------------------------------------------------
StaticPopupDialogs["BARCLONE_CONFIRM_LOAD"] = {
    text = "Load profile |cffffff00%s|r onto your action bars?%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data) ns.LoadProfile(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
StaticPopupDialogs["BARCLONE_CONFIRM_OVERWRITE"] = {
    text = "Overwrite profile |cffffff00%s|r with your current action bars?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data) ns.SaveProfile(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
StaticPopupDialogs["BARCLONE_CONFIRM_DELETE"] = {
    text = "Delete profile |cffffff00%s|r? This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if selected == data then selected = nil end
        ns.DeleteProfile(data)
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Main frame
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "BarCloneFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(FRAME_W, FRAME_H)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:Hide()
tinsert(UISpecialFrames, "BarCloneFrame") -- Escape closes it

-- Title
local titleBg = frame:CreateTexture(nil, "ARTWORK")
titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBg:SetSize(300, 64)
titleBg:SetPoint("TOP", 0, 12)
local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
title:SetPoint("TOP", titleBg, "TOP", 0, -14)
title:SetText("BarClone")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- Character line
local charText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
charText:SetPoint("TOPLEFT", 20, -32)
charText:SetJustifyH("LEFT")

-- Class filter checkbox
local classFilter = CreateFrame("CheckButton", "BarCloneClassFilter", frame, "UICheckButtonTemplate")
classFilter:SetSize(24, 24)
classFilter:SetPoint("TOPRIGHT", -110, -28)
_G[classFilter:GetName() .. "Text"]:SetText("Only my class")
classFilter:SetScript("OnClick", function(self)
    ns.db.options.onlyMyClass = self:GetChecked() and true or false
    ns.RefreshUI()
end)

-- List background
local listBg = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
listBg:SetPoint("TOPLEFT", 16, -54)
listBg:SetPoint("RIGHT", -16, 0)
listBg:SetHeight(NUM_ROWS * ROW_HEIGHT + 8)
listBg:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
listBg:SetBackdropColor(0, 0, 0, 0.5)
listBg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

local scroll = CreateFrame("ScrollFrame", "BarCloneScrollFrame", listBg, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 4, -4)
scroll:SetPoint("BOTTOMRIGHT", -26, 4)
scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, ns.RefreshUI)
end)

local emptyText = listBg:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
emptyText:SetPoint("CENTER")
emptyText:SetText("No profiles yet.\nType a name below and click Save New.")
emptyText:SetJustifyH("CENTER")

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
local rows = {}

local function ShowRowTooltip(row)
    local p = row.profile and ns.GetProfile(row.profile)
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(p.name, 1, 0.82, 0)
    local r, g, b = ns.ClassColor(p.class)
    GameTooltip:AddDoubleLine("Class", p.classLocalized or p.class or "?", 0.8, 0.8, 0.8, r, g, b)
    GameTooltip:AddDoubleLine("Saved by", (p.character or "?") .. (p.level and (" (Lv " .. p.level .. ")") or ""),
        0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Updated", ns.FormatDate(p.updated), 0.8, 0.8, 0.8, 1, 1, 1)
    if p.counts then
        GameTooltip:AddDoubleLine("Slots used", tostring(p.counts.total or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Spells / Items / Macros",
            ("%d / %d / %d"):format(p.counts.spell or 0, p.counts.item or 0, p.counts.macro or 0),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    if ns.db.lastLoaded and ns.db.lastLoaded[ns.charKey] == p.name then
        GameTooltip:AddLine("Last loaded on this character", 0.2, 1, 0.2)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to select, double-click to load.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function OnRowClick(self)
    if not self.profile then return end
    selected = self.profile
    frame.nameBox:SetText(self.profile)
    ns.RefreshUI()
end

local function OnRowDoubleClick(self)
    if not self.profile then return end
    selected = self.profile
    ns.RefreshUI()
    frame.RequestLoad(self.profile)
end

for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", "BarCloneRow" .. i, listBg)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scroll, "RIGHT", -2, 0)
    row:RegisterForClicks("LeftButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetColorTexture(1, 0.82, 0, 0.2)
    row.selected = sel

    local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("LEFT", 6, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    info:SetPoint("RIGHT", -6, 0)
    info:SetWidth(145)
    info:SetJustifyH("RIGHT")
    info:SetWordWrap(false)
    row.info = info

    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnDoubleClick", OnRowDoubleClick)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
end

-------------------------------------------------------------------------------
-- Name entry + buttons
-------------------------------------------------------------------------------
local nameLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
nameLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 4, -12)
nameLabel:SetText("Profile name")

local nameBox = CreateFrame("EditBox", "BarCloneNameBox", frame, "InputBoxTemplate")
nameBox:SetSize(190, 22)
nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(40)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); frame.RequestSaveNew() end)
frame.nameBox = nameBox

local function MakeButton(text, width, parent)
    local b = CreateFrame("Button", nil, parent or frame, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    return b
end

local saveNewBtn = MakeButton("Save New", 100)
saveNewBtn:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)

local renameBtn = MakeButton("Rename", 60)
renameBtn:SetPoint("LEFT", saveNewBtn, "RIGHT", 4, 0)

local loadBtn = MakeButton("Load", 90)
loadBtn:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -12)

local overwriteBtn = MakeButton("Overwrite", 90)
overwriteBtn:SetPoint("LEFT", loadBtn, "RIGHT", 6, 0)

local deleteBtn = MakeButton("Delete", 90)
deleteBtn:SetPoint("LEFT", overwriteBtn, "RIGHT", 6, 0)

-- Options
local function MakeCheck(name, label, optionKey, anchor, yOff)
    local cb = CreateFrame("CheckButton", name, frame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.db.options[optionKey] = self:GetChecked() and true or false
    end)
    cb.optionKey = optionKey
    return cb
end

local clearCheck = MakeCheck("BarCloneClearCheck", "Clear slots that are empty in the profile", "clearBeforeLoad", loadBtn, -14)
local macroCheck = MakeCheck("BarCloneMacroCheck", "Create macros this character is missing", "createMissingMacros", clearCheck, -2)

local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 20, 18)
hint:SetPoint("RIGHT", -20, 0)
hint:SetJustifyH("LEFT")
hint:SetText("/bc save <name>, /bc load <name>, /bc delete <name>, /bc list")

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
function frame.RequestSaveNew()
    local name, err = ns.ValidateName(nameBox:GetText())
    if not name then
        ns.Print(err)
        return
    end
    if ns.GetProfile(name) then
        StaticPopup_Show("BARCLONE_CONFIRM_OVERWRITE", name, nil, name)
    else
        if ns.SaveProfile(name) then
            selected = name
            ns.RefreshUI()
        end
    end
end

function frame.RequestLoad(name)
    local p = name and ns.GetProfile(name)
    if not p then return end
    local warning = ""
    if p.class and p.class ~= ns.class then
        warning = ("\n\n|cffff6060This profile was saved on a %s. Abilities this character does not know will be skipped.|r")
            :format(p.classLocalized or p.class)
    end
    if ns.db.options.clearBeforeLoad then
        warning = warning .. "\n\n|cffaaaaaaSlots that are empty in the profile will be cleared.|r"
    end
    StaticPopup_Show("BARCLONE_CONFIRM_LOAD", name, warning, name)
end

saveNewBtn:SetScript("OnClick", frame.RequestSaveNew)

renameBtn:SetScript("OnClick", function()
    if not selected then return end
    local newName = nameBox:GetText()
    if ns.RenameProfile(selected, newName) then
        selected = ns.Trim(newName)
        ns.RefreshUI()
    end
end)

loadBtn:SetScript("OnClick", function() frame.RequestLoad(selected) end)

overwriteBtn:SetScript("OnClick", function()
    if not selected then return end
    StaticPopup_Show("BARCLONE_CONFIRM_OVERWRITE", selected, nil, selected)
end)

deleteBtn:SetScript("OnClick", function()
    if not selected then return end
    StaticPopup_Show("BARCLONE_CONFIRM_DELETE", selected, nil, selected)
end)

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
function ns.RefreshUI()
    if not ns.db or not frame:IsShown() then return end
    local opts = ns.db.options

    local _, _, _, hex = ns.ClassColor(ns.class)
    charText:SetText(("%s%s|r  -  %s"):format(hex, ns.classLocalized or "?", ns.charKey or "?"))
    classFilter:SetChecked(opts.onlyMyClass)
    clearCheck:SetChecked(opts.clearBeforeLoad)
    macroCheck:SetChecked(opts.createMissingMacros)

    local names = ns.GetProfileNames(opts.onlyMyClass)
    if selected and not ns.GetProfile(selected) then
        selected = nil
    end

    FauxScrollFrame_Update(scroll, #names, NUM_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)

    for i = 1, NUM_ROWS do
        local row = rows[i]
        local name = names[i + offset]
        if name then
            local p = ns.db.profiles[name]
            local _, _, _, chex = ns.ClassColor(p.class)
            row.profile = name
            row.name:SetText(name)
            local charShort = (p.character or "?"):match("^([^%-]+)") or "?"
            row.info:SetText(("%s%s|r  %s"):format(chex, p.classLocalized or p.class or "?", charShort))
            if name == selected then row.selected:Show() else row.selected:Hide() end
            row:Show()
        else
            row.profile = nil
            row:Hide()
        end
    end

    if #names == 0 then emptyText:Show() else emptyText:Hide() end

    local hasSel = selected ~= nil
    loadBtn:SetEnabled(hasSel)
    overwriteBtn:SetEnabled(hasSel)
    deleteBtn:SetEnabled(hasSel)
    renameBtn:SetEnabled(hasSel)
end

frame:SetScript("OnShow", function()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
    ns.RefreshUI()
end)
frame:SetScript("OnHide", function()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
end)

function ns.ToggleUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function ns.ShowUI()
    frame:Show()
end
