--[[

    xMerchant
    Copyright (c) 2010-2014, Nils Ruesch
    All rights reserved.

]]

local wow_ver
local wowapi_ver = 100
-- @see: https://wowpedia.fandom.com/wiki/WOW_PROJECT_ID
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
    -- vanilla
    wow_ver = 10
elseif WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
    -- tbc
    wow_ver = 20
elseif WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
    -- wlk
    wow_ver = 30
else
    -- mainline
    wow_ver = 100
end

local addonName, xMerchant = ...;
local L = xMerchant.L;
local buttons = {};
local knowns = {};
local errors = {};
local factions = {};
local currencies = {};
local searching = "";

local RECIPE = GetItemClassInfo(Enum.ItemClass.Recipe); -- new enum 10.0
--[[
@see: https://wowpedia.fandom.com/wiki/ItemType
Enum.ItemClass.Recipe
]]

local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
local GetContainerItemID = GetContainerItemID or C_Container.GetContainerItemID
local GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink or C_Container.GetContainerItemLink

local GetFriendshipReputation = GetFriendshipReputation or C_GossipInfo.GetFriendshipReputation

local REQUIRES_LEVEL = L["Requires Level (%d+)"];
local LEVEL = L["Level %d"];
local REQUIRES_REPUTATION = L["Requires .+ %- (.+)"];
local REQUIRES_REPUTATION_NAME = L["Requires (.+) %- .+"];
local REQUIRES_SKILL = L["Requires (.+) %((%d+)%)"];
local SKILL = L["%1$s (%2$d)"];
local REQUIRES = L["Requires (.+)"];

local tooltip = CreateFrame("GameTooltip", "NuuhMerchantTooltip", UIParent, "GameTooltipTemplate");

-- get DB of config
function xMerchant.getCurrentDB()
    return xMerchantDB and xMerchantDB.global or {}
end
local GetCurrentDB = xMerchant.getCurrentDB

--@do-not-package@
local ENABLE_DEBUG_DONEY = false;
local function DONEY_LOGD(msg)
    if (ENABLE_DEBUG_DONEY) then
        DEFAULT_CHAT_FRAME:AddMessage("[xMer][D] "..msg);
    end
end
--@end-do-not-package@


local XMERCHANT_DEBUG_TAGS = {};
XMERCHANT_DEBUG_TAGS["[GetError]"] = 0;
XMERCHANT_DEBUG_TAGS["[GetKnown]"] = 0;
XMERCHANT_DEBUG_TAGS["[AltCurrency]"] = 0;
XMERCHANT_DEBUG_TAGS["[CurrencyFrames]"] = 0;
XMERCHANT_DEBUG_TAGS["[CurrencyUpdate]"] = 0;
XMERCHANT_DEBUG_TAGS["[FactionsUpdate]"] = 0;
XMERCHANT_DEBUG_TAGS["[Faction]"] = 0;
XMERCHANT_DEBUG_TAGS["[MerchantItemInfo]"] = 0;

local function LOGSTR(vname, v)
    return " "..vname..": "..(v and tostring(v) or "")
end
local function XMERCHANT_LOGD(msg)
    if (ENABLE_DEBUG_DONEY) then
        local pos = strfind(msg, " ");
        local tag = pos and pos > 0 and strsub(msg, 0, pos-1) or "";

        if not tag
        or tag and not XMERCHANT_DEBUG_TAGS[tag]
        or tag and XMERCHANT_DEBUG_TAGS[tag] and XMERCHANT_DEBUG_TAGS[tag] == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("[xMer][D] "..msg);
        end
    end
end
function xMerchant.LOGW(msg)
    DEFAULT_CHAT_FRAME:AddMessage("[xMerchant][Warning] "..msg);
end
local LOGW = xMerchant.LOGW

