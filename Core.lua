local addonName, ns = ...

local GLOW_EDGE_OFFSET = -7

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

local function GetUnitFrameOverlay(frame, absorbBar)
    if absorbBar and not absorbBar:IsForbidden() then
        if absorbBar.TiledOverlay and not absorbBar.TiledOverlay:IsForbidden() then
            return absorbBar.TiledOverlay, absorbBar.tiledOverlaySize or absorbBar.tileSize
        end
        if absorbBar.overlay and not absorbBar.overlay:IsForbidden() then
            return absorbBar.overlay, absorbBar.overlay.tileSize or absorbBar.tileSize
        end
    end

    if frame.totalAbsorbBarOverlay and not frame.totalAbsorbBarOverlay:IsForbidden() then
        return frame.totalAbsorbBarOverlay, frame.totalAbsorbBarOverlay.tileSize
    end

    if frame.totalAbsorbOverlay and not frame.totalAbsorbOverlay:IsForbidden() then
        return frame.totalAbsorbOverlay, frame.totalAbsorbOverlay.tileSize
    end
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

local function UpdateCompactFrameInternal(frame)
    if not IsEnabled() or not frame or frame:IsForbidden() or not frame.displayedUnit or not frame.healthBar then
        return
    end

    local healthBar = frame.healthBar
    local overlay = frame.totalAbsorbOverlay
    local glow = frame.overAbsorbGlow
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
    if not IsEnabled() or not frame or frame:IsForbidden() or not frame.unit then
        return
    end

    local curHealth, maxHealth, healthBar = GetUnitHealthValues(frame, frame.unit)
    if not healthBar or healthBar:IsForbidden() or not curHealth or not maxHealth or maxHealth <= 0 then
        return
    end

    local absorbBar = frame.totalAbsorbBar
    local glow = frame.overAbsorbGlow
    if not glow or glow:IsForbidden() then
        return
    end

    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
    totalAbsorb = SafeNumber(totalAbsorb) or 0
    if totalAbsorb <= 0 then
        glow:Hide()
        return
    end

    local overshield, totalAbsorbAmount = GetOvershieldAmount(frame.unit, curHealth, maxHealth)
    if overshield <= 0 then
        glow:Hide()
        return
    end

    local healthBarTexture = healthBar:GetStatusBarTexture()
    local effectiveHealth = curHealth + totalAbsorbAmount
    local overlay, tileSize = GetUnitFrameOverlay(frame, absorbBar)
    local fillMask = absorbBar and absorbBar.FillMask

    if absorbBar and not absorbBar:IsForbidden() and absorbBar.UpdateFillPosition and healthBarTexture and not healthBarTexture:IsForbidden() then
        if effectiveHealth > maxHealth then
            local xOffset = (maxHealth / effectiveHealth) - 1
            absorbBar:UpdateFillPosition(healthBarTexture, totalAbsorbAmount, xOffset)
        end
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

    if overlay then
        ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth, tileSize)
        return
    end

    if fillMask and not fillMask:IsForbidden() and GetOverlaySettings().showGlow then
        local color = GetOverlaySettings().glowColor
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", fillMask, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMLEFT", fillMask, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, GetOverlaySettings().glowAlpha)
        glow:Show()
    end
end

local function ForEachCompactFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    if CompactPartyFrame and CompactPartyFrame.members then
        for _, memberFrame in pairs(CompactPartyFrame.members) do
            callback(memberFrame)
        end
    end

    if CompactPartyFrame and CompactPartyFrame.flowFrames then
        for _, memberFrame in ipairs(CompactPartyFrame.flowFrames) do
            callback(memberFrame)
        end
    end

    for index = 1, 5 do
        local memberFrame = _G["CompactPartyFrameMember" .. index]
        if memberFrame then
            callback(memberFrame)
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.flowFrames then
        for _, memberFrame in ipairs(CompactRaidFrameContainer.flowFrames) do
            callback(memberFrame)
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.groups then
        for _, group in pairs(CompactRaidFrameContainer.groups) do
            if group and group.flowFrames then
                for _, memberFrame in ipairs(group.flowFrames) do
                    callback(memberFrame)
                end
            end
        end
    end

    for index = 1, 40 do
        local memberFrame = _G["CompactRaidFrame" .. index]
        if memberFrame then
            callback(memberFrame)
        end
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

    SLASH_SHIELDFRAMES1 = "/shieldframes"
    SLASH_SHIELDFRAMES2 = "/sf"
    SlashCmdList["SHIELDFRAMES"] = function(msg)
        msg = strtrim(string.lower(msg or ""))
        if msg == "debug" then
            local unit = "player"
            local absorb = UnitGetTotalAbsorbs(unit) or 0
            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local overshield = GetOvershieldAmount(unit, health, maxHealth)
            print("|cff00ccffShieldFrames|r enabled:", tostring(IsEnabled()))
            print("|cff00ccffShieldFrames|r player absorb:", absorb, "overshield:", overshield or 0, "health:", health, "/", maxHealth)
            if PlayerFrame then
                local overlay, tileSize = GetUnitFrameOverlay(PlayerFrame, PlayerFrame.totalAbsorbBar)
                print("|cff00ccffShieldFrames|r overlay found:", tostring(overlay ~= nil), "tileSize:", tostring(tileSize))
                print("|cff00ccffShieldFrames|r absorbBar:", tostring(PlayerFrame.totalAbsorbBar ~= nil), "FillMask:", tostring(PlayerFrame.totalAbsorbBar and PlayerFrame.totalAbsorbBar.FillMask ~= nil))
            end
            ns.RefreshAllFrames()
            return
        end

        if Settings and Settings.OpenToCategory and ns.categoryID then
            Settings.OpenToCategory(ns.categoryID)
        end
    end
end)
