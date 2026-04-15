-- SpellReplay (1.12.1 Vanilla / TurtleWoW Backport)
-- Original by Oldsalt (Smolderforge) for TBC/WotLK
-- Backported from 3.3.5a to 1.12.1
--
-- Lua 5.0 rules enforced:
--   SetScript handlers: function() with NO parameters
--   No select(), no ..., no #, no %, no string.match/gmatch
--   Use implicit globals: this, event, arg1..arg9
--   Use table.getn() instead of #
--   Use math.mod() instead of %
--   Use string.find() with captures instead of string.match
--   Use string.gfind() instead of string.gmatch

---------------------------------------------------------------------------
-- Lua 5.0 utility helpers
-- NOTE: maxn() removed — replaced by spellCount counter (see spellEntries state block)
---------------------------------------------------------------------------

local function abs(x)
    if x < 0 then return -x end
    return x
end

---------------------------------------------------------------------------
-- Spellbook icon cache
-- Scans player spellbook to build a spellName -> iconTexture lookup.
-- This is the 1.12.1 replacement for GetSpellInfo(id).
--
-- GetSpellNameByTexture() is O(1) instead of O(n) on every action press.
---------------------------------------------------------------------------

local spellIconCache = {}
local texIconCache   = {}

local function ScanSpellbook()
    spellIconCache = {}
    texIconCache   = {}
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
        if tex then
            spellIconCache[spellName] = tex
            texIconCache[tex]         = spellName
        end
        i = i + 1
    end
    -- Also scan pet spellbook
    i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_PET)
        if not spellName then break end
        local tex = GetSpellTexture(i, BOOKTYPE_PET)
        if tex then
            spellIconCache[spellName] = tex
            texIconCache[tex]         = spellName
        end
        i = i + 1
    end
end

local function GetSpellIcon(name)
    if not name then return nil end
    return spellIconCache[name]
end

local function GetSpellNameByTexture(tex)
    if not tex then return nil end
    return texIconCache[tex]
end

---------------------------------------------------------------------------
-- Settings defaults and persistence
---------------------------------------------------------------------------

local SR_DEFAULTS = {
    enabled     = 1,
    locked      = 0,
    showBg      = 1,
    scale       = 1.0,
    direction   = 1,    -- 1=right, 2=left
    cropTex     = 1,
    pushSpeed   = 100,
    baseSpeed   = 30,
    castSpeed   = 30,
    maxSpells   = 4,
    showResists = 1,
    resistFrame = 1,
    resistChat  = 1,
    showRanks   = 2,    -- 0=off, 1=all, 2=rank1only
    showDamage  = 1,    -- 0=off, 1=all, 2=critsonly
    showHeals   = 1,    -- 0=off, 1=all, 2=critsonly
    showMana    = 1,
    showPet     = 1,
    showWhite   = 2,    -- 0=off, 1=melee, 2=ranged, 3=both
}

--         enabled=0, which wiped all settings every login when the addon was
--         disabled. Changed to `== nil` to only reset truly missing keys.
--
--         in keys that are missing. New default keys added in future versions
--         will be picked up without blowing away existing user settings.
local function SR_InitSettings()
    if type(SpellReplaySaved) ~= "table" then
        SpellReplaySaved = {}
    end
    for k, v in pairs(SR_DEFAULTS) do
        if SpellReplaySaved[k] == nil then
            SpellReplaySaved[k] = v
        end
    end
end

-- Shorthand accessor
local function S()
    return SpellReplaySaved
end

---------------------------------------------------------------------------
-- Main display frame
---------------------------------------------------------------------------

local ReplayFrame = CreateFrame("Frame", "SpellReplayFrame", UIParent)
ReplayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
ReplayFrame:SetWidth(40)
ReplayFrame:SetHeight(40)
ReplayFrame:SetMovable(true)
ReplayFrame:EnableMouse(true)
ReplayFrame:SetClampedToScreen(true)

local ReplayBackground = ReplayFrame:CreateTexture(nil, "BACKGROUND")
ReplayBackground:SetAllPoints(ReplayFrame)
ReplayBackground:SetTexture(0, 0, 0, 0.15)

-- Mouse handlers for dragging and right-click lock toggle
-- NOTE: function() with NO parameters — Lua 5.0 rule
ReplayFrame:SetScript("OnMouseDown", function()
    if not S() then return end
    if arg1 == "LeftButton" and S().locked == 0 then
        this:StartMoving()
    end
end)

ReplayFrame:SetScript("OnMouseUp", function()
    this:StopMovingOrSizing()
    if not S() then return end
    if arg1 == "RightButton" then
        if S().locked == 0 then
            S().locked = 1
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Frame locked.")
        else
            S().locked = 0
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Frame unlocked.")
        end
    end
end)

