----------------------------------------------------------------------
-- VanillaMeter - Tabs
-- Dynamic tab system: one default tab, add more via "+" button
-- Right-click tab to switch mode or detach (non-primary)
-- Hover "x" on non-primary tabs to close
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Tabs = {}
local Tabs = VM.Tabs

-- All available modes
local MODES = {
  { id = "damage", label = "Damage Done" },
  { id = "heal",   label = "Healing Done" },
}

-- Active / inactive colors
local ACTIVE_BG   = { r = 0.20, g = 0.20, b = 0.30, a = 0.95 }
local INACTIVE_BG = { r = 0.08, g = 0.08, b = 0.08, a = 0.80 }
local ACTIVE_TEXT   = { r = 1.0, g = 1.0, b = 1.0 }
local INACTIVE_TEXT = { r = 0.5, g = 0.5, b = 0.5 }

-- State
Tabs.openTabs = {}    -- ordered list: { {id="damage", btn=frame}, ... }
Tabs.addBtn = nil     -- the "+" button
Tabs.contextMenu = nil

----------------------------------------------------------------------
-- Get mode label by id
----------------------------------------------------------------------
local function GetModeLabel(id)
  for _, m in ipairs(MODES) do
    if m.id == id then return m.label end
  end
  return id
end

----------------------------------------------------------------------
-- Check if a mode is already open in any tab
----------------------------------------------------------------------
function Tabs:IsModeOpen(modeId)
  for _, tab in ipairs(self.openTabs) do
    if tab.id == modeId then return true end
  end
  return false
end

----------------------------------------------------------------------
-- Get list of modes NOT currently open
----------------------------------------------------------------------
function Tabs:GetAvailableModes()
  local available = {}
  for _, m in ipairs(MODES) do
    if not self:IsModeOpen(m.id) then
      table.insert(available, m)
    end
  end
  return available
end

----------------------------------------------------------------------
-- Init: create the first tab + the "+" button
----------------------------------------------------------------------
function Tabs:Init(parentFrame)
  local titleBar = VM.Window.titleBar
  if not titleBar then return end

  self.titleBar = titleBar
  self.openTabs = {}

  -- Create "+" button first so LayoutTabs can position it
  self:CreateAddButton()

  -- Create settings tab using the exact same CreateTabButton that works for DPS/HEALING
  local rptBtn = self:CreateTabButton("settings")
  rptBtn.text:SetText("")
  rptBtn:SetWidth(24)
  -- Add icon texture as the tab label
  rptBtn.icon = rptBtn:CreateTexture(nil, "ARTWORK")
  rptBtn.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
  rptBtn.icon:SetWidth(12)
  rptBtn.icon:SetHeight(12)
  rptBtn.icon:SetPoint("CENTER", rptBtn, "CENTER", 0, 0)
  rptBtn.icon:SetVertexColor(0.9, 0.8, 0.2)
  -- Override click: left = toggle config, right = report menu
  rptBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  rptBtn:SetScript("OnClick", function()
    CloseDropDownMenus()
    if arg1 == "RightButton" then
      Tabs:ShowReportContextMenu()
    else
      if VM.Config then VM.Config:Toggle() end
    end
  end)
  self.settingsTab = rptBtn

  -- Add default tab
  self:AddTab("damage")

  -- Set initial active tab
  self:SetActiveTab("damage")
end

----------------------------------------------------------------------
-- Create a tab button for a given mode
----------------------------------------------------------------------
function Tabs:CreateTabButton(modeId)
  local titleBar = self.titleBar
  local font = VM.db.appearance.font or "Fonts\\FRIZQT__.TTF"
  local tabHeight = VM.TAB_HEIGHT

  local label = GetModeLabel(modeId)

  local btn = CreateFrame("Button", "VanillaMeterTab_" .. modeId, titleBar)
  btn:SetHeight(tabHeight)

  -- Background (top gap, flush bottom)
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -1)
  btn.bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 1)

  -- Label
  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFont(font, 11, "OUTLINE")
  btn.text:SetText(label)
  btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)

  btn:SetWidth(math.max(40, btn.text:GetStringWidth() + 16))

  btn.modeId = modeId

  -- Left click: switch to this tab, Right click: context menu
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function()
    CloseDropDownMenus()
    if arg1 == "RightButton" then
      Tabs:ShowTabContextMenu(btn)
    else
      Tabs:SetActiveTab(btn.modeId)
    end
  end)

  return btn
