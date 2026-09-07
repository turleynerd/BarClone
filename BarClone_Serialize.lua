-------------------------------------------------------------------------------
-- BarClone - export / import codes
--
-- A profile is serialized into a compact tagged format, wrapped in base64 so
-- it survives chat boxes and clipboards, and protected with a checksum:
--
--     BC1:<base64 payload>:<checksum>
--
-- No external libraries are used so the addon stays dependency free.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FORMAT_VERSION = 1
local PREFIX = "BC" .. FORMAT_VERSION
local NUM_SLOTS = 120

local floor = math.floor
local strbyte, strchar, strsub, strfind = string.byte, string.char, string.sub, string.find
local tconcat = table.concat

-------------------------------------------------------------------------------
-- Tagged serializer (strings are length-prefixed, so no escaping is needed)
--   s<len>:<bytes>   string
--   n<number>;       number
--   T / F            boolean
--   { k v k v ... }  table
-------------------------------------------------------------------------------
local function Serialize(value, out)
    local t = type(value)
    if t == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif t == "number" then
        if value == floor(value) and math.abs(value) < 2 ^ 52 then
            out[#out + 1] = ("n%d;"):format(value)
        else
            out[#out + 1] = ("n%.17g;"):format(value)
        end
    elseif t == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, v in pairs(value) do
            local kt, vt = type(k), type(v)
            if (kt == "string" or kt == "number")
                and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                Serialize(k, out)
                Serialize(v, out)
            end
        end
        out[#out + 1] = "}"
    end
    return out
end

local function Deserialize(str)
    local pos = 1
    local len = #str

    local readValue -- forward declaration

    local function fail(msg)
        error(msg or "malformed data", 0)
    end

    readValue = function()
        if pos > len then fail("unexpected end of data") end
        local tag = strsub(str, pos, pos)
        pos = pos + 1

        if tag == "s" then
            local colon = strfind(str, ":", pos, true)
            if not colon then fail("bad string length") end
            local n = tonumber(strsub(str, pos, colon - 1))
            if not n then fail("bad string length") end
            local s = strsub(str, colon + 1, colon + n)
            if #s ~= n then fail("truncated string") end
            pos = colon + n + 1
            return s
        elseif tag == "n" then
            local semi = strfind(str, ";", pos, true)
            if not semi then fail("bad number") end
            local n = tonumber(strsub(str, pos, semi - 1))
            if not n then fail("bad number") end
            pos = semi + 1
            return n
        elseif tag == "T" then
            return true
        elseif tag == "F" then
            return false
        elseif tag == "{" then
            local tbl = {}
            while true do
                if pos > len then fail("unterminated table") end
                if strsub(str, pos, pos) == "}" then
                    pos = pos + 1
                    return tbl
                end
                local k = readValue()
                local v = readValue()
                tbl[k] = v
            end
        end
        fail("unknown tag '" .. tostring(tag) .. "'")
    end

    local ok, result = pcall(readValue)
    if not ok then
        return nil, result
    end
    if pos <= len then
        return nil, "trailing data"
    end
    return result
end

-------------------------------------------------------------------------------
-- Base64
-------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, 64 do
    B64_DECODE[strbyte(B64, i)] = i - 1
end

local function Base64Encode(data)
    local out = {}
    local n = #data
    for i = 1, n, 3 do
        local a, b, c = strbyte(data, i, i + 2)
        local num = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(num / 262144) % 64
        local c2 = floor(num / 4096) % 64
        local c3 = floor(num / 64) % 64
        local c4 = num % 64
        out[#out + 1] = strsub(B64, c1 + 1, c1 + 1)
            .. strsub(B64, c2 + 1, c2 + 1)
            .. (b and strsub(B64, c3 + 1, c3 + 1) or "=")
            .. (c and strsub(B64, c4 + 1, c4 + 1) or "=")
    end
    return tconcat(out)
end

local function Base64Decode(data)
    -- Drop anything that is not part of the alphabet (whitespace, line breaks).
    data = data:gsub("[^%w%+/=]", "")
    local out = {}
    local n = #data
    local i = 1
    while i <= n do
        local c1, c2, c3, c4 = strbyte(data, i, i + 3)
        local v1, v2 = B64_DECODE[c1], B64_DECODE[c2]
        if not v1 or not v2 then return nil end
        local v3 = (c3 and c3 ~= 61) and B64_DECODE[c3] or nil -- 61 is '='
        local v4 = (c4 and c4 ~= 61) and B64_DECODE[c4] or nil
        local num = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        local b1 = floor(num / 65536) % 256
        local b2 = floor(num / 256) % 256
        local b3 = num % 256
        if v3 and v4 then
            out[#out + 1] = strchar(b1, b2, b3)
        elseif v3 then
            out[#out + 1] = strchar(b1, b2)
        else
            out[#out + 1] = strchar(b1)
        end
        i = i + 4
    end
    return tconcat(out)
end

-------------------------------------------------------------------------------
-- Checksum (djb2 kept inside 2^31 so string.format stays safe everywhere)
-------------------------------------------------------------------------------
local function Checksum(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + strbyte(s, i)) % 2147483648
    end
    return ("%08x"):format(h)
end

-------------------------------------------------------------------------------
-- Profile <-> code
-------------------------------------------------------------------------------
local SLOT_FIELDS = {
    spell = { id = "number", name = "string", rank = "string", sub = "string" },
    item = { id = "number", name = "string" },
    macro = { name = "string", icon = "number", body = "string", perChar = "boolean" },
}

-- Returns a clean copy of a slot entry, or nil if it is not usable.
local function SanitizeSlot(raw)
    if type(raw) ~= "table" or type(raw.type) ~= "string" then return nil end
    local fields = SLOT_FIELDS[raw.type]
    local clean = { type = raw.type }
    if fields then
        for field, expected in pairs(fields) do
            if type(raw[field]) == expected then
                clean[field] = raw[field]
            end
        end
        if raw.type == "spell" and not (clean.id or clean.name) then return nil end
        if raw.type == "item" and not clean.id then return nil end
        if raw.type == "macro" and not clean.name then return nil end
    else
        -- Unknown action type: keep only what is needed to describe it.
        if type(raw.id) == "number" then clean.id = raw.id end
    end
    return clean
end

function ns.ExportProfile(name)
    local p = ns.GetProfile(name)
    if not p then
        return nil, ("No profile named '%s'."):format(tostring(name))
    end
    local payload = {
        v = FORMAT_VERSION,
        name = p.name,
        class = p.class,
        classLocalized = p.classLocalized,
        level = p.level,
        character = p.character,
        created = p.created,
        updated = p.updated,
        slots = p.slots,
    }
    local data = tconcat(Serialize(payload, {}))
    return PREFIX .. ":" .. Base64Encode(data) .. ":" .. Checksum(data)
end

-- Parses a code. Returns a sanitized profile table (not yet saved) or nil, error.
function ns.DecodeProfile(code)
    if type(code) ~= "string" then return nil, "No code given." end
    code = code:gsub("%s+", "")
    if code == "" then return nil, "No code given." end

    local prefix, body, sum = code:match("^(%w+):([%w%+/=]+):(%x+)$")
    if not prefix then
        return nil, "This does not look like a BarClone export code."
    end
    if prefix ~= PREFIX then
        return nil, ("Unsupported code version '%s'."):format(prefix)
    end

    local data = Base64Decode(body)
    if not data then
        return nil, "The code is corrupted (bad encoding)."
    end
    if Checksum(data) ~= sum:lower() then
        return nil, "The code is corrupted (checksum mismatch). Make sure you copied all of it."
    end

    local payload, err = Deserialize(data)
    if not payload then
        return nil, "The code is corrupted (" .. tostring(err) .. ")."
    end
    if type(payload) ~= "table" or payload.v ~= FORMAT_VERSION or type(payload.slots) ~= "table" then
        return nil, "The code does not contain a profile."
    end

    local slots, counts = {}, { spell = 0, item = 0, macro = 0, other = 0, total = 0 }
    for k, raw in pairs(payload.slots) do
        local slot = tonumber(k)
        if slot and slot >= 1 and slot <= NUM_SLOTS and slot == floor(slot) then
            local clean = SanitizeSlot(raw)
            if clean then
                slots[slot] = clean
                counts.total = counts.total + 1
                local key = counts[clean.type] and clean.type or "other"
                counts[key] = counts[key] + 1
            end
        end
    end
    if counts.total == 0 then
        return nil, "The code contains an empty profile."
    end

    local profile = {
        name = type(payload.name) == "string" and payload.name or "Imported",
        class = type(payload.class) == "string" and payload.class or nil,
        classLocalized = type(payload.classLocalized) == "string" and payload.classLocalized or nil,
        level = type(payload.level) == "number" and payload.level or nil,
        character = type(payload.character) == "string" and payload.character or nil,
        created = type(payload.created) == "number" and payload.created or nil,
        updated = type(payload.updated) == "number" and payload.updated or nil,
        slots = slots,
        counts = counts,
    }
    return profile
end

-- Saves a decoded profile under the given name (overwrites silently; callers confirm).
function ns.ImportProfile(profile, rawName)
    local name, err = ns.ValidateName(rawName or profile.name)
    if not name then
        ns.Print(err)
        return false
    end
    local existing = ns.db.profiles[name]
    profile.name = name
    profile.created = (existing and existing.created) or profile.created or time()
    profile.updated = profile.updated or time()
    profile.imported = time()
    ns.db.profiles[name] = profile
    ns.Print("%s profile |cffffff00%s|r from code (%d slots: %d spells, %d items, %d macros).",
        existing and "Replaced" or "Imported", name, profile.counts.total, profile.counts.spell,
        profile.counts.item, profile.counts.macro)
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- Exposed for testing.
ns.Serialize = function(v) return tconcat(Serialize(v, {})) end
ns.Deserialize = Deserialize
ns.Base64Encode = Base64Encode
ns.Base64Decode = Base64Decode
ns.Checksum = Checksum