ReplayFrame:SetScript("OnEnter", function()
    if S() and S().showBg == 0 then
        ReplayBackground:Show()
    end
end)

ReplayFrame:SetScript("OnLeave", function()
    if S() and S().showBg == 0 then
        ReplayBackground:Hide()
    end
end)

---------------------------------------------------------------------------
-- Spell tracking state
--
--
--   Before (mismatched indexing):
--     replayTexture[]    — 0-indexed  (replayTexture[0] = first spell)
--     replayRank[]       — 0-indexed
--     replayDamage[]     — 0-indexed
--     replayFont[]       — 0-indexed
--     replayFailTexture[]— 0-indexed
--     spellTable[]       — 1-indexed  (spellTable[1]    = first spell)
--     timestampTable[]   — 1-indexed
--     → replayTexture[i] corresponded to spellTable[i+1], a constant
--       off-by-one that was a latent maintenance hazard throughout.
--
--   After (unified, 1-indexed):
--     spellEntries[i] = {
--         tex     = <Texture>,
--         rank    = <FontString or nil>,
--         damage  = <FontString or nil>,
--         font    = <FontString or nil>,
--         failTex = <Texture or nil>,
--         name    = <string>,
--         time    = <number>,
--     }
--
--         replacing all maxn(spellTable) calls. maxn() iterated the full
--         table on every frame tick and every overlay lookup — now O(1).
---------------------------------------------------------------------------

local spellEntries = {}
local spellCount   = 0
local movSpeed     = 0
local endPos       = 0
local isCasting    = false

---------------------------------------------------------------------------
-- Helper: get the X offset from a texture's anchor point
---------------------------------------------------------------------------

local function GetOfsX(tex)
    if not tex then return 0 end
    local point, relativeTo, relativePoint, xOfs, yOfs = tex:GetPoint()
    if xOfs then return xOfs end
    return 0
end

---------------------------------------------------------------------------
-- Core: add a spell icon to the scrolling strip
---------------------------------------------------------------------------

local function AddSpellToStrip(spellName, iconPath, rankText)
    if not S() or S().enabled ~= 1 then return end
    if not iconPath then
        iconPath = GetSpellIcon(spellName)
    end
    if not iconPath then return end

    local count = spellCount

    local tex = ReplayFrame:CreateTexture(nil, "ARTWORK")
    tex:Hide()
    tex:SetWidth(40)
    tex:SetHeight(40)
    tex:SetTexture(iconPath)
    if S().cropTex == 1 then
        tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    end

    if count == 0 then
        -- First spell: anchor at origin
        tex:SetPoint("TOPLEFT", ReplayFrame, "TOPLEFT", 0, 0)
        spellEntries[1] = { tex = tex, name = spellName, time = GetTime() }
    else
        -- Duplicate suppression: same spell within 0.5s
        local prev = spellEntries[count]
        if prev and spellName == prev.name and (GetTime() - prev.time) < 0.5 then
            tex:Hide()  -- clean up the texture we pre-created
            return
        end

        -- Position relative to the previous icon
        local prevX = (prev and prev.tex) and GetOfsX(prev.tex) or 0
        local newOfsX
        if S().direction == 1 then
            -- Scrolling right: new icons stack to the left
            newOfsX = (not prev or prevX > 40) and 0 or (prevX - 40)
        else
            -- Scrolling left: new icons stack to the right
            newOfsX = (not prev or prevX < -40) and 0 or (prevX + 40)
        end
        tex:SetPoint("TOPLEFT", ReplayFrame, "TOPLEFT", newOfsX, 0)
        spellEntries[count + 1] = { tex = tex, name = spellName, time = GetTime() }
    end

    spellCount = spellCount + 1

    -- Add rank label if configured
    local idx = spellCount
    local entry = spellEntries[idx]
    if rankText and S().showRanks ~= 0 and entry and entry.tex then
        local _, _, rankNum = string.find(rankText, "(%d+)")
        if rankNum then
            local shouldShow = (S().showRanks == 1) or (S().showRanks == 2 and rankNum == "1")
            if shouldShow then
                local fs = ReplayFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                fs:SetPoint("CENTER", entry.tex, "CENTER", 0, 28)
                fs:SetFont("Fonts\\FRIZQT__.TTF", 9)
                fs:SetJustifyH("CENTER")
                fs:SetText("|cff107be5R" .. rankNum)
                fs:Hide()
                entry.rank = fs
            end
        end
    end
end

---------------------------------------------------------------------------
-- Overlays: damage, heals, mana, resists
---------------------------------------------------------------------------