end

----------------------------------------------------------------------
-- Add a tab for a mode
----------------------------------------------------------------------
function Tabs:AddTab(modeId)
  if self:IsModeOpen(modeId) then return end

  local btn = self:CreateTabButton(modeId)
  table.insert(self.openTabs, { id = modeId, btn = btn })

  self:LayoutTabs()
  self:UpdateAddButton()
  self:SetActiveTab(modeId)
end

----------------------------------------------------------------------
-- Remove a non-primary tab
----------------------------------------------------------------------
function Tabs:RemoveTab(modeId)
  local removedIndex = nil
  for i, tab in ipairs(self.openTabs) do
    if tab.id == modeId then
      removedIndex = i
      tab.btn:Hide()
      tab.btn:SetParent(nil)
      break
    end
  end

  if removedIndex then
    table.remove(self.openTabs, removedIndex)
  end

  self:LayoutTabs()
  self:UpdateAddButton()

  -- If we removed the active tab, switch to first remaining or clear
  if VM.db.activeTab == modeId then
    if table.getn(self.openTabs) > 0 then
      self:SetActiveTab(self.openTabs[1].id)
    else
      -- No tabs open: reset data, stop tracking
      VM.db.activeTab = nil
      if VM.Data then VM.Data:Reset() end
      VM.Window.needsRefresh = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: All tabs closed. Tracking paused.")
    end
  end
end

----------------------------------------------------------------------
-- Switch a tab's mode (right-click menu action)
----------------------------------------------------------------------
function Tabs:SwitchTabMode(tab, newModeId)
  if self:IsModeOpen(newModeId) then return end

  local oldId = tab.id
  tab.id = newModeId
  tab.btn.modeId = newModeId
  tab.btn.text:SetText(GetModeLabel(newModeId))
  tab.btn:SetWidth(math.max(40, tab.btn.text:GetStringWidth() + 16))

  self:LayoutTabs()

  -- If the switched tab was active, update the display
  if VM.db.activeTab == oldId then
    self:SetActiveTab(newModeId)
  end
end

----------------------------------------------------------------------
-- Layout tabs left-to-right + position "+" button
-- Settings tab always anchored to the right
----------------------------------------------------------------------
function Tabs:LayoutTabs()
  local padding = 2
  local xOffset = padding

  for _, tab in ipairs(self.openTabs) do
    tab.btn:ClearAllPoints()
    tab.btn:SetPoint("LEFT", self.titleBar, "LEFT", xOffset, 0)
    xOffset = xOffset + tab.btn:GetWidth() + padding
  end

  -- Position "+" button after last tab
  if self.addBtn then
    self.addBtn:ClearAllPoints()
    self.addBtn:SetPoint("LEFT", self.titleBar, "LEFT", xOffset, 0)
  end

  -- RPT tab at the very end (right-most)
  if self.settingsTab then
    self.settingsTab:ClearAllPoints()
    self.settingsTab:SetPoint("RIGHT", self.titleBar, "RIGHT", -2, 0)
  end

  -- RESET button before RPT tab
  local resetBtn = VM.Window and VM.Window.resetBtn
  if resetBtn and self.settingsTab then
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("RIGHT", self.settingsTab, "LEFT", -4, 0)
  end
end