local kRecipeDetailLine = 5
local function GetError(index, link, isRecipe)
    -- XMERCHANT_LOGD("==== GetError ====  ".."  #"..index.."  link: "..link);
    if ( not link ) then
        return false;
    end

    local id = link:match("item:(%d+)");
    if ( errors[id] ) then
        XMERCHANT_LOGD("[GetError]  "..link.."  @return errors[id]: "..errors[id]);
        return errors[id];
    end

    tooltip:SetOwner(UIParent, "ANCHOR_NONE");
    tooltip:SetHyperlink(link);

    local errormsg = "";
    -- XMERCHANT_LOGD("[GetErrorTooltip]  ".."  #"..index.."  id: "..(id or ""));
    for i=2, tooltip:NumLines() do
        local skipForRecipe = isRecipe and ((i > kRecipeDetailLine) and (i < tooltip:NumLines()-2));
        local text = _G["NuuhMerchantTooltipTextLeft"..i];
        local r, g, b = text:GetTextColor();
        local gettext = text:GetText();
        -- XMERCHANT_LOGD("[GetErrorTooltip]  ".."  #"..index.."  ("..i.."/"..tooltip:NumLines()..")".."  : "..(gettext or "").."  r: "..r.."  g: "..g.."  b: "..b);
        if ( gettext and r >= 0.9 and g <= 0.2 and b <= 0.2 and gettext ~= RETRIEVING_ITEM_INFO ) then
            if ( errormsg ~= "" ) then
                errormsg = errormsg..", ";
            end

            -- XMERCHANT_LOGD("[GetErrorTooltip]  ".."  #"..index.."  gettext: "..(gettext or ""));

            local level = gettext:match(REQUIRES_LEVEL);
            if ( level and not skipForRecipe ) then
                errormsg = errormsg..LEVEL:format(level);
            end

            local reputation = gettext:match(REQUIRES_REPUTATION);
            if ( reputation and not skipForRecipe ) then
                errormsg = errormsg..reputation;
                local factionName = gettext:match(REQUIRES_REPUTATION_NAME);
                if ( factionName ) then
                    local standingLabel = factions[factionName];
                    if ( standingLabel ) then
                        errormsg = errormsg.." ("..standingLabel..") - "..factionName;
                    else
                        errormsg = errormsg.." ("..factionName..")";
                    end
                end
                XMERCHANT_LOGD("  #"..index.."  RequireFaction  ".."  : "..(reputation or "").."  : "..(factionName or ""));
            end

            local skill, slevel = gettext:match(REQUIRES_SKILL);
            if ( skill and slevel ) then
                XMERCHANT_LOGD("  #"..index.."  RequireSkill  ".."  : "..(skill or "").."  : "..(slevel or ""));
                errormsg = errormsg..SKILL:format(skill, slevel);
            end

            local requires = gettext:match(REQUIRES);
            if ( not level and not reputation and not skill and requires and not skipForRecipe ) then
                XMERCHANT_LOGD("[GetError]  ".."  #"..index.."  Line: "..i.."   REQUIRES: "..(requires or ""));
                errormsg = errormsg..requires;
            end

            if ( not level and not reputation and not skill and not requires ) then
                if ( errormsg ~= "" ) then
                    errormsg = gettext..", "..errormsg;
                else
                    errormsg = errormsg..gettext;
                end
            end
        end

        local text = _G["NuuhMerchantTooltipTextRight"..i];
        local r, g, b = text:GetTextColor();
        local gettext = text:GetText();
        if ( gettext and r >= 0.9 and g <= 0.2 and b <= 0.2 and not skipForRecipe ) then
            if ( errormsg ~= "" ) then
                errormsg = errormsg..", ";
            end
            errormsg = errormsg..gettext;
        end

        XMERCHANT_LOGD("[GetError]  ".."  #"..index.."Line: "..i.."   TooltipTextLeft: "..(_G["NuuhMerchantTooltipTextLeft"..i]:GetText() or ""));
        XMERCHANT_LOGD("[GetError]  ".."  #"..index.."Line: "..i.."   TooltipTextRight: "..(_G["NuuhMerchantTooltipTextRight"..i]:GetText() or ""));

        if ( isRecipe and i == kRecipeDetailLine ) then
            XMERCHANT_LOGD("[GetError]  ".."  #"..index.."Line: "..i.."   isRecipe detail line");
        end
    end

    if ( errormsg == "" ) then
        return false;
    end

    errors[id] = errormsg;
    return errormsg;
end

local function GetKnown(index, link)
    XMERCHANT_LOGD("==== GetKnown ====  ".."  #"..index.."  link: "..link);
    if ( not link ) then
        XMERCHANT_LOGD("[GetKnown]  ".."  #"..index.."  not link   @return false");
        return false;
    end

    local id = link:match("item:(%d+)");
    if ( knowns[id] ) then
        XMERCHANT_LOGD("[GetKnown]  ".."  #"..index.."  "..link.."  @return true");
        return true;
    end

    tooltip:SetOwner(UIParent, "ANCHOR_NONE");
    tooltip:SetHyperlink(link);

    for i=1, tooltip:NumLines() do
        local text = _G["NuuhMerchantTooltipTextLeft"..i];
        local gettext = text:GetText();
        -- XMERCHANT_LOGD("[GetKnownTooltip]  ".."  #"..index.."  ("..i.."/"..tooltip:NumLines()..")".."  id: "..(id or "").."  : "..(gettext or ""));
        if ( gettext == ITEM_SPELL_KNOWN ) then
            knowns[id] = true;
            -- XMERCHANT_LOGD("[GetKnownTooltip]  ".."  #"..index.."  ("..i.."/"..tooltip:NumLines()..")".."  knowns".."  id: "..(id or "").."  : "..gettext);
            return true;
        end
    end

    return false;
end

-- DONEY
local function FactionsUpdate()
    wipe(factions);

    for factionIndex = 1, GetNumFactions() do
        -- Patch 5.0.4 Added new return value: factionID
        local name, description, standingId, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = GetFactionInfo(factionIndex);

        if name~=nil and factionID~=nil then
            -- Patch 5.1.0 Added API GetFriendshipReputation
            local friendID, friendRep, friendMaxRep, friendName, friendText, friendTexture, friendTextLevel
            if GetFriendshipReputation~=nil then
                friendID, friendRep, friendMaxRep, friendName, friendText, friendTexture, friendTextLevel = GetFriendshipReputation(factionID)
            end

            local standingLabel
            if isHeader == nil then
                -- thanks to @SSJNinjaMonkey
                if friendID~=nil then
                    standingLabel = friendTextLevel or "unkown"
                else
                    standingLabel = (_G["FACTION_STANDING_LABEL"..tostring(standingId)] or "unkown")
                end
                factions[name] = standingLabel

                if friendID ~= nil then
                    XMERCHANT_LOGD("[FactionsUpdate]  " .. name .. " - " .. earnedValue .. " - " .. bottomValue .. " - " .. topValue .. " - " .. tostring(standingId) .. " " .. standingLabel);
                end
            end
        end
    end
end