local function AddDamageOverlay(spellName, amount, isCritical, isHeal)
    if not S() then return end
    if isHeal     and S().showHeals  == 0 then return end
    if not isHeal and S().showDamage == 0 then return end
    if not isCritical then
        if isHeal     and S().showHeals  == 2 then return end
        if not isHeal and S().showDamage == 2 then return end
    end

    for i = spellCount, 1, -1 do
        local e = spellEntries[i]
        if e and e.name == spellName and e.tex and not e.damage and not e.font then
            local fs = ReplayFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetJustifyH("CENTER")

            local color, prefix
            if isHeal then
                color  = "|cff00b200"
                prefix = "+"
            else
                color  = "|cffffff00"
                prefix = ""
            end

            if isCritical then
                fs:SetFont("Fonts\\FRIZQT__.TTF", 12)
                fs:SetPoint("CENTER", e.tex, "CENTER", 0, -26)
            else
                fs:SetFont("Fonts\\FRIZQT__.TTF", 9)
                fs:SetPoint("CENTER", e.tex, "CENTER", 0, -25)
            end
            fs:SetText(color .. prefix .. amount)

            -- Hide if the icon has already scrolled past the visible area
            local ofsX = GetOfsX(e.tex)
            if (S().direction == 1 and ofsX < 0) or (S().direction == 2 and ofsX > 0) then
                fs:Hide()
            end
            e.damage = fs
            break
        end
    end
end

local function AddManaOverlay(spellName, amount)
    if not S() or S().showMana ~= 1 then return end
    local e = spellEntries[spellCount]
    if e and e.name == spellName and e.tex and not e.damage then
        local fs = ReplayFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("CENTER", e.tex, "CENTER", 0, -25)
        fs:SetJustifyH("CENTER")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9)
        fs:SetText("|cff0080ff+" .. amount)
        local ofsX = GetOfsX(e.tex)
        if (S().direction == 1 and ofsX < 0) or (S().direction == 2 and ofsX > 0) then
            fs:Hide()
        end
        e.damage = fs
    end
end

local function AddResistOverlay(spellName, missType)
    if not S() or S().showResists ~= 1 then return end

    if S().resistFrame == 1 then
        for i = spellCount, 1, -1 do
            local e = spellEntries[i]
            if e and e.tex and not e.font then
                local icon = GetSpellIcon(spellName)
                if icon and e.tex:GetTexture() == icon then
                    local cross = ReplayFrame:CreateTexture(nil, "OVERLAY")
                    cross:SetPoint("CENTER", e.tex, "CENTER", 0, 0)
                    cross:SetWidth(35)
                    cross:SetHeight(35)
                    cross:SetTexture("Interface\\AddOns\\SpellReplay\\RedCross")

                    local fs = ReplayFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                    fs:SetPoint("CENTER", e.tex, "CENTER", 0, -26)
                    fs:SetFont("Fonts\\FRIZQT__.TTF", 8)
                    fs:SetJustifyH("CENTER")
                    fs:SetText("|cffffa500" .. missType)

                    local ofsX = GetOfsX(e.tex)
                    if (S().direction == 1 and ofsX < 0) or (S().direction == 2 and ofsX > 0) then
                        cross:Hide()
                        fs:Hide()
                    end
                    e.failTex = cross
                    e.font    = fs
                    break
                end
            end
        end
    end

    if S().resistChat == 1 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffa500" .. spellName .. " failed (" .. missType .. ")")
    end
end

---------------------------------------------------------------------------
-- Spell addition with dedup
-- Prevents double-adding from both SPELLCAST and combat log events
---------------------------------------------------------------------------

local lastAddedSpell = nil
local lastAddedTime  = 0

local function TryAddSpell(spellName, rankText)
    if not spellName or spellName == "" then return end
    -- Dedup: same spell within 0.3s from another event source
    if spellName == lastAddedSpell and (GetTime() - lastAddedTime) < 0.3 then
        return
    end
    -- Auto Shot / Shoot (ranged auto): show weapon icon if enabled
    if spellName == "Auto Shot" or spellName == "Shoot" then
        if not S() then return end
        if S().showWhite == 2 or S().showWhite == 3 then
            local tex = GetInventoryItemTexture("player", 18)  -- ranged slot
            if tex then
                AddSpellToStrip(spellName, tex, nil)
                lastAddedSpell = spellName
                lastAddedTime  = GetTime()
            end
        end
        return
    end
    -- Melee auto-attack: handled by AddMeleeAutoAttack, not here
    if spellName == "Attack" then return end
    local icon = GetSpellIcon(spellName)
    if icon then
        AddSpellToStrip(spellName, icon, rankText)
        lastAddedSpell = spellName
        lastAddedTime  = GetTime()
    end
end

