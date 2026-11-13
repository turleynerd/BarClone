-------------------------------------------------------------------------------
-- BarClone - client compatibility layer
--
-- BarClone runs on two very different clients:
--   * TBC Anniversary (Interface 20506): classic-style global API
--     (GetSpellInfo, GetItemInfo, GetSpellBookItemName, ...)
--   * WoW Forever (Interface 16001): Mainline-family API where those globals
--     are gone and C_Spell / C_Item / C_SpellBook take their place.
--
-- Everything that differs between them lives here. The rest of the addon only
-- calls the ns.* wrappers defined in this file.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local tocVersion = select(4, GetBuildInfo()) or 0
ns.tocVersion = tocVersion
ns.IsForever = tocVersion >= 16000 and tocVersion < 20000
ns.IsModernAPI = (C_Spell ~= nil and C_Spell.GetSpellInfo ~= nil)

if ns.IsForever then
    ns.FlavorName = "WoW Forever"
elseif tocVersion >= 100000 then
    ns.FlavorName = "Retail"
elseif tocVersion >= 20000 and tocVersion < 30000 then
    ns.FlavorName = "TBC Anniversary"
else
    ns.FlavorName = "Interface " .. tocVersion
end

-- Modern clients have eight action bars (slots 1-180); classic clients have 120.
ns.MAX_SLOTS = ns.IsModernAPI and 180 or 120

-------------------------------------------------------------------------------
-- Secret values (Forever / Retail can hand addons values they may not inspect)
-------------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

-- Returns `value` unless it is nil or secret, in which case `fallback`.
function ns.Safe(value, fallback)
    if value == nil or issecret(value) then
        return fallback
    end
    return value
end

-------------------------------------------------------------------------------
-- Spells
-------------------------------------------------------------------------------
local C_Spell, C_SpellBook, C_Item, Enum = C_Spell, C_SpellBook, C_Item, Enum

local function RankNumber(subtext)
    return tonumber((subtext or ""):match("%d+")) or 0
end

if ns.IsModernAPI then
    local GetSubtext = C_Spell.GetSpellSubtext or GetSpellSubtext

    -- name, rank, icon, spellID
    function ns.GetSpellInfo(spell)
        local info = C_Spell.GetSpellInfo(spell)
        if not info then return nil end
        local rank = GetSubtext and GetSubtext(info.spellID) or nil
        return info.name, rank, info.iconID, info.spellID
    end
else
    function ns.GetSpellInfo(spell)
        local name, rank, icon, _, _, _, id = GetSpellInfo(spell)
        if not name then return nil end
        return name, rank, icon, id
    end
end

function ns.IsKnownSpell(id)
    if not id or id == 0 then return false end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id) then return true end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    if IsSpellKnown and (IsSpellKnown(id) or IsSpellKnown(id, true)) then return true end
    return false
end

-- Scans the player's spellbook for the highest rank of `name` they know.
-- Returns spellID or nil.
if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetNumSpellBookSkillLines then
    local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local TYPE_SPELL = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1

    function ns.FindKnownSpellByName(name)
        if not name then return nil end
        local best, bestRank = nil, -1
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li and li.numSpellBookItems then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(i, PLAYER_BANK)
                    if info and info.itemType == TYPE_SPELL and not info.isOffSpec and not info.isPassive
                        and info.spellID and info.name == name then
                        local rank = RankNumber(info.subName)
                        if rank >= bestRank then
                            best, bestRank = info.spellID, rank
                        end
                    end
                end
            end
        end
        return best
    end
else
    local BOOK = BOOKTYPE_SPELL or "spell"

    function ns.FindKnownSpellByName(name)
        if not name or not GetNumSpellTabs then return nil end
        local best, bestRank = nil, -1
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
                local kind, id = GetSpellBookItemInfo(i, BOOK)
                if kind == "SPELL" and id then
                    local sName, sRank = GetSpellBookItemName(i, BOOK)
                    if sName == name then
                        local rank = RankNumber(sRank)
                        if rank >= bestRank then
                            best, bestRank = id, rank
                        end
                    end
                end
            end
        end
        return best
    end
end

-------------------------------------------------------------------------------
-- Pet spellbook
-------------------------------------------------------------------------------
if C_SpellBook and C_SpellBook.GetSpellBookItemName and Enum and Enum.SpellBookSpellBank then
    local PET_BANK = Enum.SpellBookSpellBank.Pet
    local HasPet = C_SpellBook.HasPetSpells or HasPetSpells

    function ns.HasPetSpells()
        if not HasPet then return nil end
        return (HasPet())
    end

    function ns.GetPetSpellName(index)
        return (C_SpellBook.GetSpellBookItemName(index, PET_BANK))
    end

    function ns.PickupPetSpell(index)
        if C_SpellBook.PickupSpellBookItem then
            C_SpellBook.PickupSpellBookItem(index, PET_BANK)
        end
    end
else
    local PET_BOOK = BOOKTYPE_PET or "pet"

    function ns.HasPetSpells()
        if not HasPetSpells then return nil end
        return (HasPetSpells())
    end

    function ns.GetPetSpellName(index)
        return (GetSpellBookItemName(index, PET_BOOK))
    end

    function ns.PickupPetSpell(index)
        PickupSpellBookItem(index, PET_BOOK)
    end
end

-------------------------------------------------------------------------------
-- Items and containers
-------------------------------------------------------------------------------
local GetItemInfo_ = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local PickupItem_ = PickupItem or (C_Item and C_Item.PickupItem)

function ns.GetItemName(itemID)
    if not GetItemInfo_ or not itemID then return nil end
    return (GetItemInfo_(itemID))
end

function ns.PickupItem(itemID)
    if PickupItem_ then
        PickupItem_(itemID)
    end
end

ns.GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
ns.GetContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
ns.PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

-------------------------------------------------------------------------------
-- UI templates
-------------------------------------------------------------------------------
-- UICheckButtonTemplate exposes its label as .Text on modern clients and as a
-- "$parentText" global on classic ones.
function ns.CheckButtonText(cb)
    return cb.Text or cb.text or (cb:GetName() and _G[cb:GetName() .. "Text"]) or nil
end
