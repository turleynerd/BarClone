-------------------------------------------------------------------------------
-- BarClone - profile window
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local NUM_ROWS = 12
local ROW_HEIGHT = 20
local FRAME_W, FRAME_H = 420, 530

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

local exportBtn = MakeButton("Export", 90)
exportBtn:SetPoint("TOPLEFT", loadBtn, "BOTTOMLEFT", 0, -6)

local importBtn = MakeButton("Import", 90)
importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)

local shareHint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
shareHint:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
shareHint:SetPoint("RIGHT", -20, 0)
shareHint:SetJustifyH("LEFT")
shareHint:SetText("Share codes across accounts")

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

local clearCheck = MakeCheck("BarCloneClearCheck", "Clear slots that are empty in the profile", "clearBeforeLoad", exportBtn, -14)
local macroCheck = MakeCheck("BarCloneMacroCheck", "Create macros this character is missing", "createMissingMacros", clearCheck, -2)

local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 20, 18)
hint:SetPoint("RIGHT", -20, 0)
hint:SetJustifyH("LEFT")
hint:SetText("/bc save|load|delete|export <name>, /bc import, /bc list")

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

exportBtn:SetScript("OnClick", function()
    if not selected then return end
    ns.ShowExport(selected)
end)

importBtn:SetScript("OnClick", function() ns.ShowImport() end)

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
    exportBtn:SetEnabled(hasSel)
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

-------------------------------------------------------------------------------
-- Export / Import dialog
-------------------------------------------------------------------------------
StaticPopupDialogs["BARCLONE_CONFIRM_IMPORT_OVERWRITE"] = {
    text = "A profile named |cffffff00%s|r already exists. Replace it with the imported one?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data) ns.FinishImport(data.profile, data.name) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

local TEXT_W, TEXT_H = 480, 400

local textFrame = CreateFrame("Frame", "BarCloneTextFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
textFrame:SetSize(TEXT_W, TEXT_H)
textFrame:SetPoint("CENTER", 0, 40)
textFrame:SetFrameStrata("DIALOG")
textFrame:SetFrameLevel(frame:GetFrameLevel() + 20)
textFrame:SetMovable(true)
textFrame:EnableMouse(true)
textFrame:SetClampedToScreen(true)
textFrame:RegisterForDrag("LeftButton")
textFrame:SetScript("OnDragStart", textFrame.StartMoving)
textFrame:SetScript("OnDragStop", textFrame.StopMovingOrSizing)
textFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
textFrame:Hide()
tinsert(UISpecialFrames, "BarCloneTextFrame")

local tfTitleBg = textFrame:CreateTexture(nil, "ARTWORK")
tfTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
tfTitleBg:SetSize(300, 64)
tfTitleBg:SetPoint("TOP", 0, 12)
local tfTitle = textFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
tfTitle:SetPoint("TOP", tfTitleBg, "TOP", 0, -14)

local tfClose = CreateFrame("Button", nil, textFrame, "UIPanelCloseButton")
tfClose:SetPoint("TOPRIGHT", -5, -5)

local tfHint = textFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
tfHint:SetPoint("TOPLEFT", 20, -34)
tfHint:SetPoint("RIGHT", -20, 0)
tfHint:SetJustifyH("LEFT")

-- Text area
local tfBox = CreateFrame("Frame", nil, textFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
tfBox:SetPoint("TOPLEFT", 16, -58)
tfBox:SetPoint("BOTTOMRIGHT", -16, 96)
tfBox:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
tfBox:SetBackdropColor(0, 0, 0, 0.6)
tfBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

local tfScroll = CreateFrame("ScrollFrame", "BarCloneTextScroll", tfBox, "UIPanelScrollFrameTemplate")
tfScroll:SetPoint("TOPLEFT", 8, -8)
tfScroll:SetPoint("BOTTOMRIGHT", -28, 8)

local tfEdit = CreateFrame("EditBox", "BarCloneTextEdit", tfScroll)
tfEdit:SetMultiLine(true)
tfEdit:SetAutoFocus(false)
tfEdit:SetFontObject(ChatFontNormal)
tfEdit:SetWidth(TEXT_W - 32 - 16 - 28)
tfEdit:SetMaxLetters(0)
tfEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
tfScroll:SetScrollChild(tfEdit)
-- Clicking anywhere in the box focuses the edit box, even below the text.
tfScroll:EnableMouse(true)
tfScroll:SetScript("OnMouseDown", function() tfEdit:SetFocus() end)

-- Import controls
local tfStatus = textFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
tfStatus:SetPoint("BOTTOMLEFT", 20, 74)
tfStatus:SetPoint("RIGHT", -20, 0)
tfStatus:SetJustifyH("LEFT")

local tfNameLabel = textFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
tfNameLabel:SetPoint("BOTTOMLEFT", 20, 46)
tfNameLabel:SetText("Save as")

local tfNameBox = CreateFrame("EditBox", "BarCloneImportNameBox", textFrame, "InputBoxTemplate")
tfNameBox:SetSize(200, 22)
tfNameBox:SetPoint("LEFT", tfNameLabel, "RIGHT", 10, 0)
tfNameBox:SetAutoFocus(false)
tfNameBox:SetMaxLetters(40)
tfNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local tfImportBtn = MakeButton("Import", 100, textFrame)
tfImportBtn:SetPoint("BOTTOMRIGHT", -20, 40)

local tfCloseBtn = MakeButton("Close", 80, textFrame)
tfCloseBtn:SetPoint("BOTTOMRIGHT", -20, 16)
tfCloseBtn:SetScript("OnClick", function() textFrame:Hide() end)

local function SetImportWidgetsShown(shown)
    tfStatus:SetShown(shown)
    tfNameLabel:SetShown(shown)
    tfNameBox:SetShown(shown)
    tfImportBtn:SetShown(shown)
end

local function DescribeDecoded(p)
    local _, _, _, hex = ns.ClassColor(p.class)
    return ("|cff33ff99Valid:|r |cffffff00%s|r  %s%s|r  %d slots (%d spells, %d items, %d macros)%s"):format(
        p.name, hex, p.classLocalized or p.class or "unknown class",
        p.counts.total, p.counts.spell, p.counts.item, p.counts.macro,
        p.character and ("  from " .. p.character) or "")
end

local function ValidateImportText()
    if textFrame.mode ~= "import" then return end
    local text = tfEdit:GetText()
    textFrame.decoded = nil
    if ns.Trim(text) == "" then
        tfStatus:SetText("|cffaaaaaaPaste a BarClone export code into the box above (Ctrl+V).|r")
        tfImportBtn:SetEnabled(false)
        return
    end
    local profile, err = ns.DecodeProfile(text)
    if profile then
        textFrame.decoded = profile
        tfStatus:SetText(DescribeDecoded(profile))
        if ns.Trim(tfNameBox:GetText()) == "" or tfNameBox.autoFilled then
            tfNameBox:SetText(profile.name)
            tfNameBox.autoFilled = true
        end
        tfImportBtn:SetEnabled(true)
    else
        tfStatus:SetText("|cffff6060" .. tostring(err) .. "|r")
        tfImportBtn:SetEnabled(false)
    end
end

tfEdit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then ValidateImportText() end
end)
tfNameBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self.autoFilled = false end
end)

function ns.FinishImport(profile, name)
    if ns.ImportProfile(profile, name) then
        selected = ns.Trim(name)
        textFrame:Hide()
        if frame:IsShown() then ns.RefreshUI() end
    end
end

tfImportBtn:SetScript("OnClick", function()
    local profile = textFrame.decoded
    if not profile then return end
    local name, err = ns.ValidateName(tfNameBox:GetText())
    if not name then
        ns.Print(err)
        return
    end
    if ns.GetProfile(name) then
        StaticPopup_Show("BARCLONE_CONFIRM_IMPORT_OVERWRITE", name, nil, { profile = profile, name = name })
    else
        ns.FinishImport(profile, name)
    end
end)
tfNameBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    tfImportBtn:Click()
end)

