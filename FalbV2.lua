local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--//==================================================
--// GAME MODULES
--//==================================================

local UnitConfig = require(
    ReplicatedStorage.Framework.Features.Inventory.Kinds.Unit.UnitConfig
)

local FusingUtil = require(
    ReplicatedStorage.Framework.Features.Fusing.FusingUtil
)

local FuseRemote =
    ReplicatedStorage.Network.FusingService.RE.Fuse

local ResultRemote =
    ReplicatedStorage
        :WaitForChild("Network")
        :WaitForChild("FusingService")
        :WaitForChild("RE")
        :WaitForChild("Result")

local Entries = UnitConfig.entries

--//==================================================
--// SETTINGS
--//==================================================

local Settings = {
    Enabled = false,

    -- Minimum allowed interval between fusion requests.
    Delay = 0.5,

    From = 0,
    Below = math.huge,

    Order = "Rarest First",

    RemoveFusionAnimation = false,
}

--//==================================================
--// STATS
--//==================================================

local Stats = {
    Done = 0,
    Scans = 0,
    Failed = 0,
}

--//==================================================
--// FUSION STATE
--//==================================================

local FusionBusy = false
local PendingFusion = nil

--//==================================================
--// ANIMATION REMOVER
--//==================================================

local DisabledConnections = {}
local IsAnimationRemoved = false

local function getControllerConnection()

    if not getconnections then

        warn(
            "[Animation Remover] getconnections is not supported."
        )

        return nil
    end

    for _, connection in ipairs(
        getconnections(ResultRemote.OnClientEvent)
    ) do

        local fn = connection.Function

        if fn then

            local info = debug.getinfo(fn)

            if info and info.source then

                if tostring(info.source):find(
                    "FusingController",
                    1,
                    true
                ) then

                    return connection
                end
            end
        end
    end

    return nil
end

local function removeFusionAnimation()

    if IsAnimationRemoved then
        return true
    end

    local connection =
        getControllerConnection()

    if not connection then

        warn(
            "[Animation Remover] FusingController connection NOT FOUND"
        )

        return false
    end

    DisabledConnections[1] = connection

    local success, err =
        pcall(function()
            connection:Disable()
        end)

    if not success then

        table.clear(DisabledConnections)

        warn(
            "[Animation Remover] Disable failed:",
            err
        )

        return false
    end

    IsAnimationRemoved = true

    warn(
        "[Animation Remover] FusingController disabled."
    )

    return true
end

local function restoreFusionAnimation()

    if not IsAnimationRemoved then
        return
    end

    for _, connection in ipairs(
        DisabledConnections
    ) do

        pcall(function()
            connection:Enable()
        end)
    end

    table.clear(DisabledConnections)

    IsAnimationRemoved = false

    warn(
        "[Animation Remover] FusingController restored."
    )
end

--//==================================================
--// NUMBER SUFFIXES
--//==================================================

local suffixes = {
    {1e30, "no"},
    {1e27, "oc"},
    {1e24, "sp"},
    {1e21, "sx"},
    {1e18, "qi"},
    {1e15, "qd"},
    {1e12, "t"},
    {1e9, "b"},
    {1e6, "m"},
    {1e3, "k"},
}

local multipliers = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
    t = 1e12,
    qd = 1e15,
    qi = 1e18,
    sx = 1e21,
    sp = 1e24,
    oc = 1e27,
    no = 1e30,
}

--//==================================================
--// PARSE NUMBER
--//==================================================

local function parseNumber(value)

    if type(value) ~= "string" then
        return nil
    end

    value = value:lower()
    value = value:gsub(",", "")
    value = value:gsub("%s+", "")

    local number, suffix =
        value:match("^([%d%.]+)([a-z]+)$")

    if number and suffix then

        number = tonumber(number)

        local multiplier =
            multipliers[suffix]

        if number and multiplier then
            return number * multiplier
        end
    end

    return tonumber(value)
end

--//==================================================
--// FORMAT NUMBER
--//==================================================

local function formatNumber(value)

    if value == math.huge then
        return "∞"
    end

    for _, item in ipairs(suffixes) do

        local divisor = item[1]
        local suffix = item[2]

        if value >= divisor then

            local n = value / divisor

            if math.abs(
                n - math.floor(n)
            ) < 0.000001 then

                return tostring(
                    math.floor(n)
                ) .. suffix
            end

            local formatted =
                string.format("%.3f", n)

            formatted =
                formatted
                :gsub("0+$", "")
                :gsub("%.$", "")

            return formatted .. suffix
        end
    end

    return tostring(value)