local function CurrencyUpdate()
    wipe(currencies);

    -- thanks to @StevieTV for wow 9.0 update
    local limit = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0;
    XMERCHANT_LOGD("[CurrencyUpdate] GetCurrencyListSize  limit: "..limit);

    for i=1, limit do
        -- DONEY 6.0 http://wowpedia.org/API_GetCurrencyListInfo is out-dated, 2014-10-25
        -- local name, isHeader, _, _, _, count, icon, maximum, hasWeeklyLimit, currentWeeklyAmount, _, itemID = GetCurrencyListInfo(i);
        -- DONEY 9.0 thanks to @StevieTV for wow 9.0 update
        -- @see doc: https://wow.gamepedia.com/Patch_9.0.1/API_changes
        local info = C_CurrencyInfo.GetCurrencyListInfo(i);
        local name = info.name;
        local isHeader = info.isHeader;
        local count = info.quantity;
        local icon = info.iconFileID;
        local maximum = info.maxQuantity;
        local hasWeeklyLimit = info.canEarnPerWeek;
        local itemID
        if ( not isHeader and not itemID ) then
            currencies[name] = count;
        end
    end

    XMERCHANT_DEBUG_TAGS["CurrencyUpdate"] = 0;

    for i=INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED, 1 do
        local itemID = GetInventoryItemID("player", i);
        if ( itemID ) then
            currencies[tonumber(itemID)] = 1;
        end
    end

    for bagID=0, NUM_BAG_SLOTS, 1 do
        local numSlots = GetContainerNumSlots(bagID);
        for slotID=1, numSlots, 1 do
            local itemID = GetContainerItemID(bagID, slotID);
            if ( itemID ) then
                local itemInfo, count = select(1, GetContainerItemInfo(bagID, slotID));
                if type(itemInfo) == "table" then
                    count = itemInfo.stackCount;
                end
                count = count or 1
                itemID = tonumber(itemID);
                local currency = currencies[itemID];
                if ( currency ) then
                    currencies[itemID] = currency+count;
                else
                    currencies[itemID] = count;
                end
            end
        end
    end
end

local function AltCurrencyFrame_Update(item, texture, cost, itemID, currencyName, currencyID)
    item.cost = cost
    item.hasCount = nil
    if ( currencyID and currencyID ~= 0) then
        -- https://wowpedia.fandom.com/wiki/API_C_CurrencyInfo.GetCurrencyInfo
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID) or nil
        local hasCount = currencyInfo and currencyInfo.quantity or nil
        item.hasCount = hasCount
        if ( cost > 0 and (not currencyInfo or not hasCount or hasCount < cost) ) then
            item.count:SetTextColor(1, 0, 0);
        else
            item.count:SetTextColor(1, 1, 1);
        end
    elseif ( itemID ~= 0 or currencyName) then
        local hasCount = currencies[itemID] or currencies[currencyName];
        item.hasCount = hasCount
        -- XMERCHANT_LOGD("[AltCurrency]  "
        --     ..LOGSTR("itemID", itemID)
        --     ..LOGSTR("currencyName", currencyName)
        --     ..LOGSTR("hasCount", hasCount)
        -- );
        if ( cost > 0 and (not hasCount or hasCount < cost) ) then
            item.count:SetTextColor(1, 0, 0);
        else
            item.count:SetTextColor(1, 1, 1);
        end
    end

    item.count:SetText(cost);
    item.icon:SetTexture(texture);
    if ( item.pointType == HONOR_POINTS ) then
        item.count:SetPoint("RIGHT", item.icon, "LEFT", 1, 0);
        item.icon:SetTexCoord(0.03125, 0.59375, 0.03125, 0.59375);
    else
        item.count:SetPoint("RIGHT", item.icon, "LEFT", -2, 0);
        item.icon:SetTexCoord(0, 1, 0, 1);
    end
    local iconWidth = 17;
    item.icon:SetWidth(iconWidth);
    item.icon:SetHeight(iconWidth);
    item:SetWidth(item.count:GetWidth() + iconWidth + 4);
    item:SetHeight(item.count:GetHeight() + 4);
end

