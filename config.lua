local ADDON, xMerchant = ...
local L = xMerchant.L
local LOGW = xMerchant.LOGW

-- @note: config Options codes referenced to addon: nPlates
local Options = CreateFrame("Frame", "xMerchantOptions", InterfaceOptionsFramePanelContainer)

Options.name = "xMerchant" -- GetAddOnMetadata(ADDON, "Title")
Options.version = GetAddOnMetadata(ADDON, "Version")

xMerchant.OptionsFrame = Options

local defaultDB = {
    version = Options.version,
    itemname_fontsize = 15,
    iteminfo_fontsize = 12,
    scroll_limit_enabled = false,
    scroll_limit_amount = 5,
}
local isWideCharLocale = GetLocale()=="zhCN" or GetLocale()=="zhTW"
if isWideCharLocale then
    defaultDB.itemname_fontsize = 16
    defaultDB.iteminfo_fontsize = 13
end
local currentDB

-- called during "ADDON_LOADED"
function xMerchant.initDB()
    if type(xMerchantDB) ~= "table" then
        xMerchantDB = {}
    end

    if type(xMerchantDB.defaultDB) ~= "table" or xMerchantDB.defaultDB.version ~= Options.version then
        xMerchantDB.defaultDB = defaultDB
    end

    if type(xMerchantDB.global) ~= "table" then
        xMerchantDB.global = {}
    end
    currentDB = xMerchantDB.global
    xMerchant.applyOptions()
end

function xMerchant.resetCurrentDB()
    for k,v in pairs(currentDB) do
        if defaultDB[k] ~= nil then
            currentDB[k] = defaultDB[k]
        end
    end
end

local function resetCurrentDB()
    return xMerchant.resetCurrentDB()
end

function xMerchant.applyOptions()
    -- TODO: update current displayed ui
    if xMerchant.merchantFrameButtons then
        for i=1, 10, 1 do
            local button = xMerchant.merchantFrameButtons[i]
            -- button:SetHeight(29.4); -- TODO: impl

            if not button then
                -- DEFAULT_CHAT_FRAME:AddMessage("[xMerchant][Debug] applyOptions  not button at: "..i);
                break
            end

            local fontFileName, fontHeight, flags
            fontFileName, fontHeight, flags = button.itemname:GetFont()
            button.itemname:SetFont(fontFileName, currentDB.itemname_fontsize or defaultDB.itemname_fontsize)

            fontFileName, fontHeight, flags = button.iteminfo:GetFont()
            button.iteminfo:SetFont(fontFileName, currentDB.iteminfo_fontsize or defaultDB.iteminfo_fontsize)
        end
    end

    local frame = xMerchant.merchantFrame
    if frame then
        local scrollframe = frame.scrollframe
        if scrollframe then
            -- ...
        end
    end
end

local function applyOptions()
    return xMerchant.applyOptions()
end

InterfaceOptions_AddCategory(Options)

