----------------------------------------------------------------------
-- VanillaMeter - Parser
-- Locale-independent combat log parsing for 1.12.1
-- Uses GlobalStrings.lua constants (COMBATHITSELFOTHER, etc.)
-- which are already localized by the WoW client.
--
-- Approach based on the proven ShaguDPS pattern-sanitize method.
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Parser = {}
local Parser = VM.Parser

----------------------------------------------------------------------
-- Pattern sanitization (converts GlobalStrings format to gfind-compatible)
----------------------------------------------------------------------
local sanitize_cache = {}

local function sanitize(pattern)
  if not sanitize_cache[pattern] then
    local ret = pattern
    -- escape magic characters
    ret = gsub(ret, "([%+%-%*%(%)%?%[%]%^])", "%%%1")
    -- remove capture indexes (e.g., %1$s -> %s)
    ret = gsub(ret, "%d%$", "")
    -- wrap each format specifier in a capture group
    ret = gsub(ret, "(%%%a)", "(%1+)")
    -- convert %s captures to NON-GREEDY (.-) to prevent catastrophic backtracking
    ret = gsub(ret, "%%s%+", ".-")
    -- prioritize numbers over strings: (.-)(%d+) stays as-is (already non-greedy)
    ret = gsub(ret, "%(%.%-%)(%%d%+)", "(.-)(%%d+)")
    -- cache it
    sanitize_cache[pattern] = ret
  end
  return sanitize_cache[pattern]
end

----------------------------------------------------------------------
-- Capture index extraction (handles localized argument reordering)
----------------------------------------------------------------------
local capture_cache = {}

local function captures(pat)
  local r = capture_cache
  if not r[pat] then
    r[pat] = { nil, nil, nil, nil, nil }
    for a, b, c, d, e in string.gfind(
      gsub(pat, "%((.+)%)", "%1"),
      gsub(pat, "%d%$", "%%(.-)$")
    ) do
      r[pat][1] = tonumber(a)
      r[pat][2] = tonumber(b)
      r[pat][3] = tonumber(c)
      r[pat][4] = tonumber(d)
      r[pat][5] = tonumber(e)
    end
  end
  return r[pat][1], r[pat][2], r[pat][3], r[pat][4], r[pat][5]
end

----------------------------------------------------------------------
-- Capture-index-aware string.find
----------------------------------------------------------------------
local ra, rb, rc, rd, re, a, b, c, d, e, match, num, va, vb, vc, vd, ve

local function cfind(str, pat)
  a, b, c, d, e = captures(pat)
  match, num, va, vb, vc, vd, ve = string.find(str, sanitize(pat))

  ra = e == 1 and ve or d == 1 and vd or c == 1 and vc or b == 1 and vb or va
  rb = e == 2 and ve or d == 2 and vd or c == 2 and vc or a == 2 and va or vb
  rc = e == 3 and ve or d == 3 and vd or a == 3 and va or b == 3 and vb or vc
  rd = e == 4 and ve or a == 4 and va or c == 4 and vc or b == 4 and vb or vd
  re = a == 5 and va or d == 5 and vd or c == 5 and vc or b == 5 and vb or ve

  return match, num, ra, rb, rc, rd, re
end

