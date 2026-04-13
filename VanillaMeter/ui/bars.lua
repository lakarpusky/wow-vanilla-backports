----------------------------------------------------------------------
-- VanillaMeter - Bars
-- Following ShaguDPS pattern: StatusBar with built-in texture
-- Custom textures as regular Texture layers
----------------------------------------------------------------------

local VM = VanillaMeter

VM.Bars = {}
local Bars = VM.Bars

-- BantoBar texture for the fill gradient
local BAR_FILL_PATH = "Interface\\AddOns\\VanillaMeter\\textures\\BantoBar"

-- Solid background color (#9b9b9b)
local BAR_BG_COLOR = { 0.608, 0.608, 0.608 }

local CLASS_ICON_COORDS = {
  ["WARRIOR"]  = { 0.00, 0.25, 0.00, 0.25 },
  ["MAGE"]     = { 0.25, 0.50, 0.00, 0.25 },
  ["ROGUE"]    = { 0.50, 0.75, 0.00, 0.25 },
  ["DRUID"]    = { 0.75, 1.00, 0.00, 0.25 },
  ["HUNTER"]   = { 0.00, 0.25, 0.25, 0.50 },
  ["SHAMAN"]   = { 0.25, 0.50, 0.25, 0.50 },
  ["PRIEST"]   = { 0.50, 0.75, 0.25, 0.50 },
  ["WARLOCK"]  = { 0.75, 1.00, 0.25, 0.50 },
  ["PALADIN"]  = { 0.00, 0.25, 0.50, 0.75 },
}

function Bars:CreateBar(parent, index)
  local db = VM.db.appearance
  local barHeight = db.barHeight
  local font = db.font or "Fonts\\FRIZQT__.TTF"
  local fontSize = db.fontSize or 12

  local bar = CreateFrame("Button", "VanillaMeterBar_" .. index, parent)
  bar:SetHeight(barHeight)
  bar:EnableMouse(true)
  bar:RegisterForClicks("LeftButtonDown", "RightButtonDown")

  -- Layer 1 (BACKGROUND): solid color #9b9b9b — starts after icon area
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetTexture(BAR_BG_COLOR[1], BAR_BG_COLOR[2], BAR_BG_COLOR[3], 1)
  bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", barHeight, 0)
  bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

  -- Layer 2 (ARTWORK): BantoBar.tga overlay - we'll manually set width in UpdateBar
  bar.fillTex = bar:CreateTexture(nil, "ARTWORK")
  bar.fillTex:SetTexture(BAR_FILL_PATH)
  bar.fillTex:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  bar.fillTex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)

  -- Layer 3 (OVERLAY): class color tint - semi-transparent solid color on top of BantoBar
  bar.tint = bar:CreateTexture(nil, "OVERLAY", nil, -1)
  bar.tint:SetTexture(1, 1, 1, 1)

  -- Class icon
  bar.icon = bar:CreateTexture(nil, "OVERLAY")
  bar.icon:SetWidth(barHeight)
  bar.icon:SetHeight(barHeight)
  bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
  bar.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")

  -- Rank text (on top of everything)
  bar.rankText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.rankText:SetJustifyH("LEFT")
  bar.rankText:SetFont(font, fontSize, "THINOUTLINE")

  -- Name text
  bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.nameText:SetPoint("LEFT", bar.rankText, "RIGHT", 2, 0)
  bar.nameText:SetJustifyH("LEFT")
  bar.nameText:SetFont(font, fontSize, "THINOUTLINE")

  -- Value text
  bar.valueText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.valueText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  bar.valueText:SetJustifyH("RIGHT")
  bar.valueText:SetFont(font, fontSize, "THINOUTLINE")

  bar:SetScript("OnEnter", function()
    if not this.data then return end
    Bars:ShowTooltip(this)
  end)

  bar:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  bar.data = nil
  bar:Hide()

  return bar
end