Options:Hide()
Options:SetScript("OnShow", function()

    local namePrefix = "xMerchantOptions_"

    local LeftSide = CreateFrame("Frame",namePrefix.."LeftSide",Options)
    LeftSide:SetHeight(Options:GetHeight())
    LeftSide:SetWidth(Options:GetWidth()/2)
    LeftSide:SetPoint("TOPLEFT",Options,"TOPLEFT")

    -- local RightSide = CreateFrame("Frame",namePrefix.."RightSide",Options)
    -- RightSide:SetHeight(Options:GetHeight())
    -- RightSide:SetWidth(Options:GetWidth()/2)
    -- RightSide:SetPoint("TOPRIGHT",Options,"TOPRIGHT")

    -- Left Side --

    local MerchantItemOptions = Options:CreateFontString(namePrefix.."MerchantItemOptions", "ARTWORK", "GameFontNormalLarge")
    MerchantItemOptions:SetPoint("TOPLEFT", LeftSide, 24, -16)
    MerchantItemOptions:SetText(L["Merchant Item Options"])

    local name = namePrefix.."ItemNameSize"
    local ItemNameSize = CreateFrame("Slider", name, LeftSide, "OptionsSliderTemplate")
    local slider = ItemNameSize
    slider:SetPoint("TOPLEFT", MerchantItemOptions, "BOTTOMLEFT", 0, -30)
    slider.text = _G[name.."Text"]
    slider.textLow = _G[name.."Low"]
    slider.textHigh = _G[name.."High"]
    slider:SetMinMaxValues(8, 24)
    slider.minValue, slider.maxValue = slider:GetMinMaxValues()
    slider.textLow:SetText(slider.minValue)
    slider.textHigh:SetText(slider.maxValue)
    slider:SetValue(currentDB.itemname_fontsize or defaultDB.itemname_fontsize)
    slider:SetValueStep(1)
    slider.text:SetText(L["Item name font size"]..": "..string.format("%.0f",slider:GetValue()))
    slider:SetScript("OnValueChanged", function(self,event,arg1)
        local slider = self
        slider.text:SetText(L["Item name font size"]..": "..string.format("%.0f",slider:GetValue()))
        currentDB.itemname_fontsize = tonumber(string.format("%.0f",slider:GetValue()))
        applyOptions()
    end)

    local name = namePrefix.."ItemInfoSize"
    local ItemInfoSize = CreateFrame("Slider", name, LeftSide, "OptionsSliderTemplate")
    local slider = ItemInfoSize
    slider:SetPoint("TOPLEFT", ItemNameSize, "BOTTOMLEFT", 0, -30)
    slider.text = _G[name.."Text"]
    slider.textLow = _G[name.."Low"]
    slider.textHigh = _G[name.."High"]
    slider:SetMinMaxValues(8, 20)
    slider.minValue, slider.maxValue = slider:GetMinMaxValues()
    slider.textLow:SetText(slider.minValue)
    slider.textHigh:SetText(slider.maxValue)
    slider:SetValue(currentDB.iteminfo_fontsize or defaultDB.iteminfo_fontsize)
    slider:SetValueStep(1)
    slider.text:SetText(L["Item info font size"]..": "..string.format("%.0f",slider:GetValue()))
    slider:SetScript("OnValueChanged", function(self,event,arg1)
        local slider = self
        slider.text:SetText(L["Item info font size"]..": "..string.format("%.0f",slider:GetValue()))
        currentDB.iteminfo_fontsize = tonumber(string.format("%.0f",slider:GetValue()))
        applyOptions()
    end)

    local name = namePrefix.."CustomScrollAmountEnabled"
    local CustomScrollAmountEnabled = CreateFrame("CheckButton", name, LeftSide, "InterfaceOptionsCheckButtonTemplate")
    local checkButton = CustomScrollAmountEnabled
    checkButton:SetPoint("TOPLEFT", ItemInfoSize, "BOTTOMLEFT", 0, -30)
    local checked = false
    if currentDB.scroll_limit_enabled~=nil then
        checked = currentDB.scroll_limit_enabled
    else
        checked = defaultDB.scroll_limit_enabled
    end
    checkButton:SetChecked(checked and true or false)
    checkButton.Text:SetText(L["Enable Custom Scroll Amount"])
    checkButton:SetScript('OnClick', function(self, button, down)
        local checkButton = self
        local checked = checkButton:GetChecked()
        currentDB.scroll_limit_enabled = checked

        local slider = _G[namePrefix.."CustomScrollAmount"]
        if checked then
            slider:Show()
            slider:Enable()
        else
            slider:Disable()
            slider:Hide()
        end

        applyOptions()
    end)
    -- checkButton:SetWidth(18)
    -- checkButton:SetHeight(18)

    local name = namePrefix.."CustomScrollAmount"
    local CustomScrollAmount = CreateFrame("Slider", name, LeftSide, "OptionsSliderTemplate")
    local slider = CustomScrollAmount
    slider:SetPoint("TOPLEFT", CustomScrollAmountEnabled, "BOTTOMLEFT", 0, -30)
    slider.text = _G[name.."Text"]
    slider.textLow = _G[name.."Low"]
    slider.textHigh = _G[name.."High"]
    local amount_min = 1 -- (math.floor(xMerchant.kItemButtonHeight * 0.2) * 5)
    local amount_max = 5 -- (math.ceil(xMerchant.kItemButtonHeight * 0.2) * 5) * 5
    slider:SetMinMaxValues(amount_min, amount_max)
    slider.minValue, slider.maxValue = slider:GetMinMaxValues()
    slider.textLow:SetText(slider.minValue)
    slider.textHigh:SetText(slider.maxValue)
    slider:SetValue(currentDB.scroll_limit_amount or defaultDB.scroll_limit_amount)
    slider:SetValueStep(1)
    local amount_lines = tonumber(string.format("%.0f",slider:GetValue())) -- math.floor(slider:GetValue() / xMerchant.kItemButtonHeight)
    -- slider.text:SetText(L["Scroll step"]..": "..string.format("%.0f",slider:GetValue()).." ("..string.format("%s lines", amount_lines)..") ")
    slider.text:SetText(L["Scroll step"]..": "..string.format("%s lines", amount_lines))
    slider:SetScript("OnValueChanged", function(self,event,arg1)
        local slider = self
        local amount_lines = tonumber(string.format("%.0f",slider:GetValue())) -- math.floor(slider:GetValue() / xMerchant.kItemButtonHeight)
        -- slider.text:SetText(L["Scroll step"]..": "..string.format("%.0f",slider:GetValue()).." ("..string.format("%s lines", amount_lines)..") ")
        slider.text:SetText(L["Scroll step"]..": "..string.format("%s lines", amount_lines))
        currentDB.scroll_limit_amount = amount_lines
        applyOptions()
    end)

    if slider then
        local checked = CustomScrollAmountEnabled:GetChecked()
        if checked then
            slider:Show()
            slider:Enable()
        else
            slider:Disable()
            slider:Hide()
        end
    end

    -- -- Right Side --

    -- local FrameOptions = Options:CreateFontString(namePrefix.."FrameOptions", "ARTWORK", "GameFontNormalLarge")
    -- FrameOptions:SetPoint("TOPLEFT", RightSide, 16, -16)
    -- FrameOptions:SetText(L["Frame Options"])


    local name = namePrefix.."ResetCurrentDB"
    local resetButton = CreateFrame("Button", name, LeftSide , "UIPanelButtonTemplate")
    resetButton:SetPoint("BOTTOMLEFT", 16, 16)
    resetButton:SetSize(140,25)
    resetButton:SetText(L["Reset Options"])
    resetButton:SetScript("OnClick", function(self, button, down)
        if button == "LeftButton" then
            resetCurrentDB()

            local slider = ItemNameSize
            slider:SetValue(currentDB.itemname_fontsize or defaultDB.itemname_fontsize)
            local slider = ItemInfoSize
            slider:SetValue(currentDB.iteminfo_fontsize or defaultDB.iteminfo_fontsize)
            local checkButton = CustomScrollAmountEnabled
            local checked = false
            if currentDB.scroll_limit_enabled~=nil then
                checked = currentDB.scroll_limit_enabled
            else
                checked = defaultDB.scroll_limit_enabled
            end
            checkButton:SetChecked(checked)
            local slider = CustomScrollAmount
            slider:SetValue(currentDB.scroll_limit_amount or defaultDB.scroll_limit_amount)
            if checked then
                slider:Show()
                slider:Enable()
            else
                slider:Disable()
                slider:Hide()
            end

            xMerchant.applyOptions()
        end
    end)
    resetButton:RegisterForClicks("LeftButtonUp")

    -- Bottom Right --

    local AddonTitle = Options:CreateFontString("$parentTitle", "ARTWORK", "GameFontNormalLarge")
    AddonTitle:SetPoint("BOTTOMRIGHT", -16, 16)
    AddonTitle:SetText(Options.name.." "..Options.version)

    function Options:Refresh()
    end

    Options:Refresh()
    Options:SetScript("OnShow", nil)
end)