local function UpdateAltCurrencyV2(button, index, i, link)
    local currency_frames = {};
    local lastFrame;
    local itemCount, honorPoints, arenaPoints = GetMerchantItemCostInfo(index), 0, 0;
    -- XMERCHANT_LOGD("[AltCurrency] CurrencyV2")
    -- XMERCHANT_LOGD("[AltCurrency] Currency"
    --     ..LOGSTR("link", link)
    --     ..LOGSTR("itemCount", itemCount)
    --     ..LOGSTR("honorPoints", honorPoints)
    -- );

    if ( itemCount > 0 ) then
        for j=1, MAX_ITEM_COST, 1 do
            -- https://wowpedia.fandom.com/wiki/API_GetMerchantItemCostItem
            local itemTexture, itemValue, itemLink, currencyName = GetMerchantItemCostItem(index, j);
            local item = button.item[j];
            local itemID = tonumber((itemLink or "item:0"):match("item:(%d+)"));
            local currencyID = tonumber((itemLink or "currency:0"):match("currency:(%d+)"));
            item.index = index;
            item.item = j;
            if( currencyName ) then
                item.pointType = "Beta";
                item.itemLink = itemLink or currencyName;
            else
                item.pointType = nil;
                item.itemLink = itemLink;
            end

            -- if j == 1 then
            --     XMERCHANT_LOGD("[AltCurrency] V2"
            --         ..LOGSTR("index", index)
            --         ..LOGSTR("link", link)
            --         ..LOGSTR("itemLink", itemLink)
            --         ..LOGSTR("j", j)
            --         ..LOGSTR("itemID", itemID)
            --         ..LOGSTR("currencyID", currencyID)
            --     );
            -- end
            AltCurrencyFrame_Update(item, itemTexture, itemValue, itemID, currencyName, currencyID);

            if ( not itemTexture ) then
                item:Hide();
            else
                lastFrame = item;
                lastFrame._dbg_name = "item"..j
                table.insert(currency_frames, item)
                item:Show();
            end
        end
    else
        for j=1, MAX_ITEM_COST, 1 do
            button.item[j]:Hide();
        end
    end

    local arena = button.arena;
    arena:Hide();

    local honor = button.honor;
    honor:Hide();

    button.money._dbg_name = "money"
    table.insert(currency_frames, button.money)

    -- DONEY
    lastFrame = nil
    for i,frame in ipairs(currency_frames) do
        if i == 1 then
            frame:SetPoint("RIGHT", -2, 6);
        else
            if lastFrame then
                frame:SetPoint("RIGHT", lastFrame, "LEFT", -2, 0);
            else
                -- warning, lastFrame nil unexpected
                XMERCHANT_LOGD("[CurrencyFrames]  i: "..i.."  "..frame._dbg_name.."  lastFrame nil unexpected!");
                frame:SetPoint("RIGHT", -2, 0);
            end
        end
        lastFrame = frame
    end
end

xMerchant.kItemButtonHeight = 29.4

local function MerchantUpdate()
    XMERCHANT_LOGD("[xMerchant][Debug] MerchantUpdate");
    local self = NuuhMerchantFrame;
    local numMerchantItems = GetMerchantNumItems();

    --[[
    if (ENABLE_DEBUG_DONEY) then
        local itemClasses = { GetAuctionItemClasses() };
            if #itemClasses > 0 then
            local itemClass;
            for _, itemClass in pairs(itemClasses) do
            DEFAULT_CHAT_FRAME:AddMessage(itemClass);
            end
        end
    end
    ]]--

    FauxScrollFrame_Update(self.scrollframe, numMerchantItems, 10, xMerchant.kItemButtonHeight, nil, nil, nil, nil, nil, nil, 1);
    for i=1, 10, 1 do
        local offset = i+FauxScrollFrame_GetOffset(self.scrollframe);
        local button = buttons[i];
        button.hover = nil;

        if ( offset <= numMerchantItems ) then
            local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(offset);
            local link = GetMerchantItemLink(offset);
            local name_text = name;
            local iteminfo_text = "";
            local r, g, b = 0.5, 0.5, 0.5;
            local _, itemRarity, itemType, itemSubType;
            local iLevel, iLevelText;
            if ( link ) then
                --API name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemID) or GetItemInfo("itemName") or GetItemInfo("itemLink")
                _, _, itemRarity, iLevel, _, itemType, itemSubType = GetItemInfo(link);
                if itemRarity then
                    r, g, b = GetItemQualityColor(itemRarity);
                    button.itemname:SetTextColor(r, g, b);
                end

                if itemSubType then
                    iteminfo_text = itemSubType:gsub("%(OBSOLETE%)", "");
                    if iLevel and iLevel > 1 then
                        iLevelText = tostring(iLevel);
                        iteminfo_text = iteminfo_text.." - "..iLevelText;
                    end
                else
                    iteminfo_text = ""
                end

                local alpha = 0.3;
                if ( searching == "" or searching == SEARCH:lower() or name:lower():match(searching)
                    or ( itemRarity and ( tostring(itemRarity):lower():match(searching) or _G["ITEM_QUALITY"..tostring(itemRarity).."_DESC"]:lower():match(searching) ) )
                    or ( itemType and itemType:lower():match(searching) )
                    or ( itemSubType and itemSubType:lower():match(searching) )
                    ) then
                    alpha = 1;
                elseif ( self.tooltipsearching ) then
                    tooltip:SetOwner(UIParent, "ANCHOR_NONE");
                    tooltip:SetHyperlink(link);
                    for i=1, tooltip:NumLines() do
                        if ( _G["NuuhMerchantTooltipTextLeft"..i]:GetText():lower():match(searching) ) then
                            alpha = 1;
                            break;
                        end
                    end
                end
                button:SetAlpha(alpha);
            else
                -- TODO: feature of currencies player have
                -- if currencies[name] then
                    -- iteminfo_text = "You have: " .. tostring(currencies[name]);
                -- end
            end

            XMERCHANT_LOGD("[MerchantItemInfo]  ".." - #"..(offset).." "..(link or name or "")
                ..LOGSTR("price", price)
                ..LOGSTR("quantity", quantity)
                ..LOGSTR("numAvailable", numAvailable)
                ..LOGSTR("isUsable", isUsable)
                ..LOGSTR("extendedCost", extendedCost));

            local prename_text = (numAvailable >= 0 and "|cffffffff["..numAvailable.."]|r " or "")..(quantity > 1 and "|cffffffff"..quantity.."x|r " or "")
            name_text = prename_text..(name or "|cffff0000"..RETRIEVING_ITEM_INFO)
            -- name_text = prename_text..(name and (name..name) or "|cffff0000"..RETRIEVING_ITEM_INFO)-- debug code
            button.itemname:SetText(name_text);

            -- button.itemlevel:SetText(iLevelText or "");
            button.icon:SetTexture(texture);

            UpdateAltCurrencyV2(button, offset, i, link);
            local moneyColor = 1
            if ( extendedCost ) then
                button.extendedCost = true;
            else
                button.extendedCost = nil;
            end
            if ( price <= 0 ) then
                button.price = nil;
                button.money:SetText("");
            elseif ( price > 0 ) then
                button.price = price;
                button.money:SetText(GetCoinTextureString(price));
                moneyColor = GetMoney() < price and 0 or 1
            end
            button.money:SetTextColor(1, moneyColor, moneyColor);

            if ( numAvailable == 0 ) then
                button.highlight:SetVertexColor(0.5, 0.5, 0.5, 0.5);
                button.highlight:Show();
                button.isShown = 1;
            elseif ( not isUsable ) then
                button.highlight:SetVertexColor(1, 0.2, 0.2, 0.5);
                button.highlight:Show();
                button.isShown = 1;

                local errors = GetError(i, link, itemType and itemType == RECIPE);
                if ( errors ) then
                    iteminfo_text = "|cffd00000"..iteminfo_text.." - "..errors.."|r";
                end
            elseif ( itemType and itemType == RECIPE and not GetKnown(i, link) ) then
                button.highlight:SetVertexColor(0.2, 1, 0.2, 0.8);
                button.highlight:Show();
                button.isShown = 1;
                local errors = GetError(i, link, itemType and itemType == RECIPE);
                if ( errors ) then
                    button.highlight:SetVertexColor(1, 0.8, 0.5, 0.3);
                    iteminfo_text = "|cffd00000"..iteminfo_text.." - "..errors.."|r";
                end
            else
                button.highlight:SetVertexColor(r, g, b, 0.5);
                button.highlight:Hide();
                button.isShown = nil;
                local errors = GetError(i, link, itemType and itemType == RECIPE);
                if ( errors ) then
                    iteminfo_text = "|cffd00000"..iteminfo_text.." - "..errors.."|r";
                end
            end

            if button.itemname:GetNumLines() <= 1 then
                button.iteminfo:SetText(iteminfo_text);
            else
                button.iteminfo:SetText(iteminfo_text);
            end

            button.r = r;
            button.g = g;
            button.b = b;
            button.link = GetMerchantItemLink(offset);
            button.hasItem = true;
            button.texture = texture;
            button:SetID(offset);
            button:Show();
        else
            button.price = nil;
            button.hasItem = nil;
            button:Hide();
        end
        if ( button.hasStackSplit == 1 ) then
            StackSplitFrame:Hide();
        end
    end