----------------------------------------------------------------------
-- Create the "+" button
----------------------------------------------------------------------
function Tabs:CreateAddButton()
  local titleBar = self.titleBar
  local font = VM.db.appearance.font or "Fonts\\FRIZQT__.TTF"

  local btn = CreateFrame("Button", "VanillaMeterTabAdd", titleBar)
  btn:SetHeight(16)
  btn:SetWidth(20)

  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFont(font, 16, "OUTLINE")
  btn.text:SetText("+")
  btn.text:SetTextColor(0.4, 0.6, 0.8, 0.7)
  btn.text:SetAllPoints(btn)
  btn.text:SetJustifyH("CENTER")

  btn:SetScript("OnClick", function()
    Tabs:ShowAddContextMenu()
  end)
  btn:SetScript("OnEnter", function()
    if btn:IsEnabled() == 1 then
      btn.text:SetTextColor(0.5, 0.8, 1.0, 1.0)
    end
  end)
  btn:SetScript("OnLeave", function()
    if btn:IsEnabled() == 1 then
      btn.text:SetTextColor(0.4, 0.6, 0.8, 0.7)
    end
  end)

  self.addBtn = btn
end

----------------------------------------------------------------------
-- Update "+" button state (enabled/disabled)
----------------------------------------------------------------------
function Tabs:UpdateAddButton()
  if not self.addBtn then return end
  local available = self:GetAvailableModes()
  if table.getn(available) == 0 then
    self.addBtn:Disable()
    self.addBtn.text:SetTextColor(0.2, 0.3, 0.4, 0.3)
  else
    self.addBtn:Enable()
    self.addBtn.text:SetTextColor(0.4, 0.6, 0.8, 0.7)
  end
end

----------------------------------------------------------------------
-- Context menu: right-click on a tab to switch mode
----------------------------------------------------------------------
function Tabs:ShowTabContextMenu(btn)
  local tabEntry = nil
  local tabIndex = nil
  for i, tab in ipairs(self.openTabs) do
    if tab.btn == btn then
      tabEntry = tab
      tabIndex = i
      break
    end
  end
  if not tabEntry then return end

  if not self.contextMenu then
    self.contextMenu = CreateFrame("Frame", "VanillaMeterTabContextMenu", UIParent, "UIDropDownMenuTemplate")
  end

  local menu = self.contextMenu
  UIDropDownMenu_Initialize(menu, function()
    local info

    -- Mode switching options
    for _, m in ipairs(MODES) do
      info = UIDropDownMenu_CreateInfo()
      info.text = GetModeLabel(m.id)
      info.notCheckable = 1

      if Tabs:IsModeOpen(m.id) then
        info.disabled = 1
      end

      local modeId = m.id
      info.func = function()
        Tabs:SwitchTabMode(tabEntry, modeId)
        CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info)
    end

    -- Separator
    info = UIDropDownMenu_CreateInfo()
    info.text = ""
    info.disabled = 1
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info)

    -- Detach (non-primary only)
    if tabIndex > 1 then
      info = UIDropDownMenu_CreateInfo()
      info.text = "Detach"
      info.notCheckable = 1
      local detachId = tabEntry.id
      info.func = function()
        CloseDropDownMenus()
        -- Create detached window with this mode
        if VM.Detached then
          VM.Detached:Create(detachId)
        end
        -- Remove the tab from main window
        Tabs:RemoveTab(detachId)
      end
      UIDropDownMenu_AddButton(info)
    end

    -- Close Tab (removes this tab)
    info = UIDropDownMenu_CreateInfo()
    info.text = "Close Tab"
    info.notCheckable = 1
    local removeId = tabEntry.id
    info.func = function()
      CloseDropDownMenus()
      Tabs:RemoveTab(removeId)
    end
    UIDropDownMenu_AddButton(info)
  end, "MENU")

  ToggleDropDownMenu(1, nil, menu, btn, 0, 0)
end

