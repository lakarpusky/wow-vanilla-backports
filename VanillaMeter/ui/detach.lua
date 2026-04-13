----------------------------------------------------------------------
-- VanillaMeter - Detached Windows
-- Lightweight independent windows showing one fixed mode
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Detached = {}
local Detached = VM.Detached

-- All active detached windows
Detached.windows = {}

-- Counter for unique frame names
local nextId = 1

----------------------------------------------------------------------
-- Create a detached window for a given mode
----------------------------------------------------------------------
function Detached:Create(modeId)
  local id = nextId
  nextId = nextId + 1

  local db = VM.db.appearance
  local font = db.font or "Fonts\\FRIZQT__.TTF"
  local tabHeight = VM.TAB_HEIGHT
  local barHeight = db.barHeight
  local maxBars = 20
  local prefix = "VMDetach" .. id

  local labels = { damage = "Damage Done", heal = "Healing Done" }
  local modeLabel = labels[modeId] or modeId

  -- State for this window
  local win = {
    id = id,
    modeId = modeId,
    scrollOffset = 0,
    needsRefresh = true,
    bars = {},
    maxBars = maxBars,
  }

  -- Main frame
  local f = CreateFrame("Frame", prefix .. "Frame", UIParent)
  f:SetWidth(VM.db.window.width)
  f:SetHeight(VM.db.window.height)
  f:SetPoint("CENTER", UIParent, "CENTER", 30 * id, -30 * id)
  f:SetFrameStrata("MEDIUM")
  f:SetFrameLevel(1)
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetClampedToScreen(true)

  local barH = db.barHeight
  local barS = db.barSpacing
  local minW = VM.db.window.width
  f:SetMinResize(minW,                   VM.TAB_HEIGHT + barH + barS + 2)
  f:SetMaxResize(VM.db.window.maxWidth,  VM.TAB_HEIGHT + 10 * (barH + barS))
  f:EnableMouse(true)

  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile     = true,
    tileSize = 16,
    edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  if VM.db.appearance.transparent then
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0)
  else
    f:SetBackdropColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgAlpha)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
  end

  win.frame = f

  -- Title bar
  local titleBar = CreateFrame("Frame", prefix .. "TitleBar", f)
  titleBar:SetHeight(tabHeight)
  titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  titleBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  })
  if VM.db.appearance.transparent then
    titleBar:SetBackdropColor(0, 0, 0, 0)
  else
    titleBar:SetBackdropColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgAlpha)
  end
  win.titleBar = titleBar

  -- Mode label (acts as tab)
  local modeBtn = CreateFrame("Button", prefix .. "ModeBtn", titleBar)
  modeBtn:SetHeight(tabHeight)
  modeBtn:SetWidth(math.max(50, 16))
  modeBtn:SetPoint("LEFT", titleBar, "LEFT", 2, 0)

  modeBtn.bg = modeBtn:CreateTexture(nil, "BACKGROUND")
  modeBtn.bg:SetPoint("TOPLEFT", modeBtn, "TOPLEFT", 0, -1)
  modeBtn.bg:SetPoint("BOTTOMRIGHT", modeBtn, "BOTTOMRIGHT", 0, 1)
  local modeBtnAlpha = VM.db.appearance.transparent and 0.6 or 0.9
  modeBtn.bg:SetTexture(0.1, 0.1, 0.1, modeBtnAlpha)

  modeBtn.text = modeBtn:CreateFontString(nil, "OVERLAY")
  modeBtn.text:SetFont(font, 11, "OUTLINE")
  modeBtn.text:SetText(modeLabel)
  modeBtn.text:SetTextColor(1, 1, 1)
  modeBtn.text:SetPoint("CENTER", modeBtn, "CENTER", 0, 0)
  modeBtn:SetWidth(modeBtn.text:GetStringWidth() + 16)
  win.modeBtn = modeBtn

  -- Right-click mode label for report menu
  modeBtn:RegisterForClicks("RightButtonUp")
  modeBtn:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      Detached:ShowReportMenu(modeBtn, modeId, modeLabel)
    end
  end)

  -- Close X button (right side)
  local closeBtn = CreateFrame("Button", prefix .. "CloseBtn", titleBar)
  closeBtn:SetHeight(tabHeight)
  closeBtn:SetWidth(20)
  closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
  closeBtn:RegisterForClicks("LeftButtonUp")

  local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY")
  closeLabel:SetFont(font, 12, "OUTLINE")
  closeLabel:SetText("x")
  closeLabel:SetTextColor(0.7, 0.3, 0.3)
  closeLabel:SetAllPoints(closeBtn)
  closeLabel:SetJustifyH("CENTER")

  closeBtn:SetScript("OnClick", function()
    Detached:Destroy(id)
  end)
  closeBtn:SetScript("OnEnter", function()
    closeLabel:SetTextColor(1, 0.4, 0.4)
  end)
  closeBtn:SetScript("OnLeave", function()
    closeLabel:SetTextColor(0.7, 0.3, 0.3)
  end)

  -- Reset button
  local resetBtn = CreateFrame("Button", prefix .. "ResetBtn", titleBar)
  resetBtn:SetHeight(tabHeight)
  resetBtn:SetWidth(38)
  resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
  resetBtn:RegisterForClicks("LeftButtonUp")

  local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY")
  resetLabel:SetFont(font, 10, "OUTLINE")
  resetLabel:SetText("RESET")
  resetLabel:SetTextColor(0.9, 0.4, 0.4)
  resetLabel:SetShadowOffset(1, -1)
  resetLabel:SetShadowColor(0, 0, 0, 0.8)
  resetLabel:SetAllPoints(resetBtn)
  resetLabel:SetJustifyH("CENTER")

  resetBtn:SetScript("OnClick", function()
    -- Reset only this mode's data
    if VM.Data and VM.Data[modeId] then
      VM.Data[modeId] = { [0] = {}, [1] = {} }
      win.needsRefresh = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: " .. modeLabel .. " data reset.")
    end
  end)
  resetBtn:SetScript("OnEnter", function() resetLabel:SetTextColor(1, 0.5, 0.5) end)
  resetBtn:SetScript("OnLeave", function() resetLabel:SetTextColor(0.9, 0.4, 0.4) end)

  -- Bar container
  local barContainer = CreateFrame("Frame", prefix .. "BarContainer", f)
  barContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(tabHeight + 1))
  barContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  barContainer:EnableMouse(true)
  win.barContainer = barContainer

  -- Drag from bar container
  barContainer:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" then
      f:StartMoving()
    end
  end)
  barContainer:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
  end)

  -- Create bars
  for i = 1, maxBars do
    win.bars[i] = VM.Bars:CreateBar(barContainer, prefix .. "_" .. i)
  end

  -- Scroll
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function()
    if arg1 > 0 then
      win.scrollOffset = math.max(0, win.scrollOffset - 1)
    else
      win.scrollOffset = win.scrollOffset + 1
    end
    win.needsRefresh = true
  end)

  -- Resize handle
  local handle = CreateFrame("Frame", prefix .. "Resize", f)
  handle:SetWidth(16)
  handle:SetHeight(16)
  handle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  handle:EnableMouse(true)
  handle:SetFrameStrata("HIGH")

  local grip = handle:CreateTexture(nil, "OVERLAY")
  grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetAllPoints(handle)

  handle:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  handle:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    win.needsRefresh = true
  end)
  handle:SetScript("OnEnter", function()
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  end)
  handle:SetScript("OnLeave", function()
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  end)

  -- Refresh function for this window
  win.Refresh = function()
    if not win.frame or not win.barContainer then return end
    if not VM.Data then return end

    local sorted = VM.Data:GetSorted(modeId, 1)

    -- Layout bars
    local containerHeight = win.barContainer:GetHeight()
    local bh = db.barHeight
    local bs = db.barSpacing
    local fits = math.floor(containerHeight / (bh + bs))
    if fits < 1 then fits = 1 end

    for i = 1, maxBars do
      local bar = win.bars[i]
      if bar then
        bar:ClearAllPoints()
        bar:SetHeight(bh)
        local yOff = -((i - 1) * (bh + bs))
        bar:SetPoint("TOPLEFT", win.barContainer, "TOPLEFT", 0, yOff)
        bar:SetPoint("TOPRIGHT", win.barContainer, "TOPRIGHT", 0, yOff)
      end
    end

    -- Clamp scroll
    local maxOffset = math.max(0, table.getn(sorted) - fits)
    if win.scrollOffset > maxOffset then
      win.scrollOffset = maxOffset
    end

    local topValue = sorted[1] and (sorted[1].rankValue or sorted[1].total) or 0

    for i = 1, maxBars do
      local bar = win.bars[i]
      local dataIndex = i + win.scrollOffset
      if bar then
        if sorted[dataIndex] and i <= fits then
          VM.Bars:UpdateBar(bar, dataIndex, sorted[dataIndex], topValue, modeId)
        else
          bar:Hide()
        end
      end
    end
  end

  -- OnUpdate refresh timer
  local lastRefresh = 0
  f:SetScript("OnUpdate", function()
    if GetTime() - lastRefresh < 0.5 then return end
    if win.needsRefresh then
      win.Refresh()
      win.needsRefresh = false
      lastRefresh = GetTime()
    end
  end)

  -- Store and return
  self.windows[id] = win
  return win