-- Dedicated function for melee auto-attack (weapon icon + druid form support)
local function AddMeleeAutoAttack()
    if not S() then return end
    if S().showWhite ~= 1 and S().showWhite ~= 3 then return end
    local spellName = "Attack"
    -- Dedup
    if spellName == lastAddedSpell and (GetTime() - lastAddedTime) < 0.3 then
        return
    end
    local tex = nil
    -- Druid form-specific icons (matching original addon)
    local _, playerClass = UnitClass("player")
    if playerClass == "DRUID" then
        local form = GetShapeshiftForm()
        if form == 3 then  -- cat form
            tex = "Interface\\Icons\\Ability_Druid_CatFormAttack"
        elseif form == 1 then  -- bear form
            tex = "Interface\\Icons\\Ability_Druid_Swipe"
        end
    end
    -- Default: main hand weapon icon
    if not tex then
        tex = GetInventoryItemTexture("player", 16)  -- main hand slot
    end
    if tex then
        AddSpellToStrip(spellName, tex, nil)
        lastAddedSpell = spellName
        lastAddedTime  = GetTime()
    end
end

---------------------------------------------------------------------------
-- Combat log string parsers (English locale, Lua 5.0 patterns)
-- These parse arg1 from CHAT_MSG_SPELL_* events.
-- Format reference: https://wowpedia.fandom.com/wiki/CHAT_MSG_SPELL_SELF_DAMAGE
--   "Your Fireball hits Snivvle for 842."
--   "Your Fireball crits Snivvle for 1200 Fire damage."
--   "Your Banish was resisted by Felguard Elite."
--   "Your Fire Blast failed. Firelord is immune."
--   "Your Renew heals Target for 400."
--   "Your Renew critically heals Target for 800."
--   "You gain 300 Mana from Life Tap."
---------------------------------------------------------------------------

local function ParseSelfDamage(msg)
    -- Crit: "Your SpellName crits Target for Amount"
    local _, _, name, amt = string.find(msg, "^Your (.+) crits .+ for (%d+)")
    if name then
        TryAddSpell(name, nil)
        AddDamageOverlay(name, amt, true, false)
        return
    end
    -- Hit: "Your SpellName hits Target for Amount"
    _, _, name, amt = string.find(msg, "^Your (.+) hits .+ for (%d+)")
    if name then
        TryAddSpell(name, nil)
        AddDamageOverlay(name, amt, false, false)
        return
    end
end

local function ParseSelfHeal(msg)
    -- Critical heal: "Your SpellName critically heals Target for Amount"
    local _, _, name, amt = string.find(msg, "^Your (.+) critically heals .+ for (%d+)")
    if name then
        TryAddSpell(name, nil)
        AddDamageOverlay(name, amt, true, true)
        return
    end
    -- Normal heal: "Your SpellName heals Target for Amount"
    _, _, name, amt = string.find(msg, "^Your (.+) heals .+ for (%d+)")
    if name then
        TryAddSpell(name, nil)
        AddDamageOverlay(name, amt, false, true)
        return
    end
end

local function ParseSelfMissed(msg)
    local _, _, name
    _, _, name = string.find(msg, "^Your (.+) was resisted")
    if name then AddResistOverlay(name, "RESIST") return end
    _, _, name = string.find(msg, "^Your (.+) missed")
    if name then AddResistOverlay(name, "MISS") return end
    _, _, name = string.find(msg, "^Your (.+) was dodged")
    if name then AddResistOverlay(name, "DODGE") return end
    _, _, name = string.find(msg, "^Your (.+) was parried")
    if name then AddResistOverlay(name, "PARRY") return end
    _, _, name = string.find(msg, "^Your (.+) was blocked")
    if name then AddResistOverlay(name, "BLOCK") return end
    _, _, name = string.find(msg, "^Your (.+) was evaded")
    if name then AddResistOverlay(name, "EVADE") return end
    _, _, name = string.find(msg, "^Your (.+) is absorbed")
    if name then return end  -- absorbs: don't mark as fail (matches original)
    _, _, name = string.find(msg, "^Your (.+) failed")
    if name then AddResistOverlay(name, "IMMUNE") return end
end

local function ParseManaGain(msg)
    -- "You gain 300 Mana from Life Tap."
    local _, _, amt, name = string.find(msg, "^You gain (%d+) Mana from (.+)%.")
    if name and amt then
        AddManaOverlay(name, amt)
        return
    end
    -- "You gain 40 Energy from Thistle Tea."
    _, _, amt, name = string.find(msg, "^You gain (%d+) Energy from (.+)%.")
    if name and amt then
        AddManaOverlay(name, amt)
    end
end

local function ParsePetDamage(msg)
    if not S() or S().showPet ~= 1 then return end
    -- Pet messages: "PetName's SpellName hits/crits Target for Amount"
    local _, _, fullName = string.find(msg, "^(.+) hits")
    if not fullName then
        _, _, fullName = string.find(msg, "^(.+) crits")
    end
    if not fullName then return end
    -- Extract spell name after "'s "
    local _, _, petSpell = string.find(fullName, "'s (.+)")
    if not petSpell then return end
    local icon = GetSpellIcon(petSpell)
    if not icon then return end
    AddSpellToStrip(petSpell, icon, nil)
    -- Tag the newly-added entry as PET
    local e = spellEntries[spellCount]
    if e and e.tex and not e.rank then
        local fs = ReplayFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("CENTER", e.tex, "CENTER", 0, 28)
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9)
        fs:SetJustifyH("CENTER")
        fs:SetText("|cff2e8b57PET")
        fs:Hide()
        e.rank = fs
    end
