local addonName, ns = ...

ShieldFramesDB = ShieldFramesDB or {}

local function DB()
    return ns.GetDB()
end

local function RefreshFrames()
    if ns.RefreshAllFrames then
        ns.RefreshAllFrames()
    end
end

local function MakeSetting(category, key, name, defaultValue)
    local variable = addonName .. "_" .. key
    local setting = Settings.RegisterAddOnSetting(
        category,
        variable,
        key,
        ShieldFramesDB,
        type(defaultValue),
        name,
        defaultValue
    )
    setting:SetValueChangedCallback(RefreshFrames)
    return setting
end

local function CreateCheckbox(category, key, label, tooltip)
    local setting = MakeSetting(category, key, label, ns.defaults[key])
    return Settings.CreateCheckbox(category, setting, tooltip)
end

local function CreateSlider(category, key, label, min, max, step, tooltip, formatValue)
    local setting = MakeSetting(category, key, label, ns.defaults[key])
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatValue or function(value)
        return string.format("%d%%", value)
    end)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function GetGlowColorComponents()
    local color = DB().glowColor or ns.defaults.glowColor
    return color.r or 1, color.g or 1, color.b or 1
end

local function SetGlowColor(r, g, b)
    DB().glowColor = { r = r, g = g, b = b }
    RefreshFrames()
end

local function GetOverlayColorComponents()
    local color = DB().overlayColor or ns.defaults.overlayColor
    return color.r or 1, color.g or 1, color.b or 1
end

local function SetOverlayColor(r, g, b)
    DB().overlayColor = { r = r, g = g, b = b }
    RefreshFrames()
end

local function OpenRGBColorPicker(getComponents, setColor)
    local r, g, b = getComponents()
    local previousR, previousG, previousB = r, g, b

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function()
                setColor(ColorPickerFrame:GetColorRGB())
            end,
            cancelFunc = function()
                local previousValues = ColorPickerFrame:GetPreviousValues()
                if previousValues and previousValues.r then
                    setColor(previousValues.r, previousValues.g, previousValues.b)
                else
                    setColor(previousR, previousG, previousB)
                end
            end,
        })
        return
    end

    ColorPickerFrame:Hide()
    ColorPickerFrame:SetParent(UIParent)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = previousR, g = previousG, b = previousB }
    ColorPickerFrame.func = function()
        setColor(ColorPickerFrame:GetColorRGB())
    end
    ColorPickerFrame.cancelFunc = function()
        setColor(previousR, previousG, previousB)
    end
    ColorPickerFrame.swatchFunc = function()
        setColor(ColorPickerFrame:GetColorRGB())
    end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
end

local function OpenGlowColorPicker()
    OpenRGBColorPicker(GetGlowColorComponents, SetGlowColor)
end

local function OpenOverlayColorPicker()
    OpenRGBColorPicker(GetOverlayColorComponents, SetOverlayColor)
end

local function OpenGitHub()
    if OpenURL then
        OpenURL("https://github.com/WaffleBar/ShieldFrames")
    end
end

local ADDON_DESCRIPTION = "Enhances Blizzard party, raid, player, and target frames by visualizing overshield absorbs.|n|nInstead of a thin glow on the right edge of the health bar, ShieldFrames draws a semi-transparent overlay that extends leftward in proportion to the actual overshield value.|n|nParty and raid frames also require Interface > Raid Frames > Display Incoming Heals."

local function InitializeSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
    Settings.RegisterAddOnCategory(category)
    ns.categoryID = category:GetID()

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("About"))

    layout:AddInitializer(CreateSettingsButtonInitializer(
        addonName,
        "View on GitHub",
        OpenGitHub,
        ADDON_DESCRIPTION,
        true
    ))

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Overshield Display"))

    CreateCheckbox(
        category,
        "enabled",
        "Enable ShieldFrames",
        "Show overshield absorb as a transparent bar extending left across supported Blizzard health bars. Party and raid frames also require Interface > Raid Frames > Display Incoming Heals."
    )

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Appearance"))

    CreateSlider(
        category,
        "overlayOpacity",
        "Overlay Opacity",
        5,
        100,
        5,
        "Transparency of the overshield fill drawn over the health bar."
    )

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Overlay Color",
        "Choose Color",
        OpenOverlayColorPicker,
        "Tint for the overshield stripe overlay.",
        true
    ))

    CreateCheckbox(
        category,
        "showGlow",
        "Show Edge Glow",
        "Draw a bright edge on the left side of the overshield overlay."
    )

    CreateSlider(
        category,
        "glowOpacity",
        "Glow Opacity",
        5,
        100,
        5,
        "Brightness of the overshield edge glow."
    )

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Glow Color",
        "Choose Color",
        OpenGlowColorPicker,
        "Tint for the overshield edge glow.",
        true
    ))
end

EventUtil.ContinueOnPlayerLogin(function()
    if ns.MergeDefaults then
        ns.MergeDefaults()
    end
    InitializeSettings()
end)