end

--//==================================================
--// GUID
--//==================================================

local function isGUID(value)

    return type(value) == "string"
        and value:match(
            "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
        ) ~= nil
end

--//==================================================
--// FIND INVENTORY
--//==================================================

local function getInventory()

    local best = nil
    local bestSize = 0

    for _, value in pairs(
        getgc(true)
    ) do

        if type(value) == "table" then

            local ok, inventory =
                pcall(
                    rawget,
                    value,
                    "Inventory"
                )

            if ok
                and type(inventory) == "table"
            then

                local size = 0

                for guid, data in pairs(
                    inventory
                ) do

                    if isGUID(guid)
                        and type(data) == "table"
                        and rawget(data, "name")
                    then

                        size += 1
                    end
                end

                if size > bestSize then
                    bestSize = size
                    best = inventory
                end
            end
        end
    end

    return best, bestSize
end

--//==================================================
--// GET CHANCE
--//==================================================

local function getChance(data)

    local ok, result =
        pcall(
            FusingUtil.GetChance,
            data
        )

    if ok and type(result) == "number" then
        return result
    end

    return nil
end

--//==================================================
--// SCAN INVENTORY
--//==================================================

local function scan()

    local inventory, inventorySize =
        getInventory()

    if not inventory then
        return nil
    end

    local groups = {}

    for guid, data in pairs(inventory) do

        if isGUID(guid)
            and type(data) == "table"
        then

            local name =
                rawget(data, "name")

            if name and Entries[name] then

                local chance =
                    getChance(data)

                if chance then

                    local groupKey =
                        formatNumber(chance)

                    groups[groupKey] =
                        groups[groupKey] or {}

                    table.insert(
                        groups[groupKey],
                        {
                            guid = guid,
                            name = name,
                            chance = chance,
                        }
                    )
                end
            end
        end
    end

    Stats.Scans += 1

    return {
        inventorySize = inventorySize,
        groups = groups,
        inventory = inventory,
    }
end

--//==================================================
--// FIND CANDIDATES
--//==================================================

local function getCandidates(scanData)

    local candidates = {}

    for groupKey, units in pairs(
        scanData.groups
    ) do

        if #units >= 3 then

            local chance =
                units[1].chance

            if chance >= Settings.From
                and chance < Settings.Below
            then

                table.insert(
                    candidates,
                    {
                        key = groupKey,
                        chance = chance,
                        units = units,
                        count = #units,
                    }
                )
            end
        end
    end

    if Settings.Order == "Rarest First" then

        table.sort(
            candidates,
            function(a, b)

                if a.chance ~= b.chance then
                    return a.chance > b.chance
                end

                return a.count > b.count
            end
        )

    elseif Settings.Order == "Most Copies First" then

        table.sort(
            candidates,
            function(a, b)

                if a.count ~= b.count then
                    return a.count > b.count
                end

                return a.chance > b.chance
            end
        )

    elseif Settings.Order == "Lowest Value First" then

        table.sort(
            candidates,
            function(a, b)
                return a.chance < b.chance
            end
        )
    end

    return candidates
end

--//==================================================
--// WINDOW
--//==================================================

local Window =
    Rayfield:CreateWindow({

    Name = "Anime Dice | Auto Fuse",

    LoadingTitle = "Auto Fuse",

    LoadingSubtitle =
        "Fast Fusion + Accurate Counter",

    ConfigurationSaving = {
        Enabled = false,
    },

    Discord = {
        Enabled = false,
    },

    KeySystem = false,
})

local Tab =
    Window:CreateTab(
        "Fusing",
        nil
    )

--//==================================================
--// STATUS
--//==================================================

local StatusLabel =
    Tab:CreateLabel(
        "Fuse: Idle"
    )

local TargetLabel =
    Tab:CreateLabel(
        "Target: None"
    )

local InventoryLabel =
    Tab:CreateLabel(
        "Inventory: 0"
    )

local DoneLabel =
    Tab:CreateLabel(
        "Done: 0"
    )

local ScanLabel =
    Tab:CreateLabel(
        "Scans: 0"
    )

local FailedLabel =
    Tab:CreateLabel(
        "Failed: 0"
    )

--//==================================================
--// ANIMATION
--//==================================================

Tab:CreateSection(
    "Fusion Animation"
)