end

local function xScrollFrame_OnShow(self)
    XMERCHANT_LOGD("[xMerchant][Debug] xScrollFrame_OnShow");
end
local function xScrollFrame_OnVerticalScroll(self, offset)
    XMERCHANT_LOGD("[xMerchant][Debug] OnVerticalScroll");
    local current_offset_n = FauxScrollFrame_GetOffset(self);
    local offset_n = (offset >= 0 and 1 or -1) * math.floor(math.abs(offset) / xMerchant.kItemButtonHeight + 0.1);
    local changed_n = offset_n - current_offset_n
    if GetCurrentDB().scroll_limit_enabled then
        if changed_n > GetCurrentDB().scroll_limit_amount or changed_n < -GetCurrentDB().scroll_limit_amount then
            changed_n = math.min(changed_n, GetCurrentDB().scroll_limit_amount)
            changed_n = math.max(changed_n, -GetCurrentDB().scroll_limit_amount)
            offset_n = (current_offset_n + changed_n)
            offset = (offset_n > 0.1 and (offset_n - 0.1) or 0) * xMerchant.kItemButtonHeight
        end
    end
    FauxScrollFrame_OnVerticalScroll(self, offset, xMerchant.kItemButtonHeight, MerchantUpdate);
end

local function OnClick(self, button)
    if ( IsModifiedClick() ) then
        MerchantItemButton_OnModifiedClick(self, button);
    else
        MerchantItemButton_OnClick(self, button);
    end
end

local function OnEnter(self)
    if ( self.isShown and not self.hover ) then
        self.oldr, self.oldg, self.oldb, self.olda = self.highlight:GetVertexColor();
        self.highlight:SetVertexColor(self.r, self.g, self.b, self.olda);
        self.hover = 1;
    else
        self.highlight:Show();
    end
    MerchantItemButton_OnEnter(self);
end

local function OnLeave(self)
    if ( self.isShown ) then
        self.highlight:SetVertexColor(self.oldr, self.oldg, self.oldb, self.olda);
        self.hover = nil;
    else
        self.highlight:Hide();
    end
    GameTooltip:Hide();
    ResetCursor();
    MerchantFrame.itemHover = nil;
end

local function SplitStack(button, split)
    if ( button.extendedCost ) then
        MerchantFrame_ConfirmExtendedItemCost(button, split)
    elseif ( split > 0 ) then
        BuyMerchantItem(button:GetID(), split);
    end
end

local function Item_OnClick(self)
    HandleModifiedItemClick(self.itemLink);
end

