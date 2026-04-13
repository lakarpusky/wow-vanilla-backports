----------------------------------------------------------------------
-- VanillaMeter - Combat
-- Combat state tracking and segment management
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Combat = {}
local Combat = VM.Combat

Combat.inCombat = false
Combat.startNextSegment = false

----------------------------------------------------------------------
-- Valid unit tables for scanning
----------------------------------------------------------------------
local validUnits = { ["player"] = true }
for i = 1, 4  do validUnits["party" .. i] = true end
for i = 1, 40 do validUnits["raid" .. i]  = true end

local validPets = { ["pet"] = true }
for i = 1, 4  do validPets["partypet" .. i] = true end
for i = 1, 40 do validPets["raidpet" .. i]  = true end

----------------------------------------------------------------------
-- Check if any group member is in combat
----------------------------------------------------------------------
local function IsGroupInCombat()
  if UnitAffectingCombat("player") or UnitAffectingCombat("pet") then
    return true
  end

  local raidSize  = GetNumRaidMembers()
  local partySize = GetNumPartyMembers()

  if raidSize >= 1 then
    for i = 1, raidSize do
      if UnitAffectingCombat("raid" .. i) or UnitAffectingCombat("raidpet" .. i) then
        return true
      end
    end
  else
    for i = 1, partySize do
      if UnitAffectingCombat("party" .. i) or UnitAffectingCombat("partypet" .. i) then
        return true
      end
    end
  end

  return false
end

----------------------------------------------------------------------
-- Resolve unit ID from name (with caching)
----------------------------------------------------------------------
local unitCache = {}

function Combat:UnitByName(name)
  -- Return cached result if still valid
  if unitCache[name] and UnitName(unitCache[name]) == name then
    return unitCache[name]
  end

  for unit in pairs(validUnits) do
    if UnitName(unit) == name then
      unitCache[name] = unit
      return unit
    end
  end

  for unit in pairs(validPets) do
    if UnitName(unit) == name then
      unitCache[name] = unit
      return unit
    end
  end

  return nil
end

----------------------------------------------------------------------
-- Scan a name to determine if it's a player, pet, or unknown
-- Returns: "PLAYER", "PET", or nil
-- Side effect: populates VM.data.classes
----------------------------------------------------------------------
function Combat:ScanName(name)
  if not name or not VM.Data then return nil end

  local data = VM.Data

  -- Check if it's a real player unit
  for unit in pairs(validUnits) do
    if UnitExists(unit) and UnitName(unit) == name then
      if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        data.classes[name] = class
        return "PLAYER"
      end
    end
  end

  -- Check if it's a pet
  for unit in pairs(validPets) do
    if UnitExists(unit) and UnitName(unit) == name then
      -- Determine owner
      if strsub(unit, 0, 3) == "pet" then
        data.classes[name] = UnitName("player")
      elseif strsub(unit, 0, 8) == "partypet" then
        data.classes[name] = UnitName("party" .. strsub(unit, 9))
      elseif strsub(unit, 0, 7) == "raidpet" then
        data.classes[name] = UnitName("raid" .. strsub(unit, 8))
      end
      return "PET"
    end
  end

  -- Track all units if config allows
  if VM.db and VM.db.tracking.trackAll then
    data.classes[name] = data.classes[name] or "__other__"
    return "OTHER"
  end

  return nil
end

----------------------------------------------------------------------
-- Update combat state
----------------------------------------------------------------------
function Combat:UpdateState()
  local nowInCombat = IsGroupInCombat()

  if nowInCombat and not self.inCombat then
    -- Entering combat
    self.inCombat = true

  elseif not nowInCombat and self.inCombat then
    -- Leaving combat
    self.inCombat = false
    self.startNextSegment = true
  end
end

----------------------------------------------------------------------
-- Should we start a new segment?
----------------------------------------------------------------------
function Combat:ShouldStartNewSegment()
  if self.startNextSegment then
    self.startNextSegment = false
    return true
  end
  return false
end

----------------------------------------------------------------------
-- Initialize combat state frame
----------------------------------------------------------------------
function Combat:Init()
  local frame = CreateFrame("Frame", "VanillaMeterCombatState", UIParent)

  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")

  frame:SetScript("OnEvent", function()
    Combat:UpdateState()
  end)

  -- Poll every second as fallback (party/raid member combat detection)
  frame:SetScript("OnUpdate", function()
    if (this.tick or 1) > GetTime() then return end
    this.tick = GetTime() + 1
    Combat:UpdateState()
  end)
end
