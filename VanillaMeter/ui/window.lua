----------------------------------------------------------------------
-- VanillaMeter - Window
-- Main frame: drag, resize, transparency, scroll, bar container
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Window = {}
local Window = VM.Window

-- Frame references
Window.frame = nil
Window.barContainer = nil
Window.bars = {}
Window.maxBars = 20
Window.scrollOffset = 0
Window.needsRefresh = true
Window.visible = true

-- Refresh throttle
local REFRESH_INTERVAL = 0.5
local lastRefresh = 0

----------------------------------------------------------------------
-- Apply transparency state to main frame and all detached windows
----------------------------------------------------------------------
function Window:ApplyTransparency()
  if not self.frame then return end
  local db = VM.db
  if db.appearance.transparent then
    self.frame:SetBackdropColor(0, 0, 0, 0)
    self.frame:SetBackdropBorderColor(0, 0, 0, 0)
    if self.titleBar then
      self.titleBar:SetBackdropColor(0, 0, 0, 0)
      self.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
  else
    local bg = db.appearance.bgColor
    self.frame:SetBackdropColor(bg.r, bg.g, bg.b, db.appearance.bgAlpha)
    self.frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    if self.titleBar then
      self.titleBar:SetBackdropColor(bg.r, bg.g, bg.b, db.appearance.bgAlpha)
      self.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
  end
  if VM.Detached then VM.Detached:ApplyTransparency() end
  if VM.Tabs and VM.db.activeTab then VM.Tabs:SetActiveTab(VM.db.activeTab) end
end

----------------------------------------------------------------------
-- Initialize the main window
----------------------------------------------------------------------
function Window:Init()
  local db = VM.db.window
  local appearance = VM.db.appearance

  -- Main frame
  local f = CreateFrame("Frame", "VanillaMeterFrame", UIParent)
  f:SetWidth(db.width)
  f:SetHeight(db.height)
  f:SetPoint(db.point, UIParent, db.point, db.x, db.y)
  f:SetFrameStrata("MEDIUM")
  f:SetFrameLevel(1)
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetClampedToScreen(true)

  local barH = appearance.barHeight
  local barS = appearance.barSpacing
  f:SetMinResize(db.width,    VM.TAB_HEIGHT + barH + barS + 2)
  f:SetMaxResize(db.maxWidth, VM.TAB_HEIGHT + 10 * (barH + barS))
  f:EnableMouse(true)

  -- Background with transparency
  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile     = true,
    tileSize = 16,
    edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
  })

  self.frame = f

  -- Title bar (also acts as drag handle)
  self:CreateTitleBar(f)
  self:ApplyTransparency()

  -- Bar container (scrollable area below/above title bar)
  local tabHeight = VM.TAB_HEIGHT
  local barContainer = CreateFrame("Frame", "VanillaMeterBarContainer", f)

  local tabPos = VM.db.window.tabPosition or "top"
  if tabPos == "top" then
    barContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(tabHeight + 1))
    barContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  else
    barContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    barContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, tabHeight + 1)
  end
  self.barContainer = barContainer

  -- Drag from bar container area
  barContainer:EnableMouse(true)
  barContainer:SetScript("OnMouseDown", function()
    if VM.db.window.locked then return end
    if arg1 == "LeftButton" then
      f:StartMoving()
    end
  end)
  barContainer:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    Window:SavePosition()
  end)

  -- Create bar pool
  for i = 1, self.maxBars do
    self.bars[i] = VM.Bars:CreateBar(barContainer, i)
  end

  -- Scroll support
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function()
    Window:OnScroll(arg1)
  end)

  -- Resize handle
  self:CreateResizeHandle(f)

  -- Refresh timer
  f:SetScript("OnUpdate", function()
    if GetTime() - lastRefresh < REFRESH_INTERVAL then return end
    if Window.needsRefresh then
      Window:Refresh()
      Window.needsRefresh = false
      lastRefresh = GetTime()
    end
  end)

  -- Init tabs
  if VM.Tabs then VM.Tabs:Init(f) end

  -- Initial refresh
  self:Refresh()
end

----------------------------------------------------------------------
-- Title bar with tab buttons
----------------------------------------------------------------------
function Window:CreateTitleBar(parent)
  local tabHeight = VM.TAB_HEIGHT

  local titleBar = CreateFrame("Frame", "VanillaMeterTitleBar", parent)
  titleBar:SetHeight(tabHeight)

  local tabPos = VM.db.window.tabPosition or "top"

  if tabPos == "top" then
    titleBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
  else
    titleBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 1, 1)
    titleBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
  end

  titleBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  })
  titleBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

  local font = "Fonts\\FRIZQT__.TTF"

  -- Reset button (right side)
  local resetBtn = CreateFrame("Button", "VanillaMeterResetBtn", titleBar)
  resetBtn:SetHeight(tabHeight)
  resetBtn:SetWidth(38)
  resetBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
  local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY")
  resetLabel:SetFont(font, 10, "OUTLINE")
  resetLabel:SetText("RESET")
  resetLabel:SetTextColor(0.9, 0.4, 0.4)
  resetLabel:SetShadowOffset(1, -1)
  resetLabel:SetShadowColor(0, 0, 0, 0.8)
  resetLabel:SetAllPoints(resetBtn)
  resetLabel:SetJustifyH("CENTER")
  resetBtn:SetScript("OnClick", function()
    if VM.Data then VM.Data:Reset() end
    DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: Data reset.")
  end)
  resetBtn:SetScript("OnEnter", function() resetLabel:SetTextColor(1, 0.5, 0.5) end)
  resetBtn:SetScript("OnLeave", function() resetLabel:SetTextColor(0.9, 0.4, 0.4) end)

  self.titleBar = titleBar
  self.resetBtn = resetBtn