local function Item_OnEnter(self)
    local parent = self:GetParent();
    if ( parent.isShown and not parent.hover ) then
        parent.oldr, parent.oldg, parent.oldb, parent.olda = parent.highlight:GetVertexColor();
        parent.highlight:SetVertexColor(parent.r, parent.g, parent.b, parent.olda);
        parent.hover = 1;
    else
        parent.highlight:Show();
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    local text;
    local useHyperLink = true
    if ( self.pointType == ARENA_POINTS ) then
        GameTooltip:SetText(ARENA_POINTS, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
        GameTooltip:AddLine(TOOLTIP_ARENA_POINTS, nil, nil, nil, 1);
        GameTooltip:Show();
    elseif ( self.pointType == HONOR_POINTS ) then
        GameTooltip:SetText(HONOR_POINTS, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
        GameTooltip:AddLine(TOOLTIP_HONOR_POINTS, nil, nil, nil, 1);
        GameTooltip:Show();
    elseif ( self.pointType == "Beta" ) then
        if (useHyperLink) then
            GameTooltip:SetHyperlink(self.itemLink);
        else
            text = self.itemLink..(self.cost and "\n\n"..(self.cost or "").." / "..(self.hasCount or "") or "")
            if (not self.cost or self.hasCount and self.hasCount >= self.cost) then
                GameTooltip:SetText(text, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
            else
                GameTooltip:SetText(text, 1, 0, 0);
            end
        end
        GameTooltip:Show();
    else
        GameTooltip:SetHyperlink(self.itemLink);
    end
    if ( IsModifiedClick("DRESSUP") ) then
        ShowInspectCursor();
    else
        ResetCursor();
    end
end

local function Item_OnLeave(self)
    local parent = self:GetParent();
    if ( parent.isShown ) then
        parent.highlight:SetVertexColor(parent.oldr, parent.oldg, parent.oldb, parent.olda);
        parent.hover = nil;
    else
        parent.highlight:Hide();
    end
    GameTooltip:Hide();
    ResetCursor();
end

local function OnEvent(self, event, ...)
    if ( addonName == select(1, ...) ) then
        self:UnregisterEvent("ADDON_LOADED");

        local x = 0;
        if ( IsAddOnLoaded("SellOMatic") ) then
            x = 20;
        elseif ( IsAddOnLoaded("DropTheCheapestThing") ) then
            x = 14;
        end
        if ( x ~= 0 ) then
            self.search:SetWidth(92-x);
            self.search:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 50-x, 9);
        end

        if xMerchant.initDB~=nil then
            xMerchant.initDB()
        end

        return;
    end
end

local frame = CreateFrame("Frame", "NuuhMerchantFrame", MerchantFrame);
local function xMerchant_InitFrame(frame)
    frame:RegisterEvent("ADDON_LOADED");
    frame:SetScript("OnEvent", OnEvent);
    frame:SetWidth(295);
    frame:SetHeight(294);
    frame:SetPoint("TOPLEFT", 10, -65);

    xMerchant.merchantFrame = frame

    -- TODO: test impl slash command
    -- self:RegisterChatCommand("xmerchant", "OnChatCommand")
    -- self:RegisterChatCommand("xmer", "OnChatCommand")
end
xMerchant_InitFrame(frame)

local function OnTextChanged(self)
    searching = self:GetText():trim():lower();
    MerchantUpdate();
end

local function OnShow(self)
    self:SetText(SEARCH);
    searching = "";
end

local function OnEnterPressed(self)
    self:ClearFocus();
end

local function OnEscapePressed(self)
    self:ClearFocus();
    self:SetText(SEARCH);
    searching = "";
end

local function OnEditFocusLost(self)
    self:HighlightText(0, 0);
    if ( strtrim(self:GetText()) == "" ) then
        self:SetText(SEARCH);
        searching = "";
    end
end

local function OnEditFocusGained(self)
    self:HighlightText();
    if ( self:GetText():trim():lower() == SEARCH:lower() ) then
        self:SetText("");
    end
end

-- TODO: Need polish display before enabling the options button feature
-- local optionsButton = CreateFrame("Button", "$parentOptions", frame, "UIPanelButtonTemplate")
-- frame.optionsButton = optionsButton;
-- optionsButton:SetWidth(16)
-- optionsButton:SetHeight(16)
-- optionsButton:SetText("")
-- optionsButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP");
-- optionsButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN");
-- -- optionsButton:SetDisabledTexture("Interface\\Icons\\INV_Gizmo_03");
-- -- optionsButton:SetHighlightTexture("Interface\\Icons\\INV_Gizmo_03");
-- optionsButton:ClearAllPoints()
-- optionsButton:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 28, 13)
-- optionsButton:SetScript("OnClick", function( ... )
-- 	InterfaceOptionsFrame_OpenToCategory("xMerchant")
-- 	InterfaceOptionsFrame_OpenToCategory(xMerchant.OptionsFrame)
-- 	InterfaceOptionsFrame_OpenToCategory("xMerchant")
-- 	InterfaceOptionsFrame_OpenToCategory(xMerchant.OptionsFrame)
-- end)

local search = CreateFrame("EditBox", "$parentSearch", frame, "InputBoxTemplate");
frame.search = search;
search:SetWidth(92);
search:SetHeight(26);
search:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 50, 10);
search:SetAutoFocus(false);
search:SetFontObject("ChatFontNormal");
search:SetScript("OnTextChanged", OnTextChanged);
search:SetScript("OnShow", OnShow);
search:SetScript("OnEnterPressed", OnEnterPressed);
search:SetScript("OnEscapePressed", OnEscapePressed);
search:SetScript("OnEditFocusLost", OnEditFocusLost);
search:SetScript("OnEditFocusGained", OnEditFocusGained);
search:SetText(SEARCH);