function ns.ShowExport(name)
    local code, err = ns.ExportProfile(name)
    if not code then
        ns.Print(err)
        return
    end
    textFrame.mode = "export"
    textFrame.decoded = nil
    tfTitle:SetText("Export: " .. name)
    tfHint:SetText("Press Ctrl+C to copy the code. Paste it into Import on any account or share it.")
    SetImportWidgetsShown(false)
    tfEdit:SetText(code)
    tfEdit:SetCursorPosition(0)
    textFrame:Show()
    tfEdit:SetFocus()
    tfEdit:HighlightText()
end

function ns.ShowImport()
    textFrame.mode = "import"
    textFrame.decoded = nil
    tfTitle:SetText("Import profile")
    tfHint:SetText("Paste an export code below. The profile is checked before anything is saved.")
    SetImportWidgetsShown(true)
    tfEdit:SetText("")
    tfNameBox:SetText("")
    tfNameBox.autoFilled = true
    ValidateImportText()
    textFrame:Show()
    tfEdit:SetFocus()
end

-- Re-select everything when the export box regains focus so Ctrl+C always copies the full code.
tfEdit:SetScript("OnEditFocusGained", function(self)
    if textFrame.mode == "export" then self:HighlightText() end
end)

textFrame:SetScript("OnHide", function()
    tfEdit:ClearFocus()
    tfEdit:SetText("")
    textFrame.decoded = nil
end)