function Bars:UpdateBar(bar, rank, data, maxValue, datatype)
  if not bar or not data then return end

  bar.data = data
  bar.datatype = datatype

  local r, g, b = VM:GetClassColor(data.name)

  -- Always reserve icon space so bar visual area is consistently after the icon
  local iconW = bar.icon:GetWidth()

  -- Calculate fill percentage based on rankValue (effective for heal, raw for damage)
  local pct = 0
  if maxValue > 0 then
    pct = (data.rankValue or data.total) / maxValue
  end

  -- Fill width is within the bar area only (after icon)
  local barWidth = bar:GetWidth()
  local availWidth = barWidth - iconW
  local fillWidth = availWidth * pct
  if fillWidth < 1 then fillWidth = 1 end

  -- Show the RIGHT portion of the texture (gradient tail at the end)
  bar.fillTex:SetTexCoord(1 - pct, 1, 0, 1)

  -- Class color tint covers bar area only, not the icon space
  bar.tint:SetVertexColor(r, g, b, 0.45)
  bar.tint:ClearAllPoints()
  bar.tint:SetPoint("TOPLEFT", bar, "TOPLEFT", iconW, 0)
  bar.tint:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

  -- BantoBar stays untinted
  bar.fillTex:SetVertexColor(1, 1, 1, 1)

  -- Anchor fill to RIGHT side of bar, growing leftward
  bar.fillTex:ClearAllPoints()
  bar.fillTex:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  bar.fillTex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bar.fillTex:SetWidth(fillWidth)

  -- Class icon
  local class = data.class
  if class and not CLASS_ICON_COORDS[class] then
    class = nil
  end
  if class then
    bar.icon:SetTexCoord(unpack(CLASS_ICON_COORDS[class]))
    bar.icon:Show()
  else
    bar.icon:Hide()
  end

  -- Rank/name: always offset from reserved icon area (no class-conditional branching)
  local showRank = VM.db.appearance.showRank
  bar.rankText:ClearAllPoints()
  bar.nameText:ClearAllPoints()
  if showRank then
    bar.rankText:SetPoint("LEFT", bar, "LEFT", iconW + 3, 0)
    bar.rankText:SetText(rank .. ".")
    bar.rankText:Show()
    bar.nameText:SetPoint("LEFT", bar.rankText, "RIGHT", 2, 0)
  else
    bar.rankText:Hide()
    bar.nameText:SetPoint("LEFT", bar, "LEFT", iconW + 3, 0)
  end

  bar.nameText:SetText(data.name)
  bar.nameText:SetTextColor(r, g, b)

  if datatype == "heal" then
    local esum = data.esum or 0
    bar.valueText:SetText(
      VM:FormatNumber(esum) .. " / " .. VM:FormatNumber(data.total) ..
      " (" .. VM:FormatDPS(data.persec) .. " HPS)"
    )
  else
    bar.valueText:SetText(
      VM:FormatNumber(data.total) .. " (" .. VM:FormatDPS(data.persec) .. " DPS)"
    )
  end
  bar.valueText:SetTextColor(1, 1, 1)

  bar:Show()
end

function Bars:ShowTooltip(bar)
  if not bar.data then return end

  local data = bar.data
  local r, g, b = VM:GetClassColor(data.name)

  -- Anchor tooltip to top-right of the main window frame
  local mainFrame = VM.Window and VM.Window.frame
  if mainFrame then
    GameTooltip:SetOwner(mainFrame, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", 0, 2)
  else
    GameTooltip:SetOwner(bar, "ANCHOR_TOP")
  end
  GameTooltip:ClearLines()

  GameTooltip:AddLine(data.name .. "                    ", r, g, b)

  local activeTab = bar.datatype or VM.db.activeTab or "damage"

  if activeTab == "heal" then
    local esum      = data.esum or 0
    local overheal  = data.total - esum
    local effPct    = data.total > 0 and (esum / data.total * 100) or 0
    local ovPct     = 100 - effPct
    GameTooltip:AddDoubleLine("Total:",     VM:FormatNumber(data.total), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Effective:", VM:FormatNumber(esum)     .. " (" .. string.format("%.0f%%", effPct) .. ")", 0.8, 0.8, 0.8, 0.6, 1.0, 0.6)
    GameTooltip:AddDoubleLine("Overheal:",  VM:FormatNumber(overheal) .. " (" .. string.format("%.0f%%", ovPct)  .. ")", 0.8, 0.8, 0.8, 1.0, 0.5, 0.5)
    GameTooltip:AddDoubleLine("HPS:",       VM:FormatDPS(data.persec), 0.8, 0.8, 0.8, 1, 1, 1)
  else
    GameTooltip:AddDoubleLine("Total:", VM:FormatNumber(data.total),   0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("DPS:",   VM:FormatDPS(data.persec),     0.8, 0.8, 0.8, 1, 1, 1)
  end

  local segment = VM.Data[activeTab]
  if segment and segment[1] then
    local actor = segment[1][data.name]
    if actor then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Breakdown:", 0.9, 0.8, 0.2)

      local spells = {}
      for spell, amount in pairs(actor) do
        if type(amount) == "number" and spell and spell ~= ""
           and strsub(spell, 1, 1) ~= "_" then
          table.insert(spells, { name = spell, total = amount })
        end
      end
      table.sort(spells, function(a, b) return a.total > b.total end)

      local shown = 0
      for _, spell in ipairs(spells) do
        if shown >= 8 then break end
        local pct = 0
        if data.total > 0 then
          pct = (spell.total / data.total) * 100
        end
        GameTooltip:AddDoubleLine(
          spell.name,
          VM:FormatNumber(spell.total) .. "  " .. string.format("%.1f%%", pct),
          0.9, 0.9, 0.9,
          1, 1, 1
        )
        shown = shown + 1
      end
    end
  end

  GameTooltip:Show()
end