local function PlayCheckBoxSound(on)
    if wow_ver < 73 and wowapi_ver < 100 then
        PlaySound(on and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    else
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

local function Search_OnClick(self)
    if ( self:GetChecked() ) then
        PlayCheckBoxSound(true);
        frame.tooltipsearching = 1;
    else
        PlayCheckBoxSound(false);
        frame.tooltipsearching = nil;
    end
    if ( searching ~= "" and searching ~= SEARCH:lower() ) then
        XMERCHANT_LOGD("[xMerchant][Debug] Search_OnClick");
        MerchantUpdate();
    end
end

local function Search_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["To browse item tooltips, too"]);
end

local tooltipsearching = CreateFrame("CheckButton", "$parentTooltipSearching", frame, "InterfaceOptionsCheckButtonTemplate");
search.tooltipsearching = tooltipsearching;
tooltipsearching:SetWidth(24);
tooltipsearching:SetHeight(24);
tooltipsearching:SetPoint("LEFT", search, "RIGHT", -3, -2);
tooltipsearching:SetHitRectInsets(0, 0, 0, 0);
tooltipsearching:SetScript("OnClick", Search_OnClick);
tooltipsearching:SetScript("OnEnter", Search_OnEnter);
tooltipsearching:SetScript("OnLeave", GameTooltip_Hide);
tooltipsearching:SetChecked(false);

local scrollframe = CreateFrame("ScrollFrame", "NuuhMerchantScrollFrame", frame, "FauxScrollFrameTemplate");
frame.scrollframe = scrollframe;
scrollframe:SetWidth(284);
scrollframe:SetHeight(298);
scrollframe:SetPoint("TOPLEFT", MerchantFrame, 22, -65);
scrollframe:SetScript("OnShow", xScrollFrame_OnShow);
scrollframe:SetScript("OnVerticalScroll", xScrollFrame_OnVerticalScroll);

local top = frame:CreateTexture("$parentTop", "ARTWORK");
frame.top = top
top:SetWidth(31);
top:SetHeight(256);
top:SetPoint("TOPRIGHT", 30, 6);
top:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar");
top:SetTexCoord(0, 0.484375, 0, 1);

local bottom = frame:CreateTexture("$parentBottom", "ARTWORK");
frame.bottom = bottom
bottom:SetWidth(31);
bottom:SetHeight(108);
bottom:SetPoint("BOTTOMRIGHT", 30, -6);
bottom:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar");
bottom:SetTexCoord(0.515625, 1, 0, 0.421875);

