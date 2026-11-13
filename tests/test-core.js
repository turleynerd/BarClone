// Loads BarClone_Compat.lua + BarClone.lua + BarClone_Serialize.lua into a mocked WoW
// environment (classic-style API like TBC 20506, or modern API like Forever 16001)
// and exercises save -> clear -> load, rank fallback, macro creation, pets, items,
// cross-client slot counts, and export/import between the two.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const fs = require("fs");

const DIR = require("path").join(__dirname, "..") + "/";
const files = ["BarClone_Compat.lua", "BarClone.lua", "BarClone_Serialize.lua"].map((f) => fs.readFileSync(DIR + f, "utf8"));

const harness = `
local MODE = ...  -- "classic" or "modern"
printed = {}

local function makeEnv()
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.printed = printed

  -- ---------------- state ----------------
  local S = {
    bar = {},            -- slot -> {type=, id=, sub=}
    cursor = nil,        -- {type=, id=}
    known = {},          -- spellID -> true (player book)
    book = {},           -- ordered {id=, name=, rank=}
    pet = {},            -- ordered {id=, name=}
    macros = {},         -- index -> {name=, icon=, body=, perChar=}
    bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} },
    inv = {},
    combat = false,
    spells = {},         -- id -> {name=, rank=}
    items = {},          -- id -> name
  }
  env.STATE = S

  local function pickSpell(id)
    local sp = S.spells[id]
    if sp and S.known[id] then S.cursor = { type = "spell", id = id } end
  end

  -- ---------------- common API ----------------
  env.HasAction = function(slot) return S.bar[slot] ~= nil end
  env.GetActionInfo = function(slot) local a = S.bar[slot]; if a then return a.type, a.id, a.sub end end
  env.PickupAction = function(slot) local a = S.bar[slot]; S.bar[slot] = nil; S.cursor = a end
  env.PlaceAction = function(slot) if S.cursor then local old = S.bar[slot]; S.bar[slot] = S.cursor; S.cursor = old end end
  env.ClearCursor = function() S.cursor = nil end
  env.GetCursorInfo = function() if S.cursor then return S.cursor.type, S.cursor.id end end
  env.PickupSpell = pickSpell
  env.IsSpellKnownOrOverridesKnown = function(id) return S.known[id] == true end
  env.IsPlayerSpell = function(id) return S.known[id] == true end
  env.GetMacroInfo = function(i) local m = S.macros[i]; if m then return m.name, m.icon, m.body end end
  env.GetMacroIndexByName = function(n) for i, m in pairs(S.macros) do if m.name == n then return i end end return 0 end
  env.GetNumMacros = function() local g, c = 0, 0; for i in pairs(S.macros) do if i > 120 then c = c + 1 else g = g + 1 end end return g, c end
  env.CreateMacro = function(name, icon, body, perChar)
    local base = perChar and 120 or 0
    for i = base + 1, base + (perChar and 30 or 120) do
      if not S.macros[i] then S.macros[i] = { name = name, icon = icon, body = body, perChar = perChar }; return i end
    end
  end
  env.PickupMacro = function(i) if S.macros[i] then S.cursor = { type = "macro", id = i } end end
  env.GetInventoryItemID = function(_, slot) return S.inv[slot] end
  env.PickupInventoryItem = function(slot) if S.inv[slot] then S.cursor = { type = "item", id = S.inv[slot] } end end
  env.InCombatLockdown = function() return S.combat end
  env.UnitName = function() return "Tester" end
  env.GetRealmName = function() return "Realm" end
  env.UnitClass = function() return "Warrior", "WARRIOR" end
  env.UnitLevel = function() return 60 end
  env.GetBuildInfo = function() if MODE == "modern" then return "1.60.1", "70338", "", 16001 else return "2.5.5", "60000", "", 20506 end end
  env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" } }
  env.SlashCmdList = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
  env.time = os.time
  env.date = os.date
  local handlers = {}
  env.HANDLERS = handlers
  env.CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript(_, fn) handlers[#handlers + 1] = fn end
    return f
  end
  env.issecretvalue = function() return false end

  local function findByName(name, highest)
    local best, bestRank = nil, highest and -1 or 1e9
    for _, e in ipairs(S.book) do
      if e.name == name and S.known[e.id] then
        local r = tonumber((e.rank or ""):match("%d+")) or 0
        if (highest and r >= bestRank) or (not highest and r <= bestRank) then best, bestRank = e.id, r end
      end
    end
    return best
  end

  local function containerAPI()
    return {
      GetContainerNumSlots = function(bag) return 16 end,
      GetContainerItemID = function(bag, slot) return S.bags[bag] and S.bags[bag][slot] end,
      PickupContainerItem = function(bag, slot) local id = S.bags[bag] and S.bags[bag][slot]; if id then S.cursor = { type = "item", id = id } end end,
    }
  end

  if MODE == "modern" then
    env.MAX_ACCOUNT_MACROS, env.MAX_CHARACTER_MACROS = 120, 30
    env.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 } }
    env.C_Spell = {
      GetSpellInfo = function(x)
        local id = x
        if type(x) == "string" then id = findByName(x, false) end -- deliberately the LOWEST rank, like a naive name lookup
        local sp = id and S.spells[id]
        if sp then return { name = sp.name, spellID = id, iconID = 1 } end
      end,
      GetSpellSubtext = function(id) local sp = S.spells[id]; return sp and sp.rank or nil end,
    }
    env.C_SpellBook = {
      GetNumSpellBookSkillLines = function() return 2 end,
      GetSpellBookSkillLineInfo = function(i)
        local half = math.ceil(#S.book / 2)
        if i == 1 then return { itemIndexOffset = 0, numSpellBookItems = half } end
        return { itemIndexOffset = half, numSpellBookItems = #S.book - half }
      end,
      GetSpellBookItemInfo = function(i, bank)
        local e = S.book[i]
        if not e then return nil end
        if not S.known[e.id] then return { itemType = 2, name = e.name, subName = e.rank, actionID = e.id } end
        return { itemType = 1, spellID = e.id, actionID = e.id, name = e.name, subName = e.rank, isPassive = false, isOffSpec = false }
      end,
      GetSpellBookItemName = function(i, bank)
        if bank == 1 then local p = S.pet[i]; return p and p.name end
        local e = S.book[i]; return e and e.name, e and e.rank
      end,
      PickupSpellBookItem = function(i, bank) if bank == 1 and S.pet[i] then S.cursor = { type = "spell", id = S.pet[i].id } end end,
      HasPetSpells = function() if #S.pet > 0 then return #S.pet, "PET" end end,
      IsSpellKnown = function(id) return S.known[id] == true end,
    }
    env.C_Item = { GetItemInfo = function(id) return S.items[id] end, PickupItem = function(id) for b, t in pairs(S.bags) do for _, iid in pairs(t) do if iid == id then S.cursor = { type = "item", id = id }; return end end end end }
    env.C_Container = containerAPI()
    -- Globals that do NOT exist on Forever: make sure nothing touches them.
    for _, g in ipairs({ "GetSpellInfo", "GetItemInfo", "GetSpellBookItemName", "GetContainerNumSlots", "HasPetSpells", "PickupSpellBookItem", "GetNumSpellTabs" }) do
      env[g] = nil
      rawset(env, g, nil)
    end
    setmetatable(env, { __index = function(_, k)
      if k == "GetSpellInfo" or k == "GetItemInfo" or k == "GetSpellBookItemName" or k == "GetContainerNumSlots"
        or k == "HasPetSpells" or k == "PickupSpellBookItem" or k == "GetNumSpellTabs" or k == "PickupItem" then
        return nil
      end
      return _G[k]
    end })
  else
    env.MAX_ACCOUNT_MACROS, env.MAX_CHARACTER_MACROS = 120, 18
    env.BOOKTYPE_SPELL, env.BOOKTYPE_PET = "spell", "pet"
    env.GetSpellInfo = function(x)
      local id = x
      if type(x) == "string" then id = findByName(x, true) end -- classic returns the highest known rank
      local sp = id and S.spells[id]
      if sp then return sp.name, sp.rank, 1, 0, 0, 0, id end
    end
    env.IsSpellKnown = function(id, pet)
      if pet then for _, p in ipairs(S.pet) do if p.id == id then return true end end return false end
      return S.known[id] == true
    end
    env.GetNumSpellTabs = function() return 1 end
    env.GetSpellTabInfo = function() return "General", 1, 0, #S.book end
    env.GetSpellBookItemInfo = function(i, book) local e = S.book[i]; if e then return S.known[e.id] and "SPELL" or "FUTURESPELL", e.id end end
    env.GetSpellBookItemName = function(i, book)
      if book == "pet" then local p = S.pet[i]; return p and p.name end
      local e = S.book[i]; return e and e.name, e and e.rank
    end
    env.HasPetSpells = function() if #S.pet > 0 then return #S.pet, "PET" end end
    env.PickupSpellBookItem = function(i, book) if book == "pet" and S.pet[i] then S.cursor = { type = "spell", id = S.pet[i].id } end end
    env.GetItemInfo = function(id) return S.items[id] end
    env.PickupItem = function(id) for b, t in pairs(S.bags) do for _, iid in pairs(t) do if iid == id then S.cursor = { type = "item", id = id }; return end end end end
    local c = containerAPI()
    env.GetContainerNumSlots, env.GetContainerItemID, env.PickupContainerItem = c.GetContainerNumSlots, c.GetContainerItemID, c.PickupContainerItem
  end
  return env
end

local function loadAddon(env)
  local ns = {}
  for i, src in ipairs(SOURCES) do
    local chunk = assert(load(src, "=" .. SOURCE_NAMES[i], "t", env))
    chunk("BarClone", ns)
  end
  for _, h in ipairs(env.HANDLERS) do h(nil, "ADDON_LOADED", "BarClone") end
  for _, h in ipairs(env.HANDLERS) do h(nil, "PLAYER_LOGIN") end
  return ns
end

local function lastPrinted(pattern)
  for i = #printed, 1, -1 do if printed[i]:find(pattern) then return printed[i] end end
end

local function populate(S)
  S.spells = {
    [101] = { name = "Fireball", rank = "Rank 1" },
    [200] = { name = "Frostbolt", rank = "Rank 1" }, [201] = { name = "Frostbolt", rank = "Rank 2" }, [202] = { name = "Frostbolt", rank = "Rank 3" },
    [300] = { name = "Charge", rank = "" },
    [2649] = { name = "Growl", rank = "Rank 1" },
  }
  S.book = { { id = 101, name = "Fireball", rank = "Rank 1" }, { id = 200, name = "Frostbolt", rank = "Rank 1" },
    { id = 201, name = "Frostbolt", rank = "Rank 2" }, { id = 202, name = "Frostbolt", rank = "Rank 3" }, { id = 300, name = "Charge", rank = "" } }
  S.known = { [101] = true, [200] = true, [201] = true, [202] = true, [300] = true }
  S.pet = { { id = 2649, name = "Growl" } }
  S.items = { [5001] = "Healing Potion", [6001] = "Arcanite Reaper" }
  S.bags[0][3] = 5001
  S.inv[16] = 6001
  S.macros = { [1] = { name = "Pull", icon = 134400, body = "/cast Charge" }, [121] = { name = "Mine", icon = 134400, body = "/say hi", perChar = true } }
end

print("==== MODE: " .. MODE)
local env = makeEnv()
env.BarCloneDB = nil
local ns = loadAddon(env)
local S = env.STATE
populate(S)
assert(ns.FlavorName == (MODE == "modern" and "WoW Forever" or "TBC Anniversary"), "flavor: " .. tostring(ns.FlavorName))
assert(ns.MAX_SLOTS == (MODE == "modern" and 180 or 120), "max slots")
assert(ns.IsModernAPI == (MODE == "modern"))

-- Original bars
S.bar[1] = { type = "spell", id = 101 }
S.bar[2] = { type = "spell", id = 202 }
S.bar[3] = { type = "macro", id = 1 }
S.bar[4] = { type = "item", id = 5001 }
S.bar[5] = { type = "item", id = 6001 }
S.bar[7] = { type = "spell", id = 2649, sub = MODE == "modern" and "pet" or nil }
S.bar[8] = { type = "macro", id = 121 }
S.bar[24] = { type = "spell", id = 300 }
if MODE == "modern" then S.bar[150] = { type = "spell", id = 300 } end
local expectedTotal = MODE == "modern" and 9 or 8

assert(ns.SaveProfile("Main"))
local p = ns.GetProfile("Main")
assert(p.counts.total == expectedTotal, "saved " .. p.counts.total)
assert(p.slots[2].name == "Frostbolt" and p.slots[2].rank == "Rank 3", "rank captured: " .. tostring(p.slots[2].rank))
assert(p.slots[4].name == "Healing Potion")
assert(p.slots[3].body == "/cast Charge" and p.slots[8].perChar == true)
assert(p.flavor == ns.FlavorName)
print("save: OK (" .. p.counts.total .. " slots)")

-- Wipe bars, reload, compare
local original = {}
for k, v in pairs(S.bar) do original[k] = { type = v.type, id = v.id } end
S.bar = {}
local report = ns.LoadProfile("Main")
if not report or #report.skipped > 0 then
  for _, sk in ipairs(report and report.skipped or {}) do print("  SKIP slot " .. sk.slot .. ": " .. tostring(sk.reason)) end
  error("round trip had skips / no report: " .. tostring(report))
end
for k, v in pairs(original) do
  assert(S.bar[k], "slot " .. k .. " empty after load")
  assert(S.bar[k].type == v.type, "slot " .. k .. " type")
  if v.type ~= "macro" then assert(S.bar[k].id == v.id, ("slot %d id %s vs %s"):format(k, tostring(v.id), tostring(S.bar[k].id))) end
end
assert(S.cursor == nil, "cursor left dirty")
print("round trip: OK")

-- Second "character": knows only Frostbolt R1/R2, has no Pull macro, no potion, nothing on slot 24
S.bar = {}
S.known = { [101] = true, [200] = true, [201] = true, [300] = true }
S.macros[1] = nil
S.bags[0][3] = nil
report = ns.LoadProfile("Main")
assert(S.bar[2] and S.bar[2].id == 201, "rank fallback picked " .. tostring(S.bar[2] and S.bar[2].id))
assert(report.rankFallback == 1, "rankFallback " .. report.rankFallback)
assert(report.macrosCreated == 1 and S.bar[3] and S.bar[3].type == "macro", "macro not recreated")
assert(env.GetMacroIndexByName("Pull") > 0)
assert(#report.skipped == 1 and report.skipped[1].slot == 4 and report.skipped[1].reason:find("item"), "potion should be the only skip")
assert(S.bar[7] and S.bar[7].id == 2649, "pet spell")
print("fallbacks: OK (rank, macro, item skip, pet)")

-- Combat queueing
S.combat = true
assert(ns.LoadProfile("Main") == false and ns.pendingLoad == "Main")
S.combat = false
for _, h in ipairs(env.HANDLERS) do h(nil, "PLAYER_REGEN_ENABLED") end
assert(ns.pendingLoad == nil)
print("combat queue: OK")

-- clearBeforeLoad clears stray slots; off leaves them
S.bar[60] = { type = "spell", id = 101 }
ns.LoadProfile("Main"); assert(S.bar[60] == nil, "stray slot not cleared")
ns.db.options.clearBeforeLoad = false
S.bar[60] = { type = "spell", id = 101 }
ns.LoadProfile("Main"); assert(S.bar[60] ~= nil, "stray slot cleared with option off")
ns.db.options.clearBeforeLoad = true
print("clear option: OK")

-- Slash commands don't error
env.SlashCmdList.BARCLONE("list"); env.SlashCmdList.BARCLONE("version"); env.SlashCmdList.BARCLONE("bogus")
assert(lastPrinted("Client: "), "version output")
print("slash: OK  ->  " .. lastPrinted("Client: "))

-- Export for the cross-client test
EXPORTS = EXPORTS or {}
EXPORTS[MODE] = assert(ns.ExportProfile("Main"))
NS = NS or {}
NS[MODE] = ns
ENVS = ENVS or {}
ENVS[MODE] = env
`;

