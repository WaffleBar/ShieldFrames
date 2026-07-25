local addonName, ns = ...

local GLOW_EDGE_OFFSET = -7
local healPredictionCalculator

ns.defaults = {
    enabled = true,
    overlayOpacity = 40,
    showGlow = true,
    glowOpacity = 60,
    glowColor = { r = 0.45, g = 0.92, b = 1.0 },
}

ShieldFramesDB = ShieldFramesDB or {}

local function GetDB()
    return ShieldFramesDB
end

local function MergeDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            db[key] = db[key] or {}
            MergeDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

function ns.GetDB()
    return GetDB()
end

function ns.MergeDefaults()
    MergeDefaults(GetDB(), ns.defaults)
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeNumber(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    return value
end

local function CanAccessValue(value)
    if value == nil then
        return false
    end
    if not IsSecret(value) then
        return true
    end
    return canaccessvalue and canaccessvalue(value)
end

local function UsesHealPredictionCalculator()
    return CreateUnitHealPredictionCalculator ~= nil and UnitGetDetailedHealPrediction ~= nil
end

local function EnsureHealPredictionCalculator()
    if healPredictionCalculator then
        return healPredictionCalculator
    end
    if not CreateUnitHealPredictionCalculator then
        return nil
    end

    healPredictionCalculator = CreateUnitHealPredictionCalculator()
    if healPredictionCalculator.SetToDefaults then
        healPredictionCalculator:SetToDefaults()
    end
    if healPredictionCalculator.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
        healPredictionCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
    end

    return healPredictionCalculator
end

local function UpdateHealPredictionCalculator(unit)
    local calculator = EnsureHealPredictionCalculator()
    if not calculator or not UnitGetDetailedHealPrediction then
        return nil
    end

    if calculator.Reset then
        calculator:Reset()
    end

    local ok = pcall(UnitGetDetailedHealPrediction, unit, "player", calculator)
    if not ok then
        ok = pcall(UnitGetDetailedHealPrediction, unit, calculator)
    end
    if not ok then
        return nil
    end

    return calculator
end

local function GetCalculatorOvershieldAmount(unit)
    local calculator = UpdateHealPredictionCalculator(unit)
    if not calculator then
        return
    end

    -- GetDamageAbsorbs returns the in-bar clamped amount (often 0 at full HP).
    -- GetTotalDamageAbsorbs is the full barrier value we need for the overlay width.
    local amount
    if calculator.GetTotalDamageAbsorbs then
        amount = calculator:GetTotalDamageAbsorbs()
    elseif calculator.GetDamageAbsorbs then
        amount = calculator:GetDamageAbsorbs()
    end

    return amount, calculator:GetMaximumHealth(), calculator
end

local function FrameShowsOvershieldGlow(frame)
    local glow = frame.overAbsorbGlow
    if not glow or (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
        return false
    end
    return glow:IsShown()
end

local function SetFrameOvershieldActive(frame, active)
    frame.ShieldFramesOvershieldActive = active or nil
end

local function FrameHasOvershield(frame)
    if FrameShowsOvershieldGlow(frame) then
        return true
    end
    if frame.ShieldFramesOvershieldActive then
        return true
    end
    if frame.ShieldFramesOverlayBar and not frame.ShieldFramesOverlayBar:IsForbidden() then
        return frame.ShieldFramesOverlayBar:IsShown()
    end
    return false
end

local function HideBlizzOvershieldGlow(glow)
    if not glow or (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
        return
    end
    -- Keep the glow "shown" for detection; make Blizzard's edge glow invisible instead.
    glow:SetAlpha(0)
end

local function UpdateMidnightOvershield(frame, healthBar, unit)
    local blizzGlow = frame.overAbsorbGlow
    local glowVisible = FrameShowsOvershieldGlow(frame)

    if glowVisible then
        SetFrameOvershieldActive(frame, true)
    elseif not frame.ShieldFramesOvershieldActive then
        HideOvershieldDisplay(frame)
        return
    end

    local overshieldAmount, maxHealth = GetCalculatorOvershieldAmount(unit)
    ApplyOvershieldBar(frame, healthBar, overshieldAmount, maxHealth)

    if FrameHasOvershield(frame) and blizzGlow then
        HideBlizzOvershieldGlow(blizzGlow)
    end

    if frame.ShieldFramesOverlayBar and frame.ShieldFramesOverlayBar:IsShown() then
        SetFrameOvershieldActive(frame, true)
    elseif not glowVisible then
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
    end
end

local function GetUnitHealthValues(frame, unit)
    local healthBar = frame.healthbar or frame.healthBar
    if not healthBar then
        return
    end

    local curHealth = SafeNumber(healthBar:GetValue())
    local _, maxHealth = healthBar:GetMinMaxValues()
    maxHealth = SafeNumber(maxHealth)

    if (not curHealth or not maxHealth) and unit then
        curHealth = SafeNumber(UnitHealth(unit))
        maxHealth = SafeNumber(UnitHealthMax(unit))
    end

    return curHealth, maxHealth, healthBar
end

local function IsEnabled()
    return GetDB().enabled ~= false
end

local function GetOverlaySettings()
    local db = GetDB()
    return {
        overlayAlpha = (db.overlayOpacity or ns.defaults.overlayOpacity) / 100,
        showGlow = db.showGlow ~= false,
        glowAlpha = (db.glowOpacity or ns.defaults.glowOpacity) / 100,
        glowColor = db.glowColor or ns.defaults.glowColor,
    }
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function GetOvershieldAmount(unit, curHealth, maxHealth)
    if not unit or not curHealth or not maxHealth or curHealth <= 0 or maxHealth <= 0 then
        return 0
    end

    local totalAbsorb = UnitGetTotalAbsorbs(unit) or 0
    totalAbsorb = SafeNumber(totalAbsorb) or 0
    if totalAbsorb <= 0 then
        return 0
    end

    local missingHealth = maxHealth - curHealth
    if missingHealth < 0 then
        missingHealth = 0
    end

    local overshield = totalAbsorb - missingHealth
    if overshield <= 0 then
        return 0
    end

    return overshield, totalAbsorb
end

local function EnsureCustomTextures(frame, healthBar)
    if not frame.ShieldFramesOverlay then
        local overlay = healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
        overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        overlay.tileSize = 32
        overlay:Hide()

        local glow = healthBar:CreateTexture(nil, "OVERLAY", nil, 8)
        glow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        glow:SetBlendMode("ADD")
        glow:SetWidth(16)
        glow:Hide()

        frame.ShieldFramesOverlay = overlay
        frame.ShieldFramesGlow = glow
    end

    return frame.ShieldFramesOverlay, frame.ShieldFramesGlow
end

local function HideOvershieldDisplay(frame)
    if frame.ShieldFramesOverlay then
        frame.ShieldFramesOverlay:Hide()
    end
    if frame.ShieldFramesGlow then
        frame.ShieldFramesGlow:Hide()
    end
    if frame.ShieldFramesOverlayBar and not frame.ShieldFramesOverlayBar:IsForbidden() then
        frame.ShieldFramesOverlayBar:Hide()
    end
end

local function EnsureOvershieldBar(frame, healthBar)
    if not frame.ShieldFramesOverlayBar then
        local bar = CreateFrame("StatusBar", nil, healthBar)
        bar:SetFrameLevel(healthBar:GetFrameLevel() + 7)
        bar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Overlay")
        bar:SetReverseFill(true)

        local barTexture = bar:GetStatusBarTexture()
        if barTexture then
            barTexture:SetHorizTile(true)
            barTexture:SetVertTile(true)
        end

        bar:Hide()
        frame.ShieldFramesOverlayBar = bar
    end

    if not frame.ShieldFramesGlow then
        local glow = healthBar:CreateTexture(nil, "OVERLAY", nil, 8)
        glow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        glow:SetBlendMode("ADD")
        glow:SetWidth(16)
        glow:Hide()
        frame.ShieldFramesGlow = glow
    end

    return frame.ShieldFramesOverlayBar, frame.ShieldFramesGlow
end

local function HideCustomTextures(frame)
    HideOvershieldDisplay(frame)
end

local function ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth, tileSize)
    if not overlay or overlay:IsForbidden() or overlayWidth <= 0 then
        return false
    end

    local settings = GetOverlaySettings()
    tileSize = tileSize or overlay.tileSize or 32
    local _, totalHeight = healthBar:GetSize()

    overlay:SetParent(healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetWidth(overlayWidth)
    overlay:SetTexCoord(0, overlayWidth / tileSize, 0, totalHeight / tileSize)
    overlay:SetVertexColor(1, 1, 1, settings.overlayAlpha)
    overlay:Show()

    if glow and not glow:IsForbidden() and settings.showGlow then
        local color = settings.glowColor
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
        glow:Show()
    elseif glow and not glow:IsForbidden() then
        glow:Hide()
    end

    return true
end

local function ApplyOvershieldBar(frame, healthBar, overshieldAmount, maxHealth)
    local bar, glow = EnsureOvershieldBar(frame, healthBar)
    if not bar or bar:IsForbidden() then
        return false
    end

    local settings = GetOverlaySettings()
    bar:ClearAllPoints()
    bar:SetAllPoints(healthBar)
    bar:SetMinMaxValues(0, maxHealth)
    bar:SetValue(overshieldAmount)
    bar:SetAlpha(settings.overlayAlpha)
    bar:Show()

    local fill = bar:GetStatusBarTexture()
    if glow and fill and not glow:IsForbidden() and settings.showGlow then
        local color = settings.glowColor
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", fill, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
        glow:Show()
    elseif glow and not glow:IsForbidden() then
        glow:Hide()
    end

    return true
end

local function UpdateCompactFrameInternal(frame)
    if not IsEnabled() or not frame then
        return
    end

    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return
    end

    if not frame.displayedUnit or not frame.healthBar then
        return
    end

    local healthBar = frame.healthBar
    local blizzGlow = frame.overAbsorbGlow

    if UsesHealPredictionCalculator() then
        UpdateMidnightOvershield(frame, healthBar, frame.displayedUnit)
        return
    end

    local overlay = frame.totalAbsorbOverlay
    local glow = blizzGlow
    local absorbBar = frame.totalAbsorb

    if not overlay or overlay:IsForbidden() then
        return
    end

    local curHealth = SafeNumber(healthBar:GetValue())
    local _, maxHealth = healthBar:GetMinMaxValues()
    maxHealth = SafeNumber(maxHealth)
    if not curHealth or not maxHealth or maxHealth <= 0 then
        return
    end

    local overshield = GetOvershieldAmount(frame.displayedUnit, curHealth, maxHealth)
    if overshield <= 0 then
        if glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return
    end

    local barWidth = SafeNumber(healthBar:GetWidth())
    if not barWidth or barWidth <= 0 then
        return
    end

    local fillWidth = (curHealth / maxHealth) * barWidth
    local overlayWidth = Clamp((overshield / maxHealth) * barWidth, 0, math.min(fillWidth, barWidth))
    if overlayWidth <= 0 then
        return
    end

    if absorbBar and not absorbBar:IsForbidden() and absorbBar:IsShown() then
        overlay:ClearAllPoints()
        overlay:SetParent(healthBar)
        overlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
        overlay:SetWidth(overlayWidth)
        local tileSize = overlay.tileSize or 32
        local _, totalHeight = healthBar:GetSize()
        overlay:SetTexCoord(0, overlayWidth / tileSize, 0, totalHeight / tileSize)
        overlay:SetVertexColor(1, 1, 1, GetOverlaySettings().overlayAlpha)
        overlay:Show()

        if glow and not glow:IsForbidden() and GetOverlaySettings().showGlow then
            local color = GetOverlaySettings().glowColor
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, GetOverlaySettings().glowAlpha)
            glow:Show()
        elseif glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return
    end

    ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth, overlay.tileSize)
end

function ns.UpdateCompactFrame(frame)
    UpdateCompactFrameInternal(frame)
end

local function UpdateUnitFrame(frame)
    if not IsEnabled() or not frame then
        return
    end

    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return
    end

    if not frame.unit then
        return
    end

    local healthBar = frame.healthbar or frame.healthBar
    if not healthBar or healthBar:IsForbidden() then
        return
    end

    if UsesHealPredictionCalculator() then
        UpdateMidnightOvershield(frame, healthBar, frame.unit)
        return
    end

    local curHealth, maxHealth = GetUnitHealthValues(frame, frame.unit)
    if not curHealth or not maxHealth or maxHealth <= 0 then
        return
    end

    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
    totalAbsorb = SafeNumber(totalAbsorb) or 0
    if totalAbsorb <= 0 then
        HideOvershieldDisplay(frame)
        return
    end

    local overshield = GetOvershieldAmount(frame.unit, curHealth, maxHealth)
    if overshield <= 0 then
        HideOvershieldDisplay(frame)
        return
    end

    local barWidth = SafeNumber(healthBar:GetWidth())
    if not barWidth or barWidth <= 0 then
        return
    end

    local fillWidth = (curHealth / maxHealth) * barWidth
    local overlayWidth = Clamp((overshield / maxHealth) * barWidth, 0, math.min(fillWidth, barWidth))
    if overlayWidth <= 0 then
        HideOvershieldDisplay(frame)
        return
    end

    local overlay, glow = EnsureCustomTextures(frame, healthBar)
    ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth, 32)

    if frame.overAbsorbGlow and not frame.overAbsorbGlow:IsForbidden() then
        frame.overAbsorbGlow:Hide()
    end
