----------------------------------------------------------------------
-- VanillaMeter - Core
-- Addon namespace, saved variables, defaults, initialization
----------------------------------------------------------------------

-- Global namespace
VanillaMeter = {}
local VM = VanillaMeter

-- Version
VM.version = "0.2.0"

-- Shared UI constants (used across window, tabs, detach)
VM.TAB_HEIGHT = 30

-- Player info (populated on PLAYER_LOGIN)
VM.playerName = nil

----------------------------------------------------------------------
-- Default saved variables
----------------------------------------------------------------------
VM.defaults = {
  -- Window layout
  window = {
    width = 350,
    height = 170,
    maxWidth = 500,
    point = "CENTER",
    x = 0,
    y = 0,
    locked = false,
    tabPosition = "top",    -- "top" or "bottom"
  },

  -- Visual settings
  appearance = {
    bgAlpha = 0.5,
    bgColor = { r = 0.05, g = 0.05, b = 0.05 },
    barHeight = 25,
    barSpacing = 3,
    classColors = true,
    showRank = true,
    transparent = false,
    font = "Fonts\\FRIZQT__.TTF",
    fontSize = 13,
  },

  -- Tracking
  tracking = {
    trackAll = false,       -- track all nearby units or group only
    mergePets = true,
    autoReset = false,      -- auto-reset current segment on new combat (false = accumulate)
  },

  -- Active tab per window
  activeTab = "damage",
}

----------------------------------------------------------------------
-- Deep copy utility
----------------------------------------------------------------------
function VM:DeepCopy(src)
  if type(src) ~= "table" then return src end
  local copy = {}
  for k, v in pairs(src) do
    copy[k] = self:DeepCopy(v)
  end
  return copy
end

----------------------------------------------------------------------
-- Merge defaults into saved vars (fill missing keys only)
----------------------------------------------------------------------
function VM:MergeDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then
        target[k] = {}
      end
      self:MergeDefaults(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

----------------------------------------------------------------------
-- Number formatting helpers
----------------------------------------------------------------------
function VM:FormatNumber(value)
  if value >= 1000000 then
    return string.format("%.1fM", value / 1000000)
  elseif value >= 1000 then
    return string.format("%.1fK", value / 1000)
  end
  return string.format("%d", value)
end

function VM:FormatDPS(value)
  if value >= 1000 then
    return string.format("%.1fK", value / 1000)
  end
  return string.format("%.1f", value)
end

----------------------------------------------------------------------
-- Get class color for a unit name
----------------------------------------------------------------------
function VM:GetClassColor(name)
  local class = VM.Data and VM.Data.classes[name]

  -- If class is a player name (pet owner), use PET color
  if class and not RAID_CLASS_COLORS[class] then
    return 0.30, 0.40, 0.50
  end

  -- Use Blizzard's RAID_CLASS_COLORS global
  if class and RAID_CLASS_COLORS[class] then
    local c = RAID_CLASS_COLORS[class]
    return c.r, c.g, c.b
  end

  return 0.50, 0.50, 0.50
end

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "VanillaMeter" then
    -- Initialize saved variables
    if not VanillaMeterDB then
      VanillaMeterDB = VM:DeepCopy(VM.defaults)
    else
      VM:MergeDefaults(VanillaMeterDB, VM.defaults)
    end
    VM.db = VanillaMeterDB

  elseif event == "PLAYER_LOGIN" then
    VM.playerName = UnitName("player")

    -- Initialize subsystems (they register themselves during load)
    if VM.Combat then VM.Combat:Init() end
    if VM.Data then VM.Data:Init() end
    if VM.Window then VM.Window:Init() end

    DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r v" .. VM.version .. " loaded. Type |cff80ff80/vm|r for options.")
  end
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_VANILLAMETER1 = "/vm"
SLASH_VANILLAMETER2 = "/vanillameter"

SlashCmdList["VANILLAMETER"] = function(msg)
  local cmd = string.lower(msg or "")

  if cmd == "toggle" or cmd == "" then
    if VM.Window then VM.Window:Toggle() end

  elseif cmd == "reset" then
    if VM.Data then VM.Data:Reset() end
    DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: Data reset.")

  elseif cmd == "lock" then
    if VM.db then
      VM.db.window.locked = not VM.db.window.locked
      local state = VM.db.window.locked and "locked" or "unlocked"
      DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: Window " .. state .. ".")
    end

  elseif cmd == "config" then
    if VM.Config then VM.Config:Toggle() end

  elseif cmd == "autoreset" then
    if VM.db then
      VM.db.tracking.autoReset = not VM.db.tracking.autoReset
      local state = VM.db.tracking.autoReset and "ON (resets each fight)" or "OFF (accumulates)"
      DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: Auto-reset " .. state)
    end

  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r commands:")
    DEFAULT_CHAT_FRAME:AddMessage("  /vm - Toggle window")
    DEFAULT_CHAT_FRAME:AddMessage("  /vm reset - Reset data")
    DEFAULT_CHAT_FRAME:AddMessage("  /vm lock - Toggle lock")
    DEFAULT_CHAT_FRAME:AddMessage("  /vm autoreset - Toggle auto-reset per fight")
    DEFAULT_CHAT_FRAME:AddMessage("  /vm config - Show config")
  end
end