----------------------------------------------------------------------
-- Context menu: "+" button to add a new tab
----------------------------------------------------------------------
function Tabs:ShowAddContextMenu()
  local available = self:GetAvailableModes()
  if table.getn(available) == 0 then return end

  if not self.addContextMenu then
    self.addContextMenu = CreateFrame("Frame", "VanillaMeterTabAddMenu", UIParent, "UIDropDownMenuTemplate")
  end

  local menu = self.addContextMenu
  UIDropDownMenu_Initialize(menu, function()
    for _, m in ipairs(available) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = GetModeLabel(m.id)
      info.notCheckable = 1
      local modeId = m.id
      info.func = function()
        Tabs:AddTab(modeId)
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

  ToggleDropDownMenu(1, nil, menu, self.addBtn, 0, 0)
end

----------------------------------------------------------------------
-- Report context menu (right-click on settings tab)
----------------------------------------------------------------------
function Tabs:ShowReportContextMenu()
  if not self.reportMenu then
    self.reportMenu = CreateFrame("Frame", "VanillaMeterTabReportMenu", UIParent, "UIDropDownMenuTemplate")
  end

  local channels = {
    { label = "Guild", channel = "GUILD" },
    { label = "Party", channel = "PARTY" },
    { label = "Raid",  channel = "RAID" },
  }

  UIDropDownMenu_Initialize(self.reportMenu, function()
    for _, ch in ipairs(channels) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = "Report (" .. ch.label .. ")"
      info.notCheckable = 1
      local channel = ch.channel
      info.func = function()
        if VM.Window then VM.Window:ReportToChat(channel) end
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

  ToggleDropDownMenu(1, nil, self.reportMenu, self.settingsTab, 0, 0)
end

----------------------------------------------------------------------
-- Set active tab (visual + data switch)
----------------------------------------------------------------------
function Tabs:SetActiveTab(tabId)
  VM.db.activeTab = tabId

  -- Close config panel if open
  if VM.Config and VM.Config.frame and VM.Config.frame:IsVisible() then
    VM.Config.frame:Hide()
    if VM.Window and VM.Window.barContainer then
      VM.Window.barContainer:Show()
    end
  end

  local transparent = VM.db.appearance.transparent
  for _, tab in ipairs(self.openTabs) do
    if tab.id == tabId then
      local a = transparent and 0.6 or ACTIVE_BG.a
      tab.btn.bg:SetTexture(ACTIVE_BG.r, ACTIVE_BG.g, ACTIVE_BG.b, a)
      tab.btn.text:SetTextColor(ACTIVE_TEXT.r, ACTIVE_TEXT.g, ACTIVE_TEXT.b)
    else
      local a = transparent and 0.3 or INACTIVE_BG.a
      tab.btn.bg:SetTexture(INACTIVE_BG.r, INACTIVE_BG.g, INACTIVE_BG.b, a)
      tab.btn.text:SetTextColor(INACTIVE_TEXT.r, INACTIVE_TEXT.g, INACTIVE_TEXT.b)
    end
  end

  VM.Window.scrollOffset = 0
  VM.Window.needsRefresh = true
end

----------------------------------------------------------------------
-- Reset tabs layout: close all tabs right-to-left, keep only DPS
----------------------------------------------------------------------
function Tabs:ResetLayout()
  -- Remove tabs from right to left
  while table.getn(self.openTabs) > 1 do
    local last = self.openTabs[table.getn(self.openTabs)]
    last.btn:Hide()
    last.btn:SetParent(nil)
    table.remove(self.openTabs)
  end

  -- If no tabs remain, re-add DPS
  if table.getn(self.openTabs) == 0 then
    self:AddTab("damage")
  end

  -- Make sure the remaining tab is DPS
  local firstTab = self.openTabs[1]
  if firstTab.id ~= "damage" then
    firstTab.id = "damage"
    firstTab.btn.modeId = "damage"
    firstTab.btn.text:SetText(GetModeLabel("damage"))
    firstTab.btn:SetWidth(math.max(40, firstTab.btn.text:GetStringWidth() + 16))
  end

  self:LayoutTabs()
  self:UpdateAddButton()
  self:SetActiveTab("damage")

  DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffVanillaMeter|r: Tabs reset to default.")
end
