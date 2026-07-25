local addonName, ns = ...

local GLOW_EDGE_OFFSET = -7

ns.defaults = {
    enabled = true,
    overlayOpacity = 40,
    showGlow = true,
    glowOpacity = 60,
    glowColor = { r = 0.45, g = 0.92, b = 1.0 },
}

local function GetDB()
    ShieldFramesDB = ShieldFramesDB or {}
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

local function IsUsableFrame(frame)
    return frame
        and not frame:IsForbidden()
        and frame.displayedUnit
        and frame.healthBar
        and not frame.healthBar:IsForbidden()
end

local function GetFrameElements(frame)
    local healthBar = frame.healthBar
    local overlay = frame.totalAbsorbOverlay
    local glow = frame.overAbsorbGlow

    if not overlay or overlay:IsForbidden() then
        return
    end

    return healthBar, overlay, glow
end

local function GetOvershieldAmount(healthBar, unit)
    local curHealth = healthBar:GetValue()
    if not curHealth or curHealth <= 0 then
        return 0
    end

    local _, maxHealth = healthBar:GetMinMaxValues()
    if not maxHealth or maxHealth <= 0 then
        return 0
    end

    local totalAbsorb = UnitGetTotalAbsorbs(unit) or 0
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

    return overshield, curHealth, maxHealth
end

function ns.UpdateFrame(frame)
    if not ns.defaults or not GetDB().enabled then
        return
    end

    if not IsUsableFrame(frame) then
        return
    end

    local healthBar, overlay, glow = GetFrameElements(frame)
    if not healthBar then
        return
    end

    local overshield, curHealth, maxHealth = GetOvershieldAmount(healthBar, frame.displayedUnit)
    if not overshield or overshield <= 0 then
        if glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return
    end

    local db = GetDB()
    local barWidth = healthBar:GetWidth()
    if barWidth <= 0 then
        return
    end

    local fillWidth = (curHealth / maxHealth) * barWidth
    local overshieldWidth = (overshield / maxHealth) * barWidth
    local overlayWidth = overshieldWidth
    if overlayWidth > fillWidth then
        overlayWidth = fillWidth
    end
    if overlayWidth > barWidth then
        overlayWidth = barWidth
    end
    if overlayWidth <= 0 then
        return
    end

    overlay:SetParent(healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetWidth(overlayWidth)

    if overlay.tileSize and overlay.tileSize > 0 then
        local _, totalHeight = healthBar:GetSize()
        overlay:SetTexCoord(0, overlayWidth / overlay.tileSize, 0, totalHeight / overlay.tileSize)
    end

    local overlayAlpha = (db.overlayOpacity or ns.defaults.overlayOpacity) / 100
    overlay:SetVertexColor(1, 1, 1, overlayAlpha)
    overlay:Show()

    if not glow or glow:IsForbidden() then
        return
    end

    if db.showGlow == false then
        glow:Hide()
        return
    end

    local color = db.glowColor or ns.defaults.glowColor
    local glowAlpha = (db.glowOpacity or ns.defaults.glowOpacity) / 100

    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
    glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
    glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, glowAlpha)
    glow:Show()
end

local function ForEachCompactFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    if CompactPartyFrame then
        if CompactPartyFrame.flowFrames then
            for _, frame in ipairs(CompactPartyFrame.flowFrames) do
                callback(frame)
            end
        end

        for index = 1, 5 do
            local frame = _G["CompactPartyFrameMember" .. index]
            if frame then
                callback(frame)
            end
        end
    end

    if CompactRaidFrameContainer then
        if CompactRaidFrameContainer.flowFrames then
            for _, frame in ipairs(CompactRaidFrameContainer.flowFrames) do
                callback(frame)
            end
        end

        for index = 1, 40 do
            local frame = _G["CompactRaidFrame" .. index]
            if frame then
                callback(frame)
            end
        end
    end
end

function ns.RefreshAllFrames()
    if not CompactUnitFrame_UpdateHealPrediction then
        return
    end

    ForEachCompactFrame(function(frame)
        if IsUsableFrame(frame) then
            CompactUnitFrame_UpdateHealPrediction(frame)
        end
    end)
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    MergeDefaults(GetDB(), ns.defaults)

    hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
        ns.UpdateFrame(frame)
    end)

    SLASH_SHIELDFRAMES1 = "/shieldframes"
    SLASH_SHIELDFRAMES2 = "/sf"
    SlashCmdList["SHIELDFRAMES"] = function()
        if Settings and Settings.OpenToCategory and ns.categoryID then
            Settings.OpenToCategory(ns.categoryID)
        end
    end
end)

EventUtil.ContinueOnPlayerLogin(function()
    ns.RefreshAllFrames()
end)