end

---------------------------------------------------------------------------
-- Melee auto-attack parser (CHAT_MSG_COMBAT_SELF_HITS / MISSES)
-- Formats from vanilla GlobalStrings:
--   "You hit Target for 100."
--   "You crit Target for 200."
--   "You attack. Target dodges." / parries / blocks / etc.
---------------------------------------------------------------------------

local function ParseMeleeHit(msg)
    -- "You crit Target for Amount."
    local _, _, amt = string.find(msg, "^You crit .+ for (%d+)")
    if amt then
        AddMeleeAutoAttack()
        AddDamageOverlay("Attack", amt, true, false)
        return
    end
    -- "You hit Target for Amount."
    _, _, amt = string.find(msg, "^You hit .+ for (%d+)")
    if amt then
        AddMeleeAutoAttack()
        AddDamageOverlay("Attack", amt, false, false)
        return
    end
end

local function ParseMeleeMiss(msg)
    -- "You attack. Target dodges/parries/blocks/etc."
    if string.find(msg, "^You attack") then
        AddMeleeAutoAttack()
        -- No resist overlay for melee auto misses (matches original behavior:
        -- the icon shows but no RedCross since there's no spell to match)
    end
end

---------------------------------------------------------------------------
-- OnUpdate: scroll spell icons across the frame
-- Mirrors the original WotLK scrolling logic
--
--         is now 1 (not 0) to match the unified 1-indexed table
---------------------------------------------------------------------------

local SR_UpdateFrame = CreateFrame("Frame", "SpellReplayUpdateFrame")

SR_UpdateFrame:SetScript("OnUpdate", function()
    local elapsed = arg1
    local s = S()
    if not s then return end

    local count = spellCount
    if count <= 0 then return end

    local topIdx = count
    if not spellEntries[topIdx] or not spellEntries[topIdx].tex then return end

    local dir      = s.direction
    local topOfsX  = GetOfsX(spellEntries[topIdx].tex)

    -- Choose movement speed based on scroll state
    if dir == 1 then
        endPos = s.maxSpells * 40
        if topOfsX < 0 then
            movSpeed = s.pushSpeed
        elseif isCasting then
            movSpeed = s.castSpeed
        else
            movSpeed = s.baseSpeed
        end
    else
        endPos = -(s.maxSpells * 40)
        if topOfsX > 0 then
            movSpeed = -(s.pushSpeed)
        elseif isCasting then
            movSpeed = -(s.castSpeed)
        else
            movSpeed = -(s.baseSpeed)
        end
    end

    for i = topIdx, 1, -1 do
        local e = spellEntries[i]
        if not e or not e.tex then
            break
        end

        local ofsX = GetOfsX(e.tex)
        local newX  = ofsX + movSpeed * elapsed

        -- Show icons that cross into the visible area
        if not e.tex:IsShown() then
            if (dir == 1 and ofsX > 0) or (dir == 2 and ofsX < 0) then
                e.tex:Show()
                if e.rank    then e.rank:Show()    end
                if e.damage  then e.damage:Show()  end
                if e.font    then e.font:Show()    end
                if e.failTex then e.failTex:Show() end
            end
        end

        if (dir == 1 and ofsX < endPos - 20) or (dir == 2 and ofsX > endPos + 20) then
            -- Still scrolling normally
            e.tex:SetPoint("TOPLEFT", ReplayFrame, "TOPLEFT", newX, 0)

        elseif (dir == 1 and ofsX < endPos) or (dir == 2 and ofsX > endPos) then
            -- Fade zone: approaching end position
            e.tex:SetPoint("TOPLEFT", ReplayFrame, "TOPLEFT", newX, 0)
            local alpha = abs(endPos - ofsX) / 20
            e.tex:SetAlpha(alpha)
            if e.rank    then e.rank:SetAlpha(alpha)    end
            if e.damage  then e.damage:SetAlpha(alpha)  end
            if e.font    then e.font:SetAlpha(alpha)    end
            if e.failTex then e.failTex:SetAlpha(alpha) end

        else
            -- Past end position: hide and release
            e.tex:Hide()
            if e.rank    then e.rank:Hide()    end
            if e.damage  then e.damage:Hide()  end
            if e.font    then e.font:Hide()    end
            if e.failTex then e.failTex:Hide() end
            spellEntries[i] = nil
        end
    end
end)

---------------------------------------------------------------------------
-- Global function hooks for instant cast detection
-- In vanilla 1.12.1, there is no hooksecurefunc(). We use old-style hooks:
-- save original function, replace global, call original inside wrapper.
-- Unlike SetScript handlers, these are normal Lua functions and DO receive
-- parameters normally.
-- Reference: Chronometer addon on TurtleWoW wiki uses this exact pattern.
---------------------------------------------------------------------------

local SR_orig_UseAction       = nil
local SR_orig_CastSpellByName = nil
local SR_orig_CastSpell       = nil

local function SR_InstallHooks()
    -- Hook UseAction(slot, checkCursor, onSelf)
    -- Called when player clicks an action button or presses a keybind.
    --
    -- Range check uses the slot-based APIs confirmed in vanilla 1.12.1:
    --   ActionHasRange(slot) — returns 1 if the spell has a numeric range
    --     requirement shown in its tooltip (e.g. Fire Blast 20yd). Returns nil
    --     for melee abilities (Attack, Heroic Strike) which have no listed range.
    --   IsActionInRange(slot) — returns 0 if out of range, 1 if in range,
    --     nil if no target or range does not apply.
    --
    -- We only suppress the icon when ActionHasRange confirms a range requirement
    -- AND IsActionInRange returns 0 (explicitly out of range). A nil from
    -- IsActionInRange means either no target or range not applicable — in both
    -- cases we let the icon through.
    if not SR_orig_UseAction then
        SR_orig_UseAction = UseAction
        UseAction = function(slot, checkCursor, onSelf)
            if slot and HasAction(slot) and not GetActionText(slot) then
                local tex = GetActionTexture(slot)
                if tex then
                    if IsAttackAction(slot) then
                        AddMeleeAutoAttack()
                    else
                        if not (ActionHasRange(slot) and IsActionInRange(slot) == 0) then
                            local spellName = GetSpellNameByTexture(tex)
                            if spellName then
                                TryAddSpell(spellName, nil)
                            end
                        end
                    end
                end
            end
            return SR_orig_UseAction(slot, checkCursor, onSelf)
        end
    end

    -- Hook CastSpellByName(name, onSelf) — called from macros and scripts.
    -- No range check here: macros handle their own targeting logic and
    -- calling IsSpellInRange inside this hook risks blocking the original
    -- if any error occurs before the return.
    if not SR_orig_CastSpellByName then
        SR_orig_CastSpellByName = CastSpellByName
        CastSpellByName = function(name, onSelf)
            if name then
                local _, _, cleanName = string.find(name, "^(.+)%(")
                if not cleanName then cleanName = name end
                TryAddSpell(cleanName, nil)
            end
            return SR_orig_CastSpellByName(name, onSelf)
        end
    end

    -- Hook CastSpell(spellID, bookType) — called when casting by spellbook index.
    if not SR_orig_CastSpell then
        SR_orig_CastSpell = CastSpell
        CastSpell = function(id, bookType)
            if id and bookType then
                local spellName = GetSpellName(id, bookType)
                if spellName then TryAddSpell(spellName, nil) end
            end
            return SR_orig_CastSpell(id, bookType)
        end
    end
end

---------------------------------------------------------------------------
-- Event handler frame
---------------------------------------------------------------------------

local SR_EventFrame = CreateFrame("Frame", "SpellReplayEventFrame")
SR_EventFrame:RegisterEvent("PLAYER_LOGIN")
SR_EventFrame:RegisterEvent("SPELLCAST_START")
SR_EventFrame:RegisterEvent("SPELLCAST_STOP")
SR_EventFrame:RegisterEvent("SPELLCAST_FAILED")
SR_EventFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
SR_EventFrame:RegisterEvent("SPELLCAST_CHANNEL_START")
SR_EventFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
SR_EventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
SR_EventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
SR_EventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
SR_EventFrame:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
SR_EventFrame:RegisterEvent("CHAT_MSG_SPELL_PET_BUFF")
SR_EventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
SR_EventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
SR_EventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
SR_EventFrame:RegisterEvent("SPELLS_CHANGED")

-- NOTE: function() with NO parameters. event, arg1..arg9 are implicit globals.
SR_EventFrame:SetScript("OnEvent", function()

    if event == "PLAYER_LOGIN" then
        SR_InitSettings()
        ScanSpellbook()
        SR_InstallHooks()
        if S().enabled == 1 then
            ReplayFrame:Show()
        else
            ReplayFrame:Hide()
        end
        if S().showBg == 1 then
            ReplayBackground:Show()
        else
            ReplayBackground:Hide()
        end
        ReplayFrame:SetScale(S().scale)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay|r (1.12.1) loaded. Type |cff00ccff/sr|r for commands.")
        return
    end

    if event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
        ScanSpellbook()
        return
    end

    -- Cast tracking: SPELLCAST_START fires for spells with cast time
    -- arg1 = spell name, arg2 = cast time in ms
    if event == "SPELLCAST_START" then
        isCasting = true
        TryAddSpell(arg1, nil)
        return
    end

    -- Previously this only set isCasting=true and dropped arg1, so channeled
    -- spells with no damage output (Mind Control, Drain Mana, Hypnotize, etc.)
    -- were silently never shown in the strip.
    if event == "SPELLCAST_CHANNEL_START" then
        isCasting = true
        if arg1 then TryAddSpell(arg1, nil) end
        return
    end

    if event == "SPELLCAST_STOP" or event == "SPELLCAST_CHANNEL_STOP" then
        isCasting = false
        return
    end

    if event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        isCasting = false
        return
    end

    -- Combat log events: arg1 = combat log text string
    local msg = arg1
    if not msg then return end

    if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        ParseSelfDamage(msg)
        ParseSelfMissed(msg)
        return
    end

    if event == "CHAT_MSG_SPELL_SELF_BUFF" then
        ParseSelfHeal(msg)
        ParseManaGain(msg)
        return
    end

    if event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
        ParseManaGain(msg)
        return
    end

    if event == "CHAT_MSG_SPELL_PET_DAMAGE" or event == "CHAT_MSG_SPELL_PET_BUFF" then
        ParsePetDamage(msg)
        return
    end

    if event == "CHAT_MSG_COMBAT_SELF_HITS" then
        ParseMeleeHit(msg)
        return
    end

    if event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        ParseMeleeMiss(msg)
        return
    end
end)

---------------------------------------------------------------------------
-- Slash commands: /sr or /spellreplay
---------------------------------------------------------------------------

SLASH_SPELLREPLAY1 = "/spellreplay"
SLASH_SPELLREPLAY2 = "/sr"

local function SR_OnOff(val)
    if val == 1 then return "|cff00ff00ON|r" end
    return "|cffff0000OFF|r"
end

local function SR_DirStr(val)
    if val == 1 then return "Right" end
    return "Left"
end

local function SR_DmgStr(val)
    if val == 0 then return "Off"
    elseif val == 1 then return "All"
    end
    return "Crits only"
end

local function SR_RankStr(val)
    if val == 0 then return "Off"
    elseif val == 1 then return "All"
    end
    return "Rank 1 only"
end

local function SR_WhiteStr(val)
    if val == 0 then return "Off"
    elseif val == 1 then return "Melee"
    elseif val == 2 then return "Ranged"
    end
    return "Both"
end

local function SR_PrintHelp()
    local c = "|cff00ccff"
    DEFAULT_CHAT_FRAME:AddMessage(c .. "SpellReplay 1.12.1 Commands:|r")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr enable|r - Toggle on/off")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr lock|r - Toggle position lock")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr bg|r - Toggle background visibility")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr dir|r - Toggle scroll direction")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr scale <0.8-1.5>|r - Frame scale")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr push <30-150>|r - Push speed")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr base <0-100>|r - Base scroll speed")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr cast <0-100>|r - Casting scroll speed")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr spells <2-6>|r - Spells displayed")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr crop|r - Toggle icon border crop")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr resists|r - Toggle resist display")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr damage <off|all|crit>|r")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr heals <off|all|crit>|r")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr mana|r - Toggle mana gain display")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr pet|r - Toggle pet spell display")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr ranks <off|all|r1>|r")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr white <off|melee|ranged|both>|r - Auto-attacks")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr reset|r - Reset to defaults")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/sr status|r - Show current settings")
