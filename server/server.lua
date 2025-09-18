local Core = exports.vorp_core:GetCore()

CreateThread(function()
    local item = Config.CampFireItem
    exports.vorp_inventory:registerUsableItem(item, function(data)
        exports.vorp_inventory:subItemById(data.source, data.item.id)
        TriggerClientEvent("vorp:campfire", data.source)
    end)
end)

Core.Callback.Register("vorp_crafting:GetJob", function(source, cb)
    local Character = Core.getUser(source).getUsedCharacter
    local job = Character.job
    cb(job)
end)

RegisterNetEvent('vorp:openInv', function()
    local _source = source
    exports.vorp_inventory:openInventory(_source)
end)

RegisterNetEvent('vorp:startcrafting', function(craftable, countz)
    local _source = source
    local Character = Core.getUser(_source).getUsedCharacter

    local Webhook = '' -- Set your webhook URL here
    local function getServerCraftable()
        local crafting = nil
        for _, v in ipairs(Config.Crafting) do
            if v.Text == craftable.Text then
                crafting = v
                break
            end
        end

        return crafting
    end

    local crafting = getServerCraftable()

    if not crafting then
        return
    end

    local playerjob = Character.job
    local job = crafting.Job
    local craft = false

    if job == 0 then
        craft = true
    end

    if job ~= 0 then
        for _, v in pairs(job) do
            if v == playerjob then
                craft = true
            end
        end
    end

    if not craft then
        Core.NotifyObjective(_source, _U('NotJob'), 5000)
        return
    end

    if not crafting then
        return
    end

    local reward = crafting.Reward
    local itemsToRemove = {}
    local requiredItems = {}


    for _, item in ipairs(crafting.Items) do
        requiredItems[item.name] = {
            required = item.count * countz,
            found = 0,
            canUseDecay = item.canUseDecay,
            take = item.take
        }
    end

    local inventory = exports.vorp_inventory:getUserInventoryItems(source)
    if not inventory then return end

    for _, value in pairs(inventory) do
        local reqItem = requiredItems[value.name]
        if reqItem then
            if reqItem.canUseDecay then
                if value.isDegradable then
                    if value.percentage >= reqItem.canUseDecay then
                        reqItem.found = reqItem.found + value.count
                        if reqItem.take == nil or reqItem.take == true then
                            table.insert(itemsToRemove, { data = value, count = math.min(value.count, reqItem.required) })
                        end
                    end
                else
                    reqItem.found = reqItem.found + value.count
                    if reqItem.take == nil or reqItem.take == true then
                        table.insert(itemsToRemove, { data = value, count = math.min(value.count, reqItem.required) })
                    end
                end
            else
                reqItem.found = reqItem.found + value.count
                if reqItem.take == nil or reqItem.take == true then
                    table.insert(itemsToRemove, { data = value, count = math.min(value.count, reqItem.required) })
                end
            end
        end
    end


    local craftcheck = true
    for itemName, data in pairs(requiredItems) do
        if data.found < data.required then
            craftcheck = false
            break
        end
    end

    if not craftcheck then
        return Core.NotifyObjective(_source, _U('NotEnough'), 5000)
    end

    -- Differentiate between items and weapons
    if crafting.Type == "weapon" then
        local ammo = { ["nothing"] = 0 }
        local components = {}

        for index, v in ipairs(reward) do
            local canCarry = exports.vorp_inventory:canCarryWeapons(_source, v.count * countz, nil, v.name)
            if not canCarry then
                return Core.NotifyObjective(_source, _U('WeaponsFull'), 5000)
            end
        end

        if #itemsToRemove > 0 then
            for _, value in ipairs(itemsToRemove) do
                exports.vorp_inventory:subItemById(_source, value.data.id, nil, nil, value.count)
            end
        end

        for _ = 1, countz do
            for _, v in ipairs(reward) do
                for _ = 1, v.count do
                    exports.vorp_inventory:createWeapon(_source, v.name, ammo, components)
                    Core.AddWebhook(GetPlayerName(_source), Webhook, _U('WebhookWeapon') .. ' ' .. v.name)
                end
            end
        end

        TriggerClientEvent("vorp:crafting", _source, crafting.Animation)
    elseif crafting.Type == "item" then
        local addcount = 0
        local cancarry = false

        if not crafting.UseCurrencyMode then
            for _, rwd in ipairs(reward) do
                local counta = rwd.count * countz
                addcount     = addcount + counta
                cancarry     = exports.vorp_inventory:canCarryItem(_source, rwd.name, counta)
            end
        end

        if crafting.UseCurrencyMode or cancarry then
            if #itemsToRemove > 0 then
                for _, value in ipairs(itemsToRemove) do
                    exports.vorp_inventory:subItemById(_source, value.data.id, nil, nil, value.count)
                end
            end

            for _, v in ipairs(crafting.Reward) do
                local countx = v.count * countz
                if crafting.UseCurrencyMode ~= nil and crafting.CurrencyType ~= nil and crafting.UseCurrencyMode then
                    Character.addCurrency(crafting.CurrencyType, countx)
                else
                    exports.vorp_inventory:addItem(_source, v.name, countx)
                    Core.AddWebhook(GetPlayerName(_source), Webhook, _U('WebhookItem') .. ' x' .. countx .. ' ' .. v.name)
                end
            end

            TriggerClientEvent("vorp:crafting", _source, crafting.Animation)
        else
            TriggerClientEvent("vorp:TipRight", _source, _U('TooFull'), 3000)
        end
    end
end)

-- ===== Crafting sanity check (DB + images) =====
local INV_RES_NAME = GetConvar("vorp_inventory_resource", "vorp_inventory")
local INV_RES_PATH = GetResourcePath(INV_RES_NAME) -- absolute path to resource folder (nil if resource not found)
local DB_MODE = "none"