end

----------------------------------------------------------------------
-- Resize handle (bottom-right corner)
----------------------------------------------------------------------
function Window:CreateResizeHandle(parent)
  local handle = CreateFrame("Frame", "VanillaMeterResize", parent)
  handle:SetWidth(16)
  handle:SetHeight(16)
  handle:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  handle:EnableMouse(true)
  handle:SetFrameStrata("HIGH")
  handle:SetFrameLevel(parent:GetFrameLevel() + 10)

  -- Resize grip texture
  local grip = handle:CreateTexture(nil, "OVERLAY")
  grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetAllPoints(handle)
  handle.grip = grip

  handle:SetScript("OnMouseDown", function()
    if VM.db.window.locked then return end
    parent:StartSizing("BOTTOMRIGHT")
  end)

  handle:SetScript("OnMouseUp", function()
    parent:StopMovingOrSizing()
    Window:SavePosition()
    Window:LayoutBars()
    Window:Refresh()
  end)

  handle:SetScript("OnEnter", function()
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  end)

  handle:SetScript("OnLeave", function()
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  end)

  self.resizeHandle = handle
end

----------------------------------------------------------------------
-- Save current position to saved variables
----------------------------------------------------------------------
function Window:SavePosition()
  if not self.frame then return end

  local point, _, _, x, y = self.frame:GetPoint()
  VM.db.window.point  = point
  VM.db.window.x      = x
  VM.db.window.y      = y
  VM.db.window.width  = self.frame:GetWidth()
  VM.db.window.height = self.frame:GetHeight()
end

----------------------------------------------------------------------
-- Layout bars in the container
----------------------------------------------------------------------
function Window:LayoutBars()
  if not self.barContainer then return end

  local db = VM.db.appearance
  local containerHeight = self.barContainer:GetHeight()
  local containerWidth  = self.barContainer:GetWidth()
  local barHeight       = db.barHeight
  local barSpacing      = db.barSpacing

  local fitsInWindow = math.floor(containerHeight / (barHeight + barSpacing))

  for i = 1, self.maxBars do
    local bar = self.bars[i]
    if bar then
      bar:ClearAllPoints()
      bar:SetHeight(barHeight)

      local yOffset = -((i - 1) * (barHeight + barSpacing))
      bar:SetPoint("TOPLEFT", self.barContainer, "TOPLEFT", 0, yOffset)
      bar:SetPoint("TOPRIGHT", self.barContainer, "TOPRIGHT", 0, yOffset)
    end
  end

  return fitsInWindow
end

----------------------------------------------------------------------
-- Scroll handler
----------------------------------------------------------------------
function Window:OnScroll(delta)
  if delta > 0 then
    self.scrollOffset = math.max(0, self.scrollOffset - 1)
  else
    self.scrollOffset = self.scrollOffset + 1
  end
  self.needsRefresh = true
end

----------------------------------------------------------------------
-- Refresh the display with current data
----------------------------------------------------------------------
function Window:Refresh()
  if not self.frame or not self.barContainer then return end
  if not VM.Data then return end

  local activeTab = VM.db.activeTab or "damage"
  local sorted = VM.Data:GetSorted(activeTab, 1)

  local fitsInWindow = self:LayoutBars()
  if not fitsInWindow or fitsInWindow < 1 then fitsInWindow = 1 end

  -- Clamp scroll offset
  local maxOffset = math.max(0, table.getn(sorted) - fitsInWindow)
  if self.scrollOffset > maxOffset then
    self.scrollOffset = maxOffset
  end

  -- Get the top value for percentage scaling
  local topValue = 0
  if sorted[1] then
    topValue = sorted[1].total
  end

  -- Update bars
  for i = 1, self.maxBars do
    local bar = self.bars[i]
    local dataIndex = i + self.scrollOffset

    if bar then
      if sorted[dataIndex] and i <= fitsInWindow then
        VM.Bars:UpdateBar(bar, dataIndex, sorted[dataIndex], topValue, activeTab)
      else
        bar:Hide()
      end
    end
  end
end

----------------------------------------------------------------------
-- Toggle visibility
----------------------------------------------------------------------
function Window:Toggle()
  if not self.frame then return end

  if self.frame:IsVisible() then
    self.frame:Hide()
    self.visible = false
  else
    self.frame:Show()
    self.visible = true
    self.needsRefresh = true
  end
end

----------------------------------------------------------------------
-- Report current meter to chat
----------------------------------------------------------------------
function Window:ReportToChat(channel)
  if not VM.Data then return end

  local activeTab = VM.db.activeTab or "damage"
  local sorted = VM.Data:GetSorted(activeTab, 1)
  local label = activeTab == "damage" and "Damage" or "Healing"
  local perSecLabel = activeTab == "damage" and "DPS" or "HPS"

  SendChatMessage("--- VanillaMeter: " .. label .. " (Current) ---", channel)

  local count = math.min(table.getn(sorted), 10)
  for i = 1, count do
    local entry = sorted[i]
    local line = i .. ". " .. entry.name .. " - " .. VM:FormatNumber(entry.total) .. " (" .. VM:FormatDPS(entry.persec) .. " " .. perSecLabel .. ")"
    SendChatMessage(line, channel)
  end
end