end

local function ForEachCompactFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    local function TryFrame(frame)
        if frame and type(callback) == "function" then
            callback(frame)
        end
    end

    if CompactPartyFrame and CompactPartyFrame.members then
        for _, memberFrame in pairs(CompactPartyFrame.members) do
            TryFrame(memberFrame)
        end
    end

    if CompactPartyFrame and CompactPartyFrame.flowFrames then
        for _, memberFrame in ipairs(CompactPartyFrame.flowFrames) do
            TryFrame(memberFrame)
        end
    end

    for index = 1, 5 do
        TryFrame(_G["CompactPartyFrameMember" .. index])
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.flowFrames then
        for _, memberFrame in ipairs(CompactRaidFrameContainer.flowFrames) do
            TryFrame(memberFrame)
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.groups then
        for _, group in pairs(CompactRaidFrameContainer.groups) do
            if group and group.flowFrames then
                for _, memberFrame in ipairs(group.flowFrames) do
                    TryFrame(memberFrame)
                end
            end
        end
    end

    for index = 1, 40 do
        TryFrame(_G["CompactRaidFrame" .. index])
    end
end

local function RefreshUnitFrameByUnit(unit)
    if not unit then
        return
    end

    if PlayerFrame and PlayerFrame.unit == unit then
        UpdateUnitFrame(PlayerFrame)
    end
    if TargetFrame and TargetFrame.unit == unit then
        UpdateUnitFrame(TargetFrame)
    end
    if FocusFrame and FocusFrame.unit == unit then
        UpdateUnitFrame(FocusFrame)
    end
    if PetFrame and PetFrame.unit == unit then
        UpdateUnitFrame(PetFrame)
    end

    ForEachCompactFrame(function(memberFrame)
        if memberFrame.displayedUnit == unit then
            UpdateCompactFrameInternal(memberFrame)
        end
    end)