-- Detect DB adapter and expose a unified checker
local function db_item_exists(name)
    if not name or name == "" then return false end
    local sql = "SELECT 1 FROM items WHERE item = ? LIMIT 1"

    -- oxmysql (preferred)
    if exports.oxmysql then
        if exports.oxmysql.scalarSync then
            DB_MODE = "oxmysql:scalarSync"
            local ok, val = pcall(function()
                return exports.oxmysql:scalarSync(sql, { name })
            end)
            if ok then return val ~= nil end
        elseif exports.oxmysql.executeSync then
            DB_MODE = "oxmysql:executeSync"
            local ok, rows = pcall(function()
                return exports.oxmysql:executeSync(sql, { name })
            end)
            if ok then return rows and rows[1] ~= nil end
        end
    end

    -- mysql-async / ghmattimysql Sync
    if MySQL and MySQL.Sync then
        if MySQL.Sync.fetchScalar then
            DB_MODE = "mysql-async:fetchScalar"
            local ok, val = pcall(function()
                return MySQL.Sync.fetchScalar(sql, { name })
            end)
            if ok then return val ~= nil end
        elseif MySQL.Sync.fetchAll then
            DB_MODE = "mysql-async:fetchAll"
            local ok, rows = pcall(function()
                return MySQL.Sync.fetchAll(sql, { name })
            end)
            if ok then return rows and rows[1] ~= nil end
        end
    end

    return false
end

local function file_exists(path)
    if not path then return false end
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local function image_exists(name)
    if not INV_RES_PATH then return nil end-- nil => we cannot check (resource not found), we make no noise
    local p = ("%s/html/img/items/%s.png"):format(INV_RES_PATH, name)
    return file_exists(p)
end

-- Helpers
local function is_weapon_name(s)
    return type(s) == "string" and s:upper():find("^WEAPON_") ~= nil
end

local function trim(s)
    return type(s) == "string" and (s:gsub("^%s+", ""):gsub("%s+$", "")) or s
end

-- main scan
local function scan_crafting_refs()
    Wait(1500) -- wait a bit for other resources to start up

    local missingDB, missingIMG, malformedReward, checkedDB, checkedIMG = {}, {}, {}, {}, {}

    -- one-time diagnostics
    print(("^3[script:vorp_crafting]^7 DB adapter detected: ^5%s^7"):format(DB_MODE))
    if INV_RES_PATH then
        print(("^3[script:vorp_crafting]^7 inventory icons path: ^5%s/html/img/items^7"):format(INV_RES_PATH))
    else
        print("^3[script:vorp_crafting]^7 inventory icons path: ^1NOT FOUND (resource '" .. INV_RES_NAME .. "' missing?)^7")
    end

    for _, recipe in ipairs(Config.Crafting or {}) do
        -- 1) Ingredients
        for __, it in ipairs(recipe.Items or {}) do
            local nm = trim(it.name)
            if nm and nm ~= "" then
                -- DB check (ingredients are always items)
                if not checkedDB[nm] then
                    if not db_item_exists(nm) then
                        missingDB[nm] = true
                    end
                    checkedDB[nm] = true
                end

                -- image check (optional but useful)
                if INV_RES_PATH and not checkedIMG[nm] then
                    local exists = image_exists(nm)
                    if exists == false then
                        -- Warning: item may be in the database, but PNG was forgotten
                        -- To avoid duplication with "missed item", log only if there is one in the database
                        if not missingDB[nm] then
                            missingIMG[nm] = true
                        end
                    end
                    checkedIMG[nm] = true
                end
            else
                -- name is empty or nil
                missingDB["<ingredient:empty>"] = true
            end
        end

        -- 2) Rewards
        for __, r in ipairs(recipe.Reward or {}) do
            local rn = trim(r.name)
            if not rn or rn == "" then
                table.insert(malformedReward, recipe.Text or "unknown_recipe")
            else
                if recipe.Type == "weapon" and is_weapon_name(rn) then
                    -- weapon reward → we don't touch the items and pictures database
                else
                    -- item reward → DB
                    if not checkedDB[rn] then
                        if not db_item_exists(rn) then
                            missingDB[rn] = true
                        end
                        checkedDB[rn] = true
                    end
                    -- item reward → PNG
                    if INV_RES_PATH and not checkedIMG[rn] then
                        local exists = image_exists(rn)
                        if exists == false and not missingDB[rn] then
                            missingIMG[rn] = true
                        end
                        checkedIMG[rn] = true
                    end
                end
            end
        end
    end

    -- Logs
    for nm in pairs(missingDB) do
        print(("^1missed item in DB: ^7%s"):format(nm))
    end
    for nm in pairs(missingIMG) do
        print(("^6item has no PNG: ^7%s"):format(nm))
    end
    for _, rec in ipairs(malformedReward) do
        print(("^1malformed reward (empty name) in recipe: ^7%s"):format(rec))
    end

    local cDB, cIMG = 0, 0
    for _ in pairs(missingDB) do cDB = cDB + 1 end
    for _ in pairs(missingIMG) do cIMG = cIMG + 1 end
    print(("^7scan complete. Missing in DB: ^1%d^7, missing PNG: ^6%d^7."):format(cDB, cIMG))
end

-- run once on start (give DB adapter a fair chance to initialize)
CreateThread(function()
    -- pre-detect DB mode
    db_item_exists("__probe__") -- fills DB_MODE string
    scan_crafting_refs()
end)

-- optional: admin command to rescan without restart (server console only or ACE)
RegisterCommand("craftscan", function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, "command.craftscan") then
        return
    end
    scan_crafting_refs()
end, true)