end

----------------------------------------------------------------------
-- Destroy a detached window
----------------------------------------------------------------------
function Detached:Destroy(id)
  local win = self.windows[id]
  if not win then return end

  win.frame:Hide()
  win.frame:SetParent(nil)
  self.windows[id] = nil
end

----------------------------------------------------------------------
-- Mark all detached windows for refresh
----------------------------------------------------------------------
function Detached:RefreshAll()
  for _, win in pairs(self.windows) do
    win.needsRefresh = true
  end
end

----------------------------------------------------------------------
-- Reset all detached windows data (called from settings panel)
----------------------------------------------------------------------
function Detached:ResetAll()
  for _, win in pairs(self.windows) do
    if VM.Data and VM.Data[win.modeId] then
      VM.Data[win.modeId] = { [0] = {}, [1] = {} }
      win.needsRefresh = true
    end
  end
end

----------------------------------------------------------------------
-- Report menu for detached window
----------------------------------------------------------------------
local reportMenu = nil

function Detached:ShowReportMenu(anchor, modeId, modeLabel)
  if not reportMenu then
    reportMenu = CreateFrame("Frame", "VMDetachReportMenu", UIParent, "UIDropDownMenuTemplate")
  end

  UIDropDownMenu_Initialize(reportMenu, function()
    local channels = {
      { label = "Guild", channel = "GUILD" },
      { label = "Party", channel = "PARTY" },
      { label = "Raid",  channel = "RAID" },
    }

    for _, ch in ipairs(channels) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = "Report (" .. ch.label .. ")"
      info.notCheckable = 1
      local channel = ch.channel
      info.func = function()
        Detached:ReportToChat(modeId, modeLabel, channel)
        CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info)
    end

    local info = UIDropDownMenu_CreateInfo()
    info.text = ""
    info.disabled = 1
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Close"
    info.notCheckable = 1
    info.func = function() CloseDropDownMenus() end
    UIDropDownMenu_AddButton(info)
  end, "MENU")

  ToggleDropDownMenu(1, nil, reportMenu, anchor, 0, 0)