end

local function SR_PrintStatus()
    local s = S()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay Status:|r")
    DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. SR_OnOff(s.enabled) .. "  Locked: " .. SR_OnOff(s.locked) .. "  BG: " .. SR_OnOff(s.showBg))
    DEFAULT_CHAT_FRAME:AddMessage("  Dir: " .. SR_DirStr(s.direction) .. "  Scale: " .. s.scale .. "  Spells: " .. s.maxSpells)
    DEFAULT_CHAT_FRAME:AddMessage("  Push: " .. s.pushSpeed .. "  Base: " .. s.baseSpeed .. "  Cast: " .. s.castSpeed)
    DEFAULT_CHAT_FRAME:AddMessage("  Damage: " .. SR_DmgStr(s.showDamage) .. "  Heals: " .. SR_DmgStr(s.showHeals) .. "  Ranks: " .. SR_RankStr(s.showRanks))
    DEFAULT_CHAT_FRAME:AddMessage("  Crop: " .. SR_OnOff(s.cropTex) .. "  Resists: " .. SR_OnOff(s.showResists) .. "  Mana: " .. SR_OnOff(s.showMana) .. "  Pet: " .. SR_OnOff(s.showPet))
    DEFAULT_CHAT_FRAME:AddMessage("  White hits: " .. SR_WhiteStr(s.showWhite))
