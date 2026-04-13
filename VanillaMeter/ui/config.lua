----------------------------------------------------------------------
-- VanillaMeter - Config
-- Two-column panel: toggles (left) + reset buttons (right)
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Config = {}
local Config = VM.Config

Config.frame = nil

local SETTINGS = {
  { key = "tracking.autoReset",     label = "Auto-Reset" },
  { key = "tracking.trackAll",      label = "Track All" },
  { key = "tracking.mergePets",     label = "Merge Pets" },
  { key = "window.locked",          label = "Lock Window" },
  { key = "appearance.showRank",    label = "Show Rank" },
  { key = "appearance.transparent", label = "Transparent", onToggle = function()
      if VM.Window then VM.Window:ApplyTransparency() end
    end },
}

if not strsplit then
  function strsplit(sep, str)
    local results = {}
    local pattern = "([^" .. sep .. "]+)"
    string.gsub(str, pattern, function(c) table.insert(results, c) end)
    return unpack(results)
  end
end

local function GetSetting(path)
  local parts = { strsplit(".", path) }
  local val = VM.db
  for _, p in ipairs(parts) do
    if val then val = val[p] end
  end
  return val
end

local function SetSetting(path, value)
  local parts = { strsplit(".", path) }
  local target = VM.db
  for i = 1, table.getn(parts) - 1 do
    target = target[parts[i]]
  end
  target[parts[table.getn(parts)]] = value
end

function Config:Toggle()
  if self.frame and self.frame:IsVisible() then
    self.frame:Hide()
    if VM.Window and VM.Window.barContainer then
      VM.Window.barContainer:Show()
    end
    return
  end

  if VM.Window and VM.Window.barContainer then
    VM.Window.barContainer:Hide()
  end

  if not self.frame then
    self:CreatePanel()
  end

  self:RefreshToggles()
  self.frame:Show()
end

function Config:CreatePanel()
  local parent = VM.Window.frame
  if not parent then return end

  local f = CreateFrame("Frame", "VanillaMeterConfigPanel", parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -(VM.TAB_HEIGHT + 1))
  f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  })
  local bg = VM.db.appearance.bgColor
  f:SetBackdropColor(bg.r, bg.g, bg.b, VM.db.appearance.bgAlpha)
  f:Hide()

  local font = VM.db.appearance.font or "Fonts\\FRIZQT__.TTF"
  local fontSize = 10
  local rowHeight = 20

  -- ===== LEFT COLUMN: Settings Toggles =====
  local leftTitle = f:CreateFontString(nil, "OVERLAY")
  leftTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -14)
  leftTitle:SetFont(font, 11, "OUTLINE")
  leftTitle:SetText("SETTINGS")
  leftTitle:SetTextColor(0.9, 0.8, 0.2)

  self.toggles = {}
  for i, setting in ipairs(SETTINGS) do
    local yOffset = -14 - (i * rowHeight)

    local check = CreateFrame("Button", "VanillaMeterCfg_" .. i, f)
    check:SetWidth(14)
    check:SetHeight(14)
    check:SetPoint("TOPLEFT", f, "TOPLEFT", 10, yOffset)

    check.bg = check:CreateTexture(nil, "BACKGROUND")
    check.bg:SetTexture(0.2, 0.2, 0.2, 0.8)
    check.bg:SetAllPoints(check)

    check.mark = check:CreateFontString(nil, "OVERLAY")
    check.mark:SetAllPoints(check)
    check.mark:SetFont(font, 10, "OUTLINE")
    check.mark:SetJustifyH("CENTER")
    check.mark:SetText("")

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    label:SetFont(font, fontSize, "OUTLINE")
    label:SetText(setting.label)
    label:SetTextColor(0.85, 0.85, 0.85)

    check.settingKey = setting.key
    check.markText = check.mark
    check.onToggle = setting.onToggle

    check:SetScript("OnClick", function()
      local current = GetSetting(this.settingKey)
      SetSetting(this.settingKey, not current)
      Config:RefreshToggles()
      if this.onToggle then this.onToggle() end
    end)

    self.toggles[i] = check
  end

  -- ===== RIGHT COLUMN: Reset =====
  local resetY = -14
  local resetTitle = f:CreateFontString(nil, "OVERLAY")
  resetTitle:SetPoint("TOPLEFT", f, "TOP", -2, resetY)
  resetTitle:SetFont(font, 11, "OUTLINE")
  resetTitle:SetText("RESET")
  resetTitle:SetTextColor(0.9, 0.8, 0.2)

  local resetBtnY = resetY - rowHeight
  local resetBtns = {
    { label = "All Data", func = function()
      if VM.Data then VM.Data:Reset() end
      if VM.Detached then VM.Detached:ResetAll() end
      DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: All data reset.")
    end },
    { label = "Tabs", func = function()
      if VM.Tabs then VM.Tabs:ResetLayout() end
    end },
  }

  local resetGap = 2
  local resetStartX = -2
  local resetBtnWidth = 76

  for i, rb in ipairs(resetBtns) do
    local btn = CreateFrame("Button", "VanillaMeterCfgReset_" .. i, f)
    btn:SetHeight(16)
    local xPos = resetStartX + (i - 1) * (resetBtnWidth + resetGap)
    btn:SetPoint("TOPLEFT", f, "TOP", xPos, resetBtnY)
    btn:SetWidth(resetBtnWidth)

    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetTexture(0.25, 0.15, 0.15, 0.5)
    btnBg:SetAllPoints(btn)

    local btnLabel = btn:CreateFontString(nil, "OVERLAY")
    btnLabel:SetFont(font, fontSize, "OUTLINE")
    btnLabel:SetText(rb.label)
    btnLabel:SetTextColor(0.9, 0.5, 0.5)
    btnLabel:SetAllPoints(btn)
    btnLabel:SetJustifyH("CENTER")

    local callback = rb.func
    btn:SetScript("OnClick", function() callback() end)
    btn:SetScript("OnEnter", function()
      btnLabel:SetTextColor(1, 0.6, 0.6)
      btnBg:SetTexture(0.3, 0.18, 0.18, 0.7)
    end)
    btn:SetScript("OnLeave", function()
      btnLabel:SetTextColor(0.9, 0.5, 0.5)
      btnBg:SetTexture(0.25, 0.15, 0.15, 0.5)
    end)
  end

  self.frame = f
end

function Config:RefreshToggles()
  if not self.toggles then return end

  for i, check in ipairs(self.toggles) do
    local val = GetSetting(check.settingKey)
    if val then
      check.markText:SetText("|cff80ff80ON|r")
      check.bg:SetTexture(0.15, 0.35, 0.15, 0.8)
    else
      check.markText:SetText("|cffff8080OFF|r")
      check.bg:SetTexture(0.35, 0.15, 0.15, 0.8)
    end
  end
end