end

----------------------------------------------------------------------
-- Report detached window data to chat
----------------------------------------------------------------------
function Detached:ReportToChat(modeId, modeLabel, channel)
  if not VM.Data then return end

  local sorted = VM.Data:GetSorted(modeId, 1)
  local perSecLabel = modeId == "damage" and "DPS" or "HPS"

  SendChatMessage("--- VanillaMeter: " .. modeLabel .. " (Current) ---", channel)

  local count = math.min(table.getn(sorted), 10)
  for i = 1, count do
    local entry = sorted[i]
    local line = i .. ". " .. entry.name .. " - " .. VM:FormatNumber(entry.total) .. " (" .. VM:FormatDPS(entry.persec) .. " " .. perSecLabel .. ")"
    SendChatMessage(line, channel)
  end
end

----------------------------------------------------------------------
-- Apply transparency state to all open detached windows
----------------------------------------------------------------------
function Detached:ApplyTransparency()
  local db = VM.db
  for _, win in pairs(self.windows) do
    if win.frame then
      if db.appearance.transparent then
        win.frame:SetBackdropColor(0, 0, 0, 0)
        win.frame:SetBackdropBorderColor(0, 0, 0, 0)
        if win.titleBar then
          win.titleBar:SetBackdropColor(0, 0, 0, 0)
          win.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
        end
        if win.modeBtn then
          win.modeBtn.bg:SetTexture(0.1, 0.1, 0.1, 0.6)
        end
      else
        local bg = db.appearance.bgColor
        win.frame:SetBackdropColor(bg.r, bg.g, bg.b, db.appearance.bgAlpha)
        win.frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
        if win.titleBar then
          win.titleBar:SetBackdropColor(bg.r, bg.g, bg.b, db.appearance.bgAlpha)
          win.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
        end
        if win.modeBtn then
          win.modeBtn.bg:SetTexture(0.1, 0.1, 0.1, 0.9)
        end
      end
    end
  end
end