Tab:CreateToggle({

    Name = "Remove Fusion Animation",

    CurrentValue = false,

    Flag = "RemoveFusionAnimation",

    Callback = function(value)

        Settings.RemoveFusionAnimation =
            value

        if value then

            local success =
                removeFusionAnimation()

            if success then

                Rayfield:Notify({
                    Title = "Animation Remover",
                    Content = "Fusion animation removed.",
                    Duration = 3
                })

            end

        else

            restoreFusionAnimation()

            Rayfield:Notify({
                Title = "Animation Remover",
                Content = "Fusion animation restored.",
                Duration = 3
            })
        end
    end,
})

--//==================================================
--// FROM
--//==================================================

Tab:CreateInput({

    Name = "Fuse from 1 in",

    PlaceholderText = "650qd",

    RemoveTextAfterFocusLost = false,

    CurrentValue = "",

    Callback = function(value)

        if value == "" then

            Settings.From = 0

            return
        end

        local parsed =
            parseNumber(value)

        if parsed then
            Settings.From = parsed
        end
    end,
})

--//==================================================
--// BELOW
--//==================================================

Tab:CreateInput({

    Name = "Fuse below 1 in",

    PlaceholderText = "1sx",

    RemoveTextAfterFocusLost = false,

    CurrentValue = "",

    Callback = function(value)

        if value == "" then

            Settings.Below =
                math.huge

            return
        end

        local parsed =
            parseNumber(value)

        if parsed then
            Settings.Below = parsed
        end
    end,
})

--//==================================================
--// ORDER
--//==================================================

Tab:CreateDropdown({

    Name = "Order",

    Options = {
        "Rarest First",
        "Most Copies First",
        "Lowest Value First",
    },

    CurrentOption = {
        "Rarest First"
    },

    Callback = function(option)

        if type(option) == "table" then
            option = option[1]
        end

        Settings.Order = option
    end,
})

--//==================================================
--// CHECK FUSION COMPLETION
--//==================================================

local function fusionUnitsConsumed(pending)

    if not pending then
        return false
    end

    local inventory =
        getInventory()

    if not inventory then
        return false
    end

    return inventory[pending.a.guid] == nil
        and inventory[pending.b.guid] == nil
        and inventory[pending.c.guid] == nil
end

--//==================================================
--// WAIT FOR REAL FUSION
--//==================================================

local function waitForFusionConfirmation(
    pending
)

    local timeout = 3
    local start = os.clock()

    while os.clock() - start < timeout do

        if fusionUnitsConsumed(
            pending
        ) then

            return true
        end

        task.wait(0.1)
    end

    return false
end

--//==================================================
--// FUSE THREE UNITS
--//==================================================

local function fuseSelected(
    selected
)

    if not selected then
        return false
    end

    if FusionBusy then
        return false
    end

    local a =
        selected.units[1]

    local b =
        selected.units[2]

    local c =
        selected.units[3]

    if not a
        or not b
        or not c
    then

        return false
    end

    FusionBusy = true

    local unitNames =
        tostring(a.name)
        .. " + "
        .. tostring(b.name)
        .. " + "
        .. tostring(c.name)

    local chanceText =
        formatNumber(
            selected.chance
        )

    StatusLabel:Set(
        "Fusing: "
        .. unitNames
    )

    TargetLabel:Set(
        "1 in "
        .. chanceText
        .. " | "
        .. unitNames
    )

    PendingFusion = {
        a = a,
        b = b,
        c = c,
        started = os.clock(),
    }

    local success, err =
        pcall(function()

            FuseRemote:FireServer(
                a.guid,
                b.guid,
                c.guid
            )
        end)

    if not success then

        PendingFusion = nil
        FusionBusy = false

        Stats.Failed += 1

        FailedLabel:Set(
            "Failed: "
            .. Stats.Failed
        )

        StatusLabel:Set(
            "Fuse Error"
        )

        warn(
            "[Auto Fuse] Remote error:",
            err
        )

        return false
    end

    -- IMPORTANT:
    -- FireServer only means the request was sent.
    -- We do NOT increment Done here.

    local confirmed =
        waitForFusionConfirmation(
            PendingFusion
        )

    if confirmed then

        Stats.Done += 1

        DoneLabel:Set(
            "Done: "
            .. Stats.Done
        )

        StatusLabel:Set(
            "Fused: "
            .. unitNames
        )

        print(
            "[Auto Fuse] CONFIRMED:",
            unitNames
        )

        print(
            "[Auto Fuse] Confirmed Chance: 1 in "
            .. chanceText
        )

    else

        Stats.Failed += 1

        FailedLabel:Set(
            "Failed: "
            .. Stats.Failed
        )

        StatusLabel:Set(
            "Fusion not confirmed"
        )

        warn(
            "[Auto Fuse] Fusion request was not confirmed."
        )
    end

    PendingFusion = nil
    FusionBusy = false

    return confirmed