----------------------------------------------------------------------
-- Combat log pattern groups
-- These use GlobalStrings.lua constants which are set by the client
-- and are already locale-correct.
----------------------------------------------------------------------
local combatlog_strings = {
  -- Melee / Auto damage
  ["hit_self_other"] = {
    COMBATHITSELFOTHER, COMBATHITSCHOOLSELFOTHER,
    COMBATHITCRITSELFOTHER, COMBATHITCRITSCHOOLSELFOTHER
  },
  ["hit_other_self"] = {
    COMBATHITOTHERSELF, COMBATHITCRITOTHERSELF,
    COMBATHITSCHOOLOTHERSELF, COMBATHITCRITSCHOOLOTHERSELF
  },
  ["hit_other_other"] = {
    COMBATHITOTHEROTHER, COMBATHITCRITOTHEROTHER,
    COMBATHITSCHOOLOTHEROTHER, COMBATHITCRITSCHOOLOTHEROTHER
  },

  -- Spell damage
  ["spell_self"] = {
    SPELLLOGSCHOOLSELFSELF, SPELLLOGCRITSCHOOLSELFSELF,
    SPELLLOGSELFSELF, SPELLLOGCRITSELFSELF,
    SPELLLOGSCHOOLSELFOTHER, SPELLLOGCRITSCHOOLSELFOTHER,
    SPELLLOGSELFOTHER, SPELLLOGCRITSELFOTHER
  },
  ["spell_other_self"] = {
    SPELLLOGSCHOOLOTHERSELF, SPELLLOGCRITSCHOOLOTHERSELF,
    SPELLLOGOTHERSELF, SPELLLOGCRITOTHERSELF
  },
  ["spell_other_other"] = {
    SPELLLOGSCHOOLOTHEROTHER, SPELLLOGCRITSCHOOLOTHEROTHER,
    SPELLLOGOTHEROTHER, SPELLLOGCRITOTHEROTHER
  },

  -- Damage shields
  ["shield_self"] = { DAMAGESHIELDSELFOTHER },
  ["shield_other"] = { DAMAGESHIELDOTHERSELF, DAMAGESHIELDOTHEROTHER },

  -- Periodic damage (DoTs)
  ["dot_other"] = { PERIODICAURADAMAGESELFOTHER, PERIODICAURADAMAGEOTHEROTHER },
  ["dot_self"]  = { PERIODICAURADAMAGESELFSELF, PERIODICAURADAMAGEOTHERSELF },

  -- Direct heals
  ["heal_self"] = {
    HEALEDCRITSELFSELF, HEALEDSELFSELF,
    HEALEDCRITSELFOTHER, HEALEDSELFOTHER
  },
  ["heal_other"] = {
    HEALEDCRITOTHERSELF, HEALEDOTHERSELF,
    HEALEDCRITOTHEROTHER, HEALEDOTHEROTHER
  },

  -- Periodic heals (HoTs)
  ["hot_other"]  = { PERIODICAURAHEALSELFOTHER, PERIODICAURAHEALOTHEROTHER },
  ["hot_self"]   = { PERIODICAURAHEALSELFSELF, PERIODICAURAHEALOTHERSELF },
}