end

SlashCmdList["SPELLREPLAY"] = function(msg)
    if not S() then SR_InitSettings() end
    if not msg or msg == "" or msg == "help" then
        SR_PrintHelp()
        return
    end

    -- Parse "command arg" from msg using string.find (Lua 5.0 safe)
    local _, _, cmd, cmdArg = string.find(msg, "^(%S+)%s*(.*)")
    if not cmd then
        cmd    = msg
        cmdArg = ""
    end
    cmd = strlower(cmd)

    if cmd == "enable" then
        if S().enabled == 1 then
            S().enabled = 0
            ReplayFrame:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Disabled.")
        else
            S().enabled = 1
            ReplayFrame:Show()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Enabled.")
        end

    elseif cmd == "lock" then
        if S().locked == 1 then S().locked = 0 else S().locked = 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Lock " .. SR_OnOff(S().locked))

    elseif cmd == "bg" then
        if S().showBg == 1 then
            S().showBg = 0
            ReplayBackground:Hide()
        else
            S().showBg = 1
            ReplayBackground:Show()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Background " .. SR_OnOff(S().showBg))

    elseif cmd == "dir" then
        if S().direction == 1 then S().direction = 2 else S().direction = 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Direction: " .. SR_DirStr(S().direction))

    elseif cmd == "scale" then
        local n = tonumber(cmdArg)
        if n and n >= 0.8 and n <= 1.5 then
            S().scale = n
            ReplayFrame:SetScale(n)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Scale: " .. n)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr scale <0.8-1.5>")
        end

    elseif cmd == "push" then
        local n = tonumber(cmdArg)
        if n and n >= 30 and n <= 150 then
            S().pushSpeed = n
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Push speed: " .. n)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr push <30-150>")
        end

    elseif cmd == "base" then
        local n = tonumber(cmdArg)
        if n and n >= 0 and n <= 100 then
            S().baseSpeed = n
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Base speed: " .. n)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr base <0-100>")
        end

    elseif cmd == "cast" then
        local n = tonumber(cmdArg)
        if n and n >= 0 and n <= 100 then
            S().castSpeed = n
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Casting speed: " .. n)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr cast <0-100>")
        end

    elseif cmd == "spells" then
        local n = tonumber(cmdArg)
        if n and n >= 2 and n <= 6 then
            S().maxSpells = n
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Spells: " .. n)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr spells <2-6>")
        end

    elseif cmd == "crop" then
        if S().cropTex == 1 then S().cropTex = 0 else S().cropTex = 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Crop " .. SR_OnOff(S().cropTex))

    elseif cmd == "resists" then
        if S().showResists == 1 then S().showResists = 0 else S().showResists = 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Resists " .. SR_OnOff(S().showResists))

    elseif cmd == "damage" then
        if cmdArg == "off" then S().showDamage = 0
        elseif cmdArg == "all" then S().showDamage = 1
        elseif cmdArg == "crit" then S().showDamage = 2
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr damage <off|all|crit>")
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Damage: " .. SR_DmgStr(S().showDamage))

    elseif cmd == "heals" then
        if cmdArg == "off" then S().showHeals = 0
        elseif cmdArg == "all" then S().showHeals = 1
        elseif cmdArg == "crit" then S().showHeals = 2
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr heals <off|all|crit>")
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Heals: " .. SR_DmgStr(S().showHeals))

    elseif cmd == "mana" then
        if S().showMana == 1 then S().showMana = 0 else S().showMana = 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Mana " .. SR_OnOff(S().showMana))

    elseif cmd == "pet" then
        if S().showPet == 1 then S().showPet = 0 else S().showPet = 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Pet " .. SR_OnOff(S().showPet))

    elseif cmd == "ranks" then
        if cmdArg == "off" then S().showRanks = 0
        elseif cmdArg == "all" then S().showRanks = 1
        elseif cmdArg == "r1" then S().showRanks = 2
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr ranks <off|all|r1>")
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Ranks: " .. SR_RankStr(S().showRanks))

    elseif cmd == "white" then
        if cmdArg == "off" then S().showWhite = 0
        elseif cmdArg == "melee" then S().showWhite = 1
        elseif cmdArg == "ranged" then S().showWhite = 2
        elseif cmdArg == "both" then S().showWhite = 3
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Usage: /sr white <off|melee|ranged|both>")
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r White hits: " .. SR_WhiteStr(S().showWhite))

    elseif cmd == "reset" then
        SpellReplaySaved = nil
        SR_InitSettings()
        ReplayFrame:ClearAllPoints()
        ReplayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        ReplayFrame:SetScale(1)
        ReplayFrame:Show()
        ReplayBackground:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffSpellReplay:|r Reset to defaults.")

    elseif cmd == "status" then
        SR_PrintStatus()

    else
        SR_PrintHelp()
    end
end