end

--//==================================================
--// PERFORM FUSION
--//==================================================

local function performFusion()

    if FusionBusy then
        return false
    end

    local data =
        scan()

    if not data then

        StatusLabel:Set(
            "Fuse: Inventory not found"
        )

        TargetLabel:Set(
            "Target: None"
        )

        InventoryLabel:Set(
            "Inventory: 0"
        )

        return false
    end

    InventoryLabel:Set(
        "Inventory: "
        .. data.inventorySize
    )

    ScanLabel:Set(
        "Scans: "
        .. Stats.Scans
    )

    local candidates =
        getCandidates(data)

    if #candidates == 0 then

        StatusLabel:Set(
            "Fuse: Nothing eligible"
        )

        TargetLabel:Set(
            "Target: None"
        )

        return false
    end

    local selected =
        candidates[1]

    return fuseSelected(
        selected
    )
end

--//==================================================
--// FIND NEXT FUSION
--//==================================================

Tab:CreateButton({

    Name = "Find Next Fusion",

    Callback = function()

        task.spawn(
            performFusion
        )

    end,
})

--//==================================================
--// AUTO FUSE
--//==================================================

Tab:CreateToggle({

    Name = "Auto Fuse",

    CurrentValue = false,

    Flag = "AutoFuseToggle",

    Callback = function(value)

        Settings.Enabled = value

        if not value then

            StatusLabel:Set(
                "Fuse: Idle"
            )

            TargetLabel:Set(
                "Target: None"
            )

            return
        end

        StatusLabel:Set(
            "Fuse: Scanning..."
        )

        task.spawn(function()

            while Settings.Enabled do

                if not FusionBusy then
                    performFusion()
                end

                task.wait(
                    Settings.Delay
                )
            end
        end)
    end,
})

--//==================================================
--// DELAY
--//==================================================

Tab:CreateSlider({

    Name = "Fuse Delay",

    Range = {
        0.5,
        5
    },

    Increment = 0.5,

    Suffix = "s",

    CurrentValue = 0.5,

    Flag = "FuseDelaySlider",

    Callback = function(value)

        Settings.Delay = value
    end,
})

--//==================================================
--// INFORMATION
--//==================================================

Tab:CreateSection(
    "Fusion Accuracy"
)

Tab:CreateLabel(
    "Done counts only after the fused units disappear."
)

Tab:CreateLabel(
    "FireServer is not counted as a completed fusion."
)

Tab:CreateLabel(
    "A second fusion cannot start while one is pending."
)

Tab:CreateLabel(
    "Scanning avoids per-unit console spam."
)

Tab:CreateLabel(
    "Failed counts fusion requests that were not confirmed."
)

Tab:CreateLabel(
    "Each fusion is checked before the next one begins."
)

--//==================================================
--// HOW IT SELECTS
--//==================================================

Tab:CreateSection(
    "How It Selects"
)

Tab:CreateLabel(
    "Groups units by displayed 1 in X chance."
)

Tab:CreateLabel(
    "Only groups with 3+ copies are eligible."
)

Tab:CreateLabel(
    "From / Below control the chance range."
)

Tab:CreateLabel(
    "Rarest First selects the highest chance."
)

Tab:CreateLabel(
    "Most Copies First selects the largest group."
)

Tab:CreateLabel(
    "Lowest Value First selects the lowest chance."
)

Tab:CreateLabel(
    "Exactly 3 units are selected."
)

--//==================================================
--// ANIMATION REMOVER
--//==================================================

Tab:CreateSection(
    "Animation Remover"
)

Tab:CreateLabel(
    "Disables the FusingController result listener."
)

Tab:CreateLabel(
    "The Result RemoteEvent itself remains active."
)

Tab:CreateLabel(
    "This removes the fusion animation without GUI scanning."
)

--//==================================================
--// STATUS
--//==================================================

Tab:CreateSection(
    "Current Status"
)

Tab:CreateLabel(
    "Done = confirmed fusions."
)

Tab:CreateLabel(
    "Failed = unconfirmed fusion requests."
)

Tab:CreateLabel(
    "Scans = completed inventory scans."
)

--//==================================================
--// LOADED
--//==================================================

Rayfield:Notify({

    Title = "Auto Fuse",

    Content =
        "Fast Auto Fuse + accurate confirmation loaded.",

    Duration = 4
})