end

function ns.RefreshAllFrames()
    if PlayerFrame then
        UpdateUnitFrame(PlayerFrame)
    end
    if TargetFrame then
        UpdateUnitFrame(TargetFrame)
    end
    if FocusFrame then
        UpdateUnitFrame(FocusFrame)
    end
    if PetFrame then
        UpdateUnitFrame(PetFrame)
    end

    ForEachCompactFrame(function(memberFrame)
        UpdateCompactFrameInternal(memberFrame)
    end)
end

local function ChatPrint(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    else
        print(message)
    end
end

local function PrintDebugInfo()
    local ok, err = pcall(function()
        local unit = "player"

        ChatPrint("|cff00ccffShieldFrames|r v1.0.11 debug")
        ChatPrint("|cff00ccffShieldFrames|r enabled: " .. tostring(IsEnabled()))
        ChatPrint("|cff00ccffShieldFrames|r in combat: " .. tostring(UnitAffectingCombat(unit)))
        ChatPrint("|cff00ccffShieldFrames|r midnight APIs: " .. tostring(UsesHealPredictionCalculator()))

        if UsesHealPredictionCalculator() then
            UpdateHealPredictionCalculator(unit)
            if PlayerFrame then
                UpdateMidnightOvershield(PlayerFrame, PlayerFrame.healthbar, unit)
            end

            local glowShown = PlayerFrame and FrameShowsOvershieldGlow(PlayerFrame)
            ChatPrint("|cff00ccffShieldFrames|r blizz overAbsorbGlow shown: " .. tostring(glowShown))

            local barShown = PlayerFrame
                and PlayerFrame.ShieldFramesOverlayBar
                and PlayerFrame.ShieldFramesOverlayBar:IsShown()
            ChatPrint("|cff00ccffShieldFrames|r custom overlay bar: " .. tostring(barShown))

            if not glowShown and not barShown then
                ChatPrint("|cff00ccffShieldFrames|r no overshield glow. Cast a barrier at full HP to test.")
            end
            return
        end

        local absorb = SafeNumber(UnitGetTotalAbsorbs(unit)) or 0
        local health = SafeNumber(UnitHealth(unit))
        local maxHealth = SafeNumber(UnitHealthMax(unit))
        local overshield = GetOvershieldAmount(unit, health, maxHealth)

        ChatPrint("|cff00ccffShieldFrames|r player absorb: " .. tostring(absorb))
        if health and maxHealth then
            ChatPrint(string.format(
                "|cff00ccffShieldFrames|r overshield: %s  health: %s / %s",
                tostring(overshield or 0),
                tostring(health),
                tostring(maxHealth)
            ))
        else
            ChatPrint("|cff00ccffShieldFrames|r health values unavailable.")
        end
    end)

    if not ok then
        ChatPrint("|cffff0000ShieldFrames debug error:|r " .. tostring(err))
    end
end

local function OpenSettings()
    if Settings and Settings.OpenToCategory and ns.categoryID then
        Settings.OpenToCategory(ns.categoryID)
        return
    end

    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(addonName)
        return
    end

    ChatPrint("|cff00ccffShieldFrames|r settings are not ready yet. Try again after login.")
end

local function ShieldFramesSlashHandler(msg)
    msg = strtrim(msg or "")
    local command = strlower(strsplit(" ", msg, 2) or "")

    if command == "debug" then
        PrintDebugInfo()
        return
    end

    if command == "help" then
        ChatPrint("|cff00ccffShieldFrames|r commands:")
        ChatPrint("  /shieldframes - open settings")
        ChatPrint("  /sfdebug or /shieldframes debug - print debug info to chat")
        return
    end

    if command == "" then
        OpenSettings()
        return
    end

    ChatPrint("|cff00ccffShieldFrames|r unknown command: " .. msg .. " (type /shieldframes help)")
end

SLASH_SHIELDFRAMES1 = "/shieldframes"
SLASH_SHIELDFRAMES2 = "/sf"
SlashCmdList["SHIELDFRAMES"] = ShieldFramesSlashHandler

SLASH_SHIELDFRAMESDEBUG1 = "/sfdebug"
SLASH_SHIELDFRAMESDEBUG2 = "/shieldframesdebug"
SlashCmdList["SHIELDFRAMESDEBUG"] = function()
    PrintDebugInfo()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
        ns.RefreshAllFrames()
        return
    end

    if unit then
        RefreshUnitFrameByUnit(unit)
    else
        ns.RefreshAllFrames()
    end
end)

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    ns.MergeDefaults()

    hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
        UpdateCompactFrameInternal(frame)
    end)

    hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
        UpdateUnitFrame(frame)
    end)

    C_Timer.NewTicker(0.15, function()
        if not IsEnabled() then
            return
        end
        if PlayerFrame and PlayerFrame.unit then
            UpdateUnitFrame(PlayerFrame)
        end
        if TargetFrame and TargetFrame.unit then
            UpdateUnitFrame(TargetFrame)
        end
        if FocusFrame and FocusFrame.unit then
            UpdateUnitFrame(FocusFrame)
        end
        if PetFrame and PetFrame.unit then
            UpdateUnitFrame(PetFrame)
        end
    end)

end)