xMerchant.merchantFrameButtons = {}
local function xMerchant_InitItemsButtons()
    for i=1, 10, 1 do
        local button = CreateFrame("Button", "NuuhMerchantFrame"..i, frame);
        button:SetWidth(frame:GetWidth());
        button:SetHeight(xMerchant.kItemButtonHeight);
        if ( i == 1 ) then
            button:SetPoint("TOPLEFT", 0, -1);
        else
            button:SetPoint("TOP", buttons[i-1], "BOTTOM");
        end
        button:RegisterForClicks("LeftButtonUp","RightButtonUp");
        button:RegisterForDrag("LeftButton");
        button.UpdateTooltip = OnEnter;
        button.SplitStack = SplitStack;
        button:SetScript("OnClick", OnClick);
        button:SetScript("OnDragStart", MerchantItemButton_OnClick);
        button:SetScript("OnEnter", OnEnter);
        button:SetScript("OnLeave", OnLeave);
        button:SetScript("OnHide", OnHide);

        local highlight = button:CreateTexture("$parentHighlight", "BACKGROUND"); -- better highlight
        button.highlight = highlight;
        highlight:SetAllPoints();
        highlight:SetBlendMode("ADD");
        highlight:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2");
        highlight:Hide();

        local itemname_fontsize = GetCurrentDB().itemname_fontsize or 15
        local iteminfo_fontsize = GetCurrentDB().iteminfo_fontsize or 12

        local itemname = button:CreateFontString("$parentItemName", "ARTWORK");
        button.itemname = itemname;
        itemname:SetFont(GameFontHighlight:GetFont(), itemname_fontsize)
        itemname:SetPoint("TOPLEFT", 30.4, -1);
        itemname:SetJustifyH("LEFT");
        itemname:SetJustifyV("TOP");
        itemname:SetWordWrap(false)

        local iteminfo = button:CreateFontString("$parentItemInfo", "ARTWORK");
        button.iteminfo = iteminfo;
        iteminfo:SetFont(GameFontNormal:GetFont(), iteminfo_fontsize)
        iteminfo:SetPoint("TOPLEFT", itemname, "BOTTOMLEFT", 10, 0);
        iteminfo:SetJustifyH("LEFT");
        iteminfo:SetJustifyV("TOP");
        iteminfo:SetTextColor(0.5, 0.5, 0.5);
        iteminfo:SetWordWrap(false)

        local icon = button:CreateTexture("$parentIcon", "BORDER");
        button.icon = icon;
        icon:SetWidth(25.4);
        icon:SetHeight(25.4);
        icon:SetPoint("LEFT", 2, 0);
        icon:SetTexture("Interface\\Icons\\temp");

        -- DONEY todo?
        -- local itemlevel = button:CreateFontString("$parentItemName", "ARTWORK", "GameFontNormal");
        -- button.itemlevel = itemlevel;
        -- itemlevel:SetPoint("BOTTOMLEFT", 1.0, -3);
        -- itemlevel:SetJustifyH("LEFT");

        local money = button:CreateFontString("$parentMoney", "ARTWORK");
        button.money = money;
        money:SetFontObject(GameFontHighlight)
        money:SetPoint("RIGHT", -2, 0);
        money:SetJustifyH("RIGHT");
        itemname:SetPoint("RIGHT", money, "LEFT", -2, 0);
        iteminfo:SetPoint("RIGHT", money, "RIGHT", -2, 0);

        button.item = {};
        for j=1, MAX_ITEM_COST, 1 do
            local item = CreateFrame("Button", "$parentItem"..j, button);
            button.item[j] = item;
            item:SetWidth(17);
            item:SetHeight(17);
            if ( j == 1 ) then
                item:SetPoint("RIGHT", -2, 0);
            else
                item:SetPoint("RIGHT", button.item[j-1], "LEFT", -2, 0);
            end
            item:RegisterForClicks("LeftButtonUp","RightButtonUp");
            item:SetScript("OnClick", Item_OnClick);
            item:SetScript("OnEnter", Item_OnEnter);
            item:SetScript("OnLeave", Item_OnLeave);
            item.hasItem = true;
            item.UpdateTooltip = Item_OnEnter;

            local icon = item:CreateTexture("$parentIcon", "BORDER");
            item.icon = icon;
            icon:SetWidth(17);
            icon:SetHeight(17);
            icon:SetPoint("RIGHT");

            local count = item:CreateFontString("$parentCount", "ARTWORK", "GameFontHighlight");
            item.count = count;
            count:SetPoint("RIGHT", icon, "LEFT", -2, 0);
        end

        local honor = CreateFrame("Button", "$parentHonor", button);
        button.honor = honor;
        honor.itemLink = select(2, GetItemInfo(43308)) or "\124cffffffff\124Hitem:43308:0:0:0:0:0:0:0:0\124h[Ehrenpunkte]\124h\124r";
        honor:SetWidth(17);
        honor:SetHeight(17);
        honor:SetPoint("RIGHT", -2, 0);
        honor:RegisterForClicks("LeftButtonUp","RightButtonUp");
        honor:SetScript("OnClick", Item_OnClick);
        honor:SetScript("OnEnter", Item_OnEnter);
        honor:SetScript("OnLeave", Item_OnLeave);
        honor.hasItem = true;
        honor.UpdateTooltip = Item_OnEnter;

        local icon = honor:CreateTexture("$parentIcon", "BORDER");
        honor.icon = icon;
        icon:SetWidth(17);
        icon:SetHeight(17);
        icon:SetPoint("RIGHT");

        local count = honor:CreateFontString("$parentCount", "ARTWORK", "GameFontHighlight");
        honor.count = count;
        count:SetPoint("RIGHT", icon, "LEFT", -2, 0);

        local arena = CreateFrame("Button", "$parentArena", button);
        button.arena = arena;
        arena.itemLink = select(2, GetItemInfo(43307)) or "\124cffffffff\124Hitem:43307:0:0:0:0:0:0:0:0\124h[Arenapunkte]\124h\124r";
        arena:SetWidth(17);
        arena:SetHeight(17);
        arena:SetPoint("RIGHT", -2, 0);
        arena:RegisterForClicks("LeftButtonUp","RightButtonUp");
        arena:SetScript("OnClick", Item_OnClick);
        arena:SetScript("OnEnter", Item_OnEnter);
        arena:SetScript("OnLeave", Item_OnLeave);
        arena.hasItem = true;
        arena.UpdateTooltip = Item_OnEnter;

        local icon = arena:CreateTexture("$parentIcon", "BORDER");
        arena.icon = icon;
        icon:SetWidth(17);
        icon:SetHeight(17);
        icon:SetPoint("RIGHT");

        local count = arena:CreateFontString("$parentCount", "ARTWORK", "GameFontHighlight");
        arena.count = count;
        count:SetPoint("RIGHT", icon, "LEFT", -2, 0);

        xMerchant.merchantFrameButtons[i] = button
        buttons[i] = button;
    end
end
xMerchant_InitItemsButtons()

local function Update()
    if ( MerchantFrame.selectedTab == 1 ) then
        for i=1, 12, 1 do
            _G["MerchantItem"..i]:Hide();
        end
        frame:Show();
        XMERCHANT_LOGD("[xMerchant][Debug] Update:  CurrencyUpdate");
        CurrencyUpdate();
        FactionsUpdate();
        XMERCHANT_LOGD("[xMerchant][Debug] Update:  MerchantUpdate");
        MerchantUpdate();
    else
        frame:Hide();
        for i=1, 12, 1 do
            _G["MerchantItem"..i]:Show();
        end
        if ( StackSplitFrame:IsShown() ) then
            StackSplitFrame:Hide();
        end
    end
end
hooksecurefunc("MerchantFrame_Update", Update);

local function OnHide()
    wipe(errors);
    wipe(currencies);
end
hooksecurefunc("MerchantFrame_OnHide", OnHide);


MerchantBuyBackItem:ClearAllPoints();
MerchantBuyBackItem:SetPoint("BOTTOMLEFT", 175, 32);

for _, frame in next, { MerchantNextPageButton, MerchantPrevPageButton, MerchantPageText } do
    frame:Hide()
    frame.Show = function() end;
end
