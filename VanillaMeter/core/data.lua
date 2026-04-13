----------------------------------------------------------------------
-- VanillaMeter - Data
-- Actor storage, DPS/HPS calculation, segment management
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Data = {}
local Data = VM.Data

----------------------------------------------------------------------
-- Data tables
----------------------------------------------------------------------
-- Segment indices: [0] = overall, [1] = current fight
Data.damage = { [0] = {}, [1] = {} }
Data.heal   = { [0] = {}, [1] = {} }
Data.classes = {}

----------------------------------------------------------------------
-- Trim helper
----------------------------------------------------------------------
local function trim(str)
  return gsub(str, "^%s*(.-)%s*$", "%1")
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function Data:Init()
  -- nothing special for now, tables are ready
end

----------------------------------------------------------------------
-- Reset all data
----------------------------------------------------------------------
function Data:Reset()
  self.damage = { [0] = {}, [1] = {} }
  self.heal   = { [0] = {}, [1] = {} }
  self.classes = {}

  -- Trigger UI refresh
  if VM.Window and VM.Window.Refresh then
    VM.Window:Refresh()
  end
end

----------------------------------------------------------------------
-- Add a parsed combat entry
-- Called by the parser with: source, spell, target, value, school, datatype
----------------------------------------------------------------------
function Data:AddEntry(source, spell, target, value, school, datatype)
  -- Validate input
  if type(source) ~= "string" then return end
  if not tonumber(value) then return end

  source = trim(source)
  value = tonumber(value)

  -- Skip self-damage
  if datatype == "damage" and source == target then return end

  -- Check if we should start a new segment (only if autoReset is enabled)
  if VM.db and VM.db.tracking.autoReset and VM.Combat:ShouldStartNewSegment() then
    if self.classes[source] and self.classes[source] ~= "__other__" then
      self.damage[1] = {}
      self.heal[1]   = {}
    end
  elseif VM.Combat then
    -- Consume the flag even if we don't reset, so it doesn't pile up
    VM.Combat:ShouldStartNewSegment()
  end

  -- Calculate effective healing (how much actually landed vs. overhealing)
  local effective = 0
  if datatype == "heal" then
    local unitstr = VM.Combat:UnitByName(target)
    if unitstr then
      effective = math.min(UnitHealthMax(unitstr) - UnitHealth(unitstr), value)
    end
  end

  -- Write to both segments (overall + current)
  for segment = 0, 1 do
    local store = self[datatype]
    if not store then return end
    local entry = store[segment]

    -- First time seeing this source in this segment
    if not entry[source] then
      local unitType = VM.Combat:ScanName(source)

      if unitType == "PET" then
        -- Create owner entry if missing
        local owner = self.classes[source]
        if owner and not entry[owner] then
          if VM.Combat:ScanName(owner) then
            entry[owner] = { _sum = 0, _esum = 0, _ctime = 1, _tick = GetTime() }
          end
        end
      elseif not unitType then
        -- Not a tracked unit — skip this segment
        break
      end

      entry[source] = { _sum = 0, _esum = 0, _ctime = 1, _tick = GetTime() }
    end

    -- Merge pet data into owner if enabled
    local actualSource = source
    local actualSpell = spell

    if VM.db and VM.db.tracking.mergePets then
      local ownerClass = self.classes[source]
      if ownerClass and ownerClass ~= "__other__" and entry[ownerClass] then
        -- This is a pet — merge into owner
        entry[source] = nil
        actualSpell = "Pet: " .. source
        actualSource = ownerClass

        if not entry[actualSource] then
          entry[actualSource] = { _sum = 0, _esum = 0, _ctime = 1, _tick = GetTime() }
        end
      end
    end

    -- Write the data
    local actor = entry[actualSource]
    if actor then
      actor[actualSpell] = (actor[actualSpell] or 0) + value
      actor._sum  = (actor._sum  or 0) + value
      actor._esum = (actor._esum or 0) + effective

      -- Combat time tracking
      actor._ctime = actor._ctime or 1
      actor._tick  = actor._tick or GetTime()

      local now = GetTime()
      local elapsed = now - actor._tick
      -- Only add time if the gap is small (< 3.5s means continuous combat)
      if elapsed < 3.5 then
        actor._ctime = actor._ctime + elapsed
      end
      actor._tick = now
    end
  end

  -- Trigger UI refresh
  if VM.Window and VM.Window.needsRefresh ~= nil then
    VM.Window.needsRefresh = true
  end
end

----------------------------------------------------------------------
-- Get sorted data for display
-- segment: 0 = overall, 1 = current
-- datatype: "damage" or "heal"
-- Returns: sorted array of { name, total, esum, persec, rankValue, class }
--   damage: rankValue = total,  persec = DPS
--   heal:   rankValue = esum,   persec = effective HPS
----------------------------------------------------------------------
function Data:GetSorted(datatype, segment)
  segment = segment or 1

  local store = self[datatype]
  if not store or not store[segment] then return {} end

  local entry = store[segment]
  local result = {}
  local isHeal = (datatype == "heal")

  for name, actor in pairs(entry) do
    if type(actor) == "table" and actor._sum then
      local total     = actor._sum
      local esum      = actor._esum or 0
      local ctime     = math.max(actor._ctime or 1, 1)
      local rankValue = isHeal and esum or total
      local persec    = rankValue / ctime

      table.insert(result, {
        name      = name,
        total     = total,
        esum      = esum,
        persec    = persec,
        rankValue = rankValue,
        class     = self.classes[name],
      })
    end
  end

  -- Sort descending by rankValue (effective for heal, raw for damage)
  table.sort(result, function(a, b) return a.rankValue > b.rankValue end)

  return result
end