const crossTest = `
-- Import the modern (180-slot) profile into the classic client and load it.
local ns, env = NS.classic, ENVS.classic
local S = env.STATE
local prof = assert(ns.DecodeProfile(EXPORTS.modern))
assert(prof.slots[150], "slot 150 should survive decode")
assert(ns.ImportProfile(prof, "FromForever"))
S.bar = {}
S.known = { [101] = true, [200] = true, [201] = true, [202] = true, [300] = true }
S.bags[0][3] = 5001 -- the earlier "second character" step took the potion away
local report = ns.LoadProfile("FromForever")
assert(report.placed == 8, "placed " .. report.placed)
assert(S.bar[150] == nil, "slot 150 must not be placed on a 120-slot client")
local found = false
for _, m in ipairs(printed) do if m:find("action bars this client does not have") then found = true end end
assert(found, "missing 'ignored' notice")
for _, m in ipairs(printed) do if m:find("saved on WoW Forever") then found = "flavor" end end
assert(found == "flavor", "missing flavor notice")

-- And the other direction: classic profile into the modern client.
local ns2, env2 = NS.modern, ENVS.modern
local prof2 = assert(ns2.DecodeProfile(EXPORTS.classic))
assert(ns2.ImportProfile(prof2, "FromTBC"))
env2.STATE.bar = {}
env2.STATE.known = { [101] = true, [200] = true, [201] = true, [202] = true, [300] = true }
env2.STATE.bags[0][3] = 5001
local r2 = ns2.LoadProfile("FromTBC")
assert(r2.placed == 8 and #r2.skipped == 0, "modern load of classic profile: placed " .. r2.placed .. " skipped " .. #r2.skipped)
print("cross-client: OK (Forever -> TBC ignores slot 150; TBC -> Forever loads fully)")
print("ALL CORE TESTS PASSED")
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
// Push sources
lua.lua_createtable(L, files.length, 0);
files.forEach((src, i) => { lua.lua_pushstring(L, to_luastring(src)); lua.lua_rawseti(L, -2, i + 1); });
lua.lua_setglobal(L, to_luastring("SOURCES"));
lua.lua_createtable(L, 3, 0);
["BarClone_Compat.lua", "BarClone.lua", "BarClone_Serialize.lua"].forEach((n, i) => { lua.lua_pushstring(L, to_luastring(n)); lua.lua_rawseti(L, -2, i + 1); });
lua.lua_setglobal(L, to_luastring("SOURCE_NAMES"));

function run(code, arg) {
  if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK) {
    console.error("LOAD ERROR:", to_jsstring(lua.lua_tostring(L, -1))); process.exit(1);
  }
  let nargs = 0;
  if (arg) { lua.lua_pushstring(L, to_luastring(arg)); nargs = 1; }
  if (lua.lua_pcall(L, nargs, 0, 0) !== lua.LUA_OK) {
    console.error("LUA ERROR:", to_jsstring(lua.lua_tostring(L, -1)));
    lauxlib.luaL_dostring(L, to_luastring("for i = math.max(1, #printed - 15), #printed do print(\"  chat> \" .. printed[i]) end"));
    process.exit(1);
  }
}
run(harness, "classic");
run(harness, "modern");
run(crossTest);