----------------------------------------------------------------------
-- Event → pattern group mapping
----------------------------------------------------------------------
local combatlog_events = {
  -- Melee hits
  ["CHAT_MSG_COMBAT_SELF_HITS"]                     = combatlog_strings["hit_self_other"],
  ["CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"]         = combatlog_strings["hit_other_self"],
  ["CHAT_MSG_COMBAT_PARTY_HITS"]                    = combatlog_strings["hit_other_other"],
  ["CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS"]           = combatlog_strings["hit_other_other"],
  ["CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"]            = combatlog_strings["hit_other_other"],
  ["CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS"]     = combatlog_strings["hit_other_other"],
  ["CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS"]        = combatlog_strings["hit_other_other"],
  ["CHAT_MSG_COMBAT_PET_HITS"]                      = combatlog_strings["hit_other_other"],

  -- Spell damage
  ["CHAT_MSG_SPELL_SELF_DAMAGE"]                    = combatlog_strings["spell_self"],
  ["CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"]        = combatlog_strings["spell_other_self"],
  ["CHAT_MSG_SPELL_PARTY_DAMAGE"]                   = combatlog_strings["spell_other_other"],
  ["CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE"]          = combatlog_strings["spell_other_other"],
  ["CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"]           = combatlog_strings["spell_other_other"],
  ["CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE"]    = combatlog_strings["spell_other_other"],
  ["CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE"]       = combatlog_strings["spell_other_other"],
  ["CHAT_MSG_SPELL_PET_DAMAGE"]                     = combatlog_strings["spell_other_other"],

  -- Damage shields
  ["CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF"]          = combatlog_strings["shield_self"],
  ["CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS"]        = combatlog_strings["shield_other"],

  -- Periodic damage
  ["CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE"]          = combatlog_strings["dot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"]  = combatlog_strings["dot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE"] = combatlog_strings["dot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"]       = combatlog_strings["dot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE"]           = combatlog_strings["dot_self"],

  -- Direct heals
  ["CHAT_MSG_SPELL_SELF_BUFF"]                      = combatlog_strings["heal_self"],
  ["CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF"]            = combatlog_strings["heal_other"],
  ["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]             = combatlog_strings["heal_other"],
  ["CHAT_MSG_SPELL_PARTY_BUFF"]                     = combatlog_strings["heal_other"],

  -- Periodic heals
  ["CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS"]           = combatlog_strings["hot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"]  = combatlog_strings["hot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS"]   = combatlog_strings["hot_other"],
  ["CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"]            = combatlog_strings["hot_self"],
}

----------------------------------------------------------------------
-- Pattern → extraction logic
-- Each function returns: source, spell, target, value, school, type
----------------------------------------------------------------------
local combatlog_parser = {
  -- Spell damage (self → self/other)
  [SPELLLOGSCHOOLSELFSELF]      = function(d, attack, value, school) return d.source, attack, d.target, value, school, "damage" end,
  [SPELLLOGCRITSCHOOLSELFSELF]  = function(d, attack, value, school) return d.source, attack, d.target, value, school, "damage" end,
  [SPELLLOGSELFSELF]            = function(d, attack, value)         return d.source, attack, d.target, value, d.school, "damage" end,
  [SPELLLOGCRITSELFSELF]        = function(d, attack, value)         return d.source, attack, d.target, value, d.school, "damage" end,
  [SPELLLOGSCHOOLSELFOTHER]     = function(d, attack, target, value, school) return d.source, attack, target, value, school, "damage" end,
  [SPELLLOGCRITSCHOOLSELFOTHER] = function(d, attack, target, value, school) return d.source, attack, target, value, school, "damage" end,
  [SPELLLOGSELFOTHER]           = function(d, attack, target, value) return d.source, attack, target, value, d.school, "damage" end,
  [SPELLLOGCRITSELFOTHER]       = function(d, attack, target, value) return d.source, attack, target, value, d.school, "damage" end,

  -- Spell damage (other → self)
  [SPELLLOGSCHOOLOTHERSELF]     = function(d, source, attack, value, school) return source, attack, d.target, value, school, "damage" end,
  [SPELLLOGCRITSCHOOLOTHERSELF] = function(d, source, attack, value, school) return source, attack, d.target, value, school, "damage" end,
  [SPELLLOGOTHERSELF]           = function(d, source, attack, value) return source, attack, d.target, value, d.school, "damage" end,
  [SPELLLOGCRITOTHERSELF]       = function(d, source, attack, value) return source, attack, d.target, value, d.school, "damage" end,

  -- Spell damage (other → other)
  [SPELLLOGSCHOOLOTHEROTHER]     = function(d, source, attack, target, value, school) return source, attack, target, value, school, "damage" end,
  [SPELLLOGCRITSCHOOLOTHEROTHER] = function(d, source, attack, target, value, school) return source, attack, target, value, school, "damage" end,
  [SPELLLOGOTHEROTHER]           = function(d, source, attack, target, value) return source, attack, target, value, d.school, "damage" end,
  [SPELLLOGCRITOTHEROTHER]       = function(d, source, attack, target, value) return source, attack, target, value, d.school, "damage" end,

  -- Melee hits (self → other)
  [COMBATHITSELFOTHER]           = function(d, target, value) return d.source, d.attack, target, value, d.school, "damage" end,
  [COMBATHITCRITSELFOTHER]       = function(d, target, value) return d.source, d.attack, target, value, d.school, "damage" end,
  [COMBATHITSCHOOLSELFOTHER]     = function(d, target, value, school) return d.source, d.attack, target, value, school, "damage" end,
  [COMBATHITCRITSCHOOLSELFOTHER] = function(d, target, value, school) return d.source, d.attack, target, value, school, "damage" end,

  -- Melee hits (other → self)
  [COMBATHITOTHERSELF]           = function(d, source, value) return source, d.attack, d.target, value, d.school, "damage" end,
  [COMBATHITCRITOTHERSELF]       = function(d, source, value) return source, d.attack, d.target, value, d.school, "damage" end,
  [COMBATHITSCHOOLOTHERSELF]     = function(d, source, value, school) return source, d.attack, d.target, value, school, "damage" end,
  [COMBATHITCRITSCHOOLOTHERSELF] = function(d, source, value, school) return source, d.attack, d.target, value, school, "damage" end,

  -- Melee hits (other → other)
  [COMBATHITOTHEROTHER]           = function(d, source, target, value) return source, d.attack, target, value, d.school, "damage" end,
  [COMBATHITCRITOTHEROTHER]       = function(d, source, target, value) return source, d.attack, target, value, d.school, "damage" end,
  [COMBATHITSCHOOLOTHEROTHER]     = function(d, source, target, value, school) return source, d.attack, target, value, school, "damage" end,
  [COMBATHITCRITSCHOOLOTHEROTHER] = function(d, source, target, value, school) return source, d.attack, target, value, school, "damage" end,

  -- Damage shields
  [DAMAGESHIELDSELFOTHER]  = function(d, value, school, target) return d.source, "Reflect (" .. school .. ")", target, value, school, "damage" end,
  [DAMAGESHIELDOTHERSELF]  = function(d, source, value, school) return source, "Reflect (" .. school .. ")", d.target, value, school, "damage" end,
  [DAMAGESHIELDOTHEROTHER] = function(d, source, value, school, target) return source, "Reflect (" .. school .. ")", target, value, school, "damage" end,

  -- Periodic damage (DoTs)
  [PERIODICAURADAMAGESELFSELF]   = function(d, value, school, attack)         return d.source, attack, d.target, value, school, "damage" end,
  [PERIODICAURADAMAGESELFOTHER]  = function(d, target, value, school, attack) return d.source, attack, target, value, school, "damage" end,
  [PERIODICAURADAMAGEOTHERSELF]  = function(d, value, school, source, attack) return source, attack, d.target, value, school, "damage" end,
  [PERIODICAURADAMAGEOTHEROTHER] = function(d, target, value, school, source, attack) return source, attack, target, value, school, "damage" end,

  -- Direct heals (self → self/other)
  [HEALEDCRITSELFSELF]   = function(d, spell, value)         return d.source, spell, d.target, value, d.school, "heal" end,
  [HEALEDSELFSELF]       = function(d, spell, value)         return d.source, spell, d.target, value, d.school, "heal" end,
  [HEALEDCRITSELFOTHER]  = function(d, spell, target, value) return d.source, spell, target, value, d.school, "heal" end,
  [HEALEDSELFOTHER]      = function(d, spell, target, value) return d.source, spell, target, value, d.school, "heal" end,

  -- Direct heals (other → self/other)
  [HEALEDCRITOTHERSELF]  = function(d, source, spell, value)         return source, spell, d.target, value, d.school, "heal" end,
  [HEALEDOTHERSELF]      = function(d, source, spell, value)         return source, spell, d.target, value, d.school, "heal" end,
  [HEALEDCRITOTHEROTHER] = function(d, source, spell, target, value) return source, spell, target, value, d.school, "heal" end,
  [HEALEDOTHEROTHER]     = function(d, source, spell, target, value) return source, spell, target, value, d.school, "heal" end,

  -- Periodic heals (HoTs)
  [PERIODICAURAHEALSELFSELF]   = function(d, value, spell)                 return d.source, spell, d.target, value, d.school, "heal" end,
  [PERIODICAURAHEALSELFOTHER]  = function(d, target, value, spell)         return d.source, spell, target, value, d.school, "heal" end,
  [PERIODICAURAHEALOTHERSELF]  = function(d, value, source, spell)         return source, spell, d.target, value, d.school, "heal" end,
  [PERIODICAURAHEALOTHEROTHER] = function(d, target, value, source, spell) return source, spell, target, value, d.school, "heal" end,
}

----------------------------------------------------------------------
-- Initialize parser frame and register events
----------------------------------------------------------------------
local parserFrame = CreateFrame("Frame")

-- Register all combat log events
for evt in pairs(combatlog_events) do
  parserFrame:RegisterEvent(evt)
end

-- Preload all pattern sanitizations (skip nil patterns)
for pattern in pairs(combatlog_parser) do
  if pattern then
    sanitize(pattern)
  end
end

-- Initialize absorb/resist suffix patterns for stripping
-- These may be nil on some servers, so guard them
local absorb_pattern = ABSORB_TRAILER and sanitize(ABSORB_TRAILER) or nil
local resist_pattern = RESIST_TRAILER and sanitize(RESIST_TRAILER) or nil

-- Reusable defaults table (avoids garbage per event)
local defaults = {}
local empty = ""
local physical = "physical"
local autohit = "Auto Hit"

-- Scope variables outside the hot path
local _, result, a1, a2, a3, a4, a5

----------------------------------------------------------------------
-- Main event handler — fires on every combat log message
----------------------------------------------------------------------
parserFrame:SetScript("OnEvent", function()
  if not arg1 then return end
  if not VM.Data then return end

  -- Don't track if no tabs are open
  if not VM.db or not VM.db.activeTab then return end
  if VM.Tabs and VM.Tabs.openTabs and table.getn(VM.Tabs.openTabs) == 0 then return end

  -- Strip absorb/resist suffixes from the message
  local msg = arg1
  if absorb_pattern then
    local ok, cleaned = pcall(string.gsub, msg, absorb_pattern, empty)
    if ok then msg = cleaned end
  end
  if resist_pattern then
    local ok, cleaned = pcall(string.gsub, msg, resist_pattern, empty)
    if ok then msg = cleaned end
  end

  -- Set defaults for self-referencing patterns
  defaults.source = VM.playerName or UnitName("player")
  defaults.target = VM.playerName or UnitName("player")
  defaults.school = physical
  defaults.attack = autohit
  defaults.spell  = UNKNOWN
  defaults.value  = 0

  -- Get the pattern list for this event
  local patterns = combatlog_events[event]
  if not patterns then return end

  -- Try each pattern until one matches
  for _, pattern in pairs(patterns) do
    if pattern and combatlog_parser[pattern] then
      local ok, r, n, p1, p2, p3, p4, p5 = pcall(cfind, msg, pattern)
      if ok and r then
        VM.Data:AddEntry(combatlog_parser[pattern](defaults, p1, p2, p3, p4, p5))
        return
      end
    end
  end
end)
