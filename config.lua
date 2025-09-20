task.wait(8) 

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local MAX_UNDERGROUND_OFFSET = 10
local MIN_UNDERGROUND_OFFSET = 0
local TELEPORT_NEAR_TREE_OFFSET = 25
local HORIZONTAL_DISTANCE_THRESHOLD = 9999
local SELL_WORLD_ID = 3475397644
local FARM_WORLD_ID = 125804922932357
local PLACE_ID = 125804922932357

-- 🌍 ระบบจัดการโลกสุ่ม
local WORLD_FARM = 125804922932357
local WORLD_ORIGINS = 3475397644
local OTHER_WORLDS = { 4601778915, 3475419198, 3475422608, 3487210751, 3623549100, 3737848045, 3752680052, 4174118306, 4728805070 }
local farmStartTime = tick()
local lastSafePosition = Vector3.new(0, 100, 0)
local triedServers = {}

-- 🚀 เพิ่มความเร็วในการฟาร์ม
local ATTACK_DELAY = 0.02  -- ลดจาก 0.05 เหลือ 0.02
local FARM_CHECK_DELAY = 0.1  -- ลดจาก 1 เหลือ 0.1

-- 🍎 ตัวแปรสำหรับระบบดูดของใหม่
local ITEM_PULL_DELAY = 0.3  -- รอ 0.3 วินาทีระหว่างการดูดแต่ละไอเทม
local ITEM_COLLECTION_WAIT = 0.5  -- รอให้ไอเทมเข้าตัวผู้เล่น
local lastPullTime = 0
local collectingItems = false

pcall(function()
    local mobRemote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    if mobRemote then
        local target = mobRemote:FindFirstChild("MobDamageRemote")
        if target then
            target:Destroy()
            print("")
        end
    end
end)

-- 🔍 ดึงจำนวนผู้เล่นในเซิร์ฟเวอร์ของแต่ละโลก
local function getServerWithFewPlayers(placeId)
    local request = (syn and syn.request) or request or http_request
    if not request then
        warn("❌ Executor ของคุณไม่รองรับ HTTP request")
        return nil
    end

    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
    local response = request({ Url = url, Method = "GET" })

    if response and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        for _, server in ipairs(data.data) do
            if server.playing <= 1 then
                return placeId
            end
        end
    end

    return nil
end

-- 🎲 วาร์ปไปโลกสุ่มจาก OTHER_WORLDS
local function teleportToRandomWorld()
    local randomWorld = OTHER_WORLDS[math.random(1, #OTHER_WORLDS)]
    print("🌍 วาร์ปไปโลกสุ่ม:", randomWorld)
    task.wait(3)
    ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(randomWorld, {})
end

-- 🎲 วาร์ปไปโลกที่ว่างจริงจาก OTHER_WORLDS
local function teleportToNextEmptyWorld()
    for _, world in ipairs(OTHER_WORLDS) do
        local found = getServerWithFewPlayers(world)
        if found then
            print("🌍 วาร์ปไปโลกสุ่มที่ว่างจริง:", found)
            task.wait(3)
            ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(found, {})
            return true
        end
    end
    
    -- ถ้าไม่เจอโลกว่าง ให้สุ่มไปโลกใดโลกหนึ่ง
    print("❌ ไม่มีโลกไหนในรายการที่ว่างเลย - สุ่มไปโลกใดโลกหนึ่ง")
    teleportToRandomWorld()
    return true
end

local function checkAndHandlePlayers()
    local currentPlace = game.PlaceId

    if currentPlace == WORLD_FARM then
        if #Players:GetPlayers() > 1 then
            print("👥 โลกฟาร์มมีผู้เล่นอื่น → ไปหาที่ว่างในโลกสุ่ม...")
            teleportToNextEmptyWorld()
            return true
        else
            print("✅ โลกฟาร์มมีแค่เรา → เริ่มฟาร์มต่อได้เลย")
            return false -- อยู่โลกฟาร์มคนเดียว ไม่ต้องวาร์ป
        end
    elseif currentPlace == WORLD_ORIGINS then
        if #Players:GetPlayers() > 1 then
            print("🏪 โลก Origins มีผู้เล่นอื่น → ไปโลกสุ่ม...")
            teleportToRandomWorld()
            return true
        end
    elseif table.find(OTHER_WORLDS, currentPlace) then
        if #Players:GetPlayers() > 1 then
            print("⛔ โลกสุ่มนี้มีคนอื่น → วาร์ปไปโลกสุ่มอื่น...")
            teleportToNextEmptyWorld()
            return true
        else
            print("✅ โลกสุ่มว่าง → กลับไปโลกฟาร์ม")
            task.wait(3)
            ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(WORLD_FARM, {})
            return true
        end
    end

    return false
end

-- 🌀 Hop ไปเซิร์ฟเวอร์ใหม่ ที่มีคุณแค่คนเดียว
local function hopUntilSolo()
    local requestFunc = (syn and syn.request) or http_request or request
    if not requestFunc then
        warn("❌ Executor ของคุณไม่รองรับ HTTP request")
        return
    end
    
    local found = false
    
    while not found do
        local url = "https://games.roblox.com/v1/games/" .. PLACE_ID .. "/servers/Public?sortOrder=Asc&limit=100"
        local result = requestFunc({ Url = url, Method = "GET" })
        
        if result and result.StatusCode == 200 then
            local servers = HttpService:JSONDecode(result.Body).data
            for _, server in ipairs(servers) do
                if server.id ~= game.JobId and not triedServers[server.id] and server.playing <= 1 then
                    triedServers[server.id] = true
                    print("🔁 Hop ไปเซิร์ฟใหม่แบบว่าง:", server.id)
                    TeleportService:TeleportToPlaceInstance(PLACE_ID, server.id, Players.LocalPlayer)
                    found = true
                    break
                end
            end
        end
        task.wait(1)
    end
end

-- 🔍 ตรวจเช็คว่ามีคนอื่นอยู่ในเซิร์ฟไหม และจัดการโลกอัตโนมัติ
task.spawn(function()
    task.wait(5) -- รอให้โหลดเสร็จ
    
    -- เช็คครั้งแรกเมื่อเริ่มต้น
    local blocked = checkAndHandlePlayers()
    
    -- ถ้าอยู่ในโลกฟาร์มและไม่มีการวาร์ป
    if game.PlaceId == WORLD_FARM and not blocked then
        print("✅ เริ่มต้นในโลกฟาร์ม - พร้อมฟาร์ม")
    end
    
    -- วนลูปเช็คทุก 30 วินาที
    while true do
        task.wait(30)
        checkAndHandlePlayers()
    end
end)

-- ✅ วาร์ปไป FARM_WORLD_ID อัตโนมัติ
task.spawn(function()
    task.wait(2)
    local remoteTeleport = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("WorldTeleportRemote")

    -- ถ้าไม่อยู่ในโลกฟาร์ม ให้วาร์ปไป
    if game.PlaceId ~= FARM_WORLD_ID and not table.find(OTHER_WORLDS, game.PlaceId) then
        print("🛫 วาร์ปไปโลกฟาร์ม...")
        local args = { FARM_WORLD_ID, {} }
        remoteTeleport:InvokeServer(unpack(args))
    else
        print("✅ อยู่ในโลกที่ถูกต้องแล้ว")
    end
end)

local watchedItems = {
   "EdamameFoodModel","KajiFruitFoodModel","MistSudachiFoodModel"
}

local targetNames = {
   "AppleFoodModel", "LemonFoodModel", "CornFoodModel", "CarrotFoodModel", "PearFoodModel",
    "StrawberryFoodModel", "PeachFoodModel", "PotatoFoodModel", "BroccoliFoodModel", "CherryFoodModel",
    "BuleberryFoodModel", "MushroomFoodModel", "BananaFoodModel", "AlmondFoodModel", "OnionFoodModel",
    "KelpFoodModel", "GrapesFoodModel", "WatermelonFoodModel", "PricklyPearFoodModel", "ChiliFoodModel",
    "GlowingMushroomFoodModel", "PineappleFoodModel", "CottonCandyFoodModel", "JuniperBerryFoodModel",
    "LimeFoodModel", "DragonfruitFoodModel", "AvacadoFoodModel", "CacaoBeanFoodModel", "CoconutFoodModel","EdamameFoodModel","KajiFruitFoodModel","MistSudachiFoodModel"
}

local isFarming = true -- 🟢 เริ่มฟาร์มทันที

-- 🎨 UI ใหม่ที่สวยกว่าเดิม
local function createModernUI()
    local screenGui = Instance.new("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"))
    screenGui.Name = "NEXON_MODERN_UI"
    screenGui.ResetOnSpawn = false

    -- 🌟 Main Container
    local mainContainer = Instance.new("Frame", screenGui)
    mainContainer.Size = UDim2.new(0, 450, 0, 320)
    mainContainer.Position = UDim2.new(0.5, -225, 0.5, -160)
    mainContainer.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
    mainContainer.BorderSizePixel = 0
    mainContainer.Name = "MainContainer"

    -- 🎯 Gradient Background
    local gradient = Instance.new("UIGradient", mainContainer)
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 30, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 20, 30))
    }
    gradient.Rotation = 45

    -- 📐 Round Corners
    local cornerMain = Instance.new("UICorner", mainContainer)
    cornerMain.CornerRadius = UDim.new(0, 20)

    -- ✨ Border Glow
    local stroke = Instance.new("UIStroke", mainContainer)
    stroke.Color = Color3.fromRGB(0, 255, 150)
    stroke.Thickness = 2
    stroke.Transparency = 0.5

    -- 🔥 Title with Animation
    local titleFrame = Instance.new("Frame", mainContainer)
    titleFrame.Size = UDim2.new(1, -20, 0, 60)
    titleFrame.Position = UDim2.new(0, 10, 0, 10)
    titleFrame.BackgroundTransparency = 1

    local titleText = Instance.new("TextLabel", titleFrame)
    titleText.Size = UDim2.new(1, 0, 1, 0)
    titleText.BackgroundTransparency = 1
    titleText.Font = Enum.Font.GothamBlack
    titleText.Text = "⚡ NEXON WORLD SHINRIN ⚡"
    titleText.TextColor3 = Color3.fromRGB(0, 255, 150)
    titleText.TextSize = 24
    titleText.TextStrokeTransparency = 0.8

    -- 🌈 Title Animation
    task.spawn(function()
        while true do
            local tween = game:GetService("TweenService"):Create(
                titleText, 
                TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                {TextColor3 = Color3.fromRGB(255, 100, 255)}
            )
            tween:Play()
            task.wait(2)
        end
    end)

    -- 📊 Stats Panel
    local statsPanel = Instance.new("Frame", mainContainer)
    statsPanel.Size = UDim2.new(1, -20, 0, 120)
    statsPanel.Position = UDim2.new(0, 10, 0, 80)
    statsPanel.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
    statsPanel.BorderSizePixel = 0

    local statsCorner = Instance.new("UICorner", statsPanel)
    statsCorner.CornerRadius = UDim.new(0, 15)

    local statsGlow = Instance.new("UIStroke", statsPanel)
    statsGlow.Color = Color3.fromRGB(100, 150, 255)
    statsGlow.Thickness = 1
    statsGlow.Transparency = 0.7

    -- 📈 Items Grid
    local itemsFrame = Instance.new("Frame", statsPanel)
    itemsFrame.Size = UDim2.new(1, -20, 0, 80)
    itemsFrame.Position = UDim2.new(0, 10, 0, 10)
    itemsFrame.BackgroundTransparency = 1

    local itemsLayout = Instance.new("UIGridLayout", itemsFrame)
    itemsLayout.CellSize = UDim2.new(0, 130, 0, 35)
    itemsLayout.CellPadding = UDim2.new(0, 5, 0, 5)

    _G.FarmItemLabels = {}

    for _, name in ipairs(watchedItems) do
        local itemName = name:gsub("FoodModel", "")

        local itemCard = Instance.new("Frame", itemsFrame)
        itemCard.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
        itemCard.BorderSizePixel = 0

        local cardCorner = Instance.new("UICorner", itemCard)
        cardCorner.CornerRadius = UDim.new(0, 8)

        local label = Instance.new("TextLabel", itemCard)
        label.Size = UDim2.new(1, -10, 1, 0)
        label.Position = UDim2.new(0, 5, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamSemibold
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextSize = 14
        label.Text = itemName .. ": 0"
        label.TextXAlignment = Enum.TextXAlignment.Left

        _G.FarmItemLabels[itemName] = label
    end

    -- ⏱️ Time Display
    local timeLabel = Instance.new("TextLabel", statsPanel)
    timeLabel.Size = UDim2.new(0, 200, 0, 25)
    timeLabel.Position = UDim2.new(1, -210, 1, -35)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Font = Enum.Font.GothamBold
    timeLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    timeLabel.TextSize = 16
    timeLabel.Text = "🕒 00:00"

    -- 🎮 Control Panel
    local controlPanel = Instance.new("Frame", mainContainer)
    controlPanel.Size = UDim2.new(1, -20, 0, 80)
    controlPanel.Position = UDim2.new(0, 10, 1, -90)
    controlPanel.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    controlPanel.BorderSizePixel = 0

    local controlCorner = Instance.new("UICorner", controlPanel)
    controlCorner.CornerRadius = UDim.new(0, 15)

    -- 🔘 Toggle Button
    local toggleButton = Instance.new("TextButton", controlPanel)
    toggleButton.Size = UDim2.new(0, 200, 0, 50)
    toggleButton.Position = UDim2.new(0.5, -100, 0.5, -25)
    toggleButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.Font = Enum.Font.GothamBlack
    toggleButton.TextSize = 18
    toggleButton.BorderSizePixel = 0
    toggleButton.Text = "⏸️ STOP FARMING"

    local toggleCorner = Instance.new("UICorner", toggleButton)
    toggleCorner.CornerRadius = UDim.new(0, 12)

    local toggleStroke = Instance.new("UIStroke", toggleButton)
    toggleStroke.Thickness = 2
    toggleStroke.Color = Color3.fromRGB(255, 255, 255)
    toggleStroke.Transparency = 0.3

    -- 💡 Status Indicator
    local statusDot = Instance.new("Frame", controlPanel)
    statusDot.Size = UDim2.new(0, 20, 0, 20)
    statusDot.Position = UDim2.new(0, 20, 0.5, -10)
    statusDot.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    statusDot.BorderSizePixel = 0

    local dotCorner = Instance.new("UICorner", statusDot)
    dotCorner.CornerRadius = UDim.new(0.5, 0)

    -- 🌟 Status Animation
    task.spawn(function()
        while true do
            if isFarming then
                statusDot.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
                local tween = game:GetService("TweenService"):Create(
                    statusDot,
                    TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                    {Size = UDim2.new(0, 25, 0, 25)}
                )
                tween:Play()
            else
                statusDot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
            end
            task.wait(0.5)
        end
    end)

    -- 🖱️ Drag Functionality
    local UserInputService = game:GetService("UserInputService")
    local dragging = false
    local dragInput, dragStart, startPos

    mainContainer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainContainer.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    mainContainer.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            local newPosition = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            mainContainer.Position = newPosition
        end
    end)

    -- 🎯 Toggle Function
    toggleButton.MouseButton1Click:Connect(function()
        isFarming = not isFarming
        
        if isFarming then
            toggleButton.Text = "⏸️ STOP FARMING"
            toggleButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
        else
            toggleButton.Text = "▶️ START FARMING"
            toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        end
    end)

    -- 📊 Stats Update Loop
    task.spawn(function()
        while true do
            local now = tick()
            local elapsed = now - farmStartTime
            timeLabel.Text = string.format("🕒 %02d:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60))

            local res = LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Resources")
            if res then
                for _, name in ipairs(watchedItems) do
                    local itemName = name:gsub("FoodModel", "")
                    local val = res:FindFirstChild(itemName)
                    local label = _G.FarmItemLabels[itemName]
                    if label then
                        if val and val.Value > 0 then
                            label.Text = "💎 " .. itemName .. ": " .. tostring(val.Value)
                            -- 🌈 Color animation for high values
                            if val.Value >= 5000 then
                                label.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold
                            elseif val.Value >= 1000 then
                                label.TextColor3 = Color3.fromRGB(0, 255, 100) -- Green
                            else
                                label.TextColor3 = Color3.fromRGB(255, 255, 255) -- White
                            end
                        else
                            label.Text = "💎 " .. itemName .. ": 0"
                            label.TextColor3 = Color3.fromRGB(150, 150, 150)
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end

-- ✅ ตรวจสอบและขาย
local function sellEverythingInInventory()
    local res = LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Resources")
    if not res then return end
    local args = {}
    for _, item in ipairs(res:GetChildren()) do
        if item:IsA("NumberValue") and item.Value >= 200 then
            table.insert(args, {
                ItemName = item.Name,
                Amount = 10000
            })
        end
    end
    if #args > 0 then
        ReplicatedStorage.Remotes.SellItemRemote:FireServer(unpack(args))
        print("✅ ขายไอเทมทั้งหมดในกระเป๋าแล้ว")
    end
end

local function allWatchedItemsReachedTarget()
    local res = LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Resources")
    if not res then return false end
    for _, itemName in ipairs(watchedItems) do
        local cleanName = itemName:gsub("FoodModel", "")
        local val = res:FindFirstChild(cleanName)
        if not val or val.Value < 10000 then
            return false
        end
    end
    return true
end

local function checkAndSell()
    local res = LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Resources")
    if not res then return end
    local remoteTeleport = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("WorldTeleportRemote")

    if game.PlaceId == SELL_WORLD_ID then
        local sold = false
        for _, itemName in ipairs(watchedItems) do
            local cleanName = itemName:gsub("FoodModel", "")
            local val = res:FindFirstChild(cleanName)
            if val and val.Value >= 50 then
                ReplicatedStorage.Remotes.SellItemRemote:FireServer({
                    ItemName = cleanName,
                    Amount = 10000
                })
                sold = true
                task.wait(0.1) -- เร็วขึ้น
            end
        end
        if sold then
            task.wait(0.5) -- เร็วขึ้น
            print("✅ ขายเสร็จ → วาร์ปกลับโลกฟาร์ม")
            local args = { FARM_WORLD_ID, {} }
            remoteTeleport:InvokeServer(unpack(args))
        end
    else
        if allWatchedItemsReachedTarget() then
            print("🛫 ทุกไอเทมถึง 200 แล้ว → วาร์ปไปโลกขาย")
            local args = { SELL_WORLD_ID, {} }
            remoteTeleport:InvokeServer(unpack(args))
        end
    end
end

-- ✅ ป้องกันตกโลก
RunService.Stepped:Connect(function()
    local hrp = Character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Position.Y < -100 then
        hrp.CFrame = CFrame.new(lastSafePosition)
    end
end)

-- ✅ ตรวจทุก 0.5 วินาที (เร็วขึ้น)
task.spawn(function()
    while true do
        pcall(checkAndSell)
        task.wait(0.5)
    end
end)

-- ✅ Anti-AFK
task.spawn(function()
    while true do
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        print("🛡️ Anti-AFK: คลิกกันหลุด")
        task.wait(120) -- ลดเหลือ 2 นาที
    end
end)

-- ✅ ฟาร์ม LargeFoodNode (เร็วขึ้น)
local function getRemote(name)
    for i = 1, 100 do
        local dragon = Character:FindFirstChild("Dragons") and Character.Dragons:FindFirstChild(tostring(i))
        if dragon and dragon:FindFirstChild("Remotes") then
            local remote = dragon.Remotes:FindFirstChild(name)
            if remote then return remote end
        end
    end
    return nil
end

local function getHealth(part)
    return part and part:FindFirstChild("Health")
end

local function teleportTo(part, offset)
    local root = Character:FindFirstChild("HumanoidRootPart")
    if root and part then
        root.CFrame = CFrame.new(part.Position - Vector3.new(0, offset or 0, 0))
    end
end

-- 🍎 ระบบดูดของใหม่แบบค่อยๆ ดูด
local function pullItemToPlayerSafely()
    if collectingItems then 
        return -- ถ้ากำลังเก็บของอยู่ ไม่ดูดเพิ่ม
    end
    
    local now = tick()
    if now - lastPullTime < ITEM_PULL_DELAY then
        return -- ยังไม่ถึงเวลาดูดครั้งต่อไป
    end
    
    local root = Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local itemsFound = false
    local itemsPulled = 0
    
    -- 🔍 หาไอเทมที่ต้องดูด (จำกัดแค่ 3 ชิ้นต่อครั้ง)
    for _, source in ipairs({workspace, workspace:FindFirstChild("Camera")}) do
        if itemsPulled >= 3 then break end -- จำกัดการดูดไม่เกิน 3 ชิ้น
        
        for _, name in ipairs(targetNames) do
            if itemsPulled >= 3 then break end
            
            local model = source and source:FindFirstChild(name)
            if model and model:IsA("Model") and model.PrimaryPart then
                local distance = (model.PrimaryPart.Position - root.Position).Magnitude
                
                -- ดูดแค่ไอเทมที่ไกลพอสมควร (ไม่ใกล้เกินไป)
                if distance > 5 and distance < 100 then
                    -- ดูดแบบค่อยๆ ไม่วาร์ปตรงไปตรงมา
                    local targetPos = root.Position + Vector3.new(
                        math.random(-2, 2), -- สุ่มตำแหน่งเล็กน้อย
                        math.random(1, 3), 
                        math.random(-2, 2)
                    )
                    
                    model:SetPrimaryPartCFrame(CFrame.new(targetPos))
                    itemsFound = true
                    itemsPulled = itemsPulled + 1
                    
                    print("🍎 ดูดไอเทม:", name, "ระยะทาง:", math.floor(distance))
                    
                    -- รอหน่อยระหว่างการดูดแต่ละชิ้น
                    task.wait(0.1)
                end
            end
        end
    end
    
    lastPullTime = now
    
    -- ถ้าดูดไอเทมแล้ว ให้รอไอเทมเข้าตัว
    if itemsFound then
        collectingItems = true
        print("🕒 รอให้ไอเทมเข้าตัว...")
        task.wait(ITEM_COLLECTION_WAIT) -- รอให้ไอเทมเข้าตัว
        collectingItems = false
        print("✅ เก็บไอเทมเสร็จแล้ว")
    end
end

local function distanceXZ(a, b)
    local dxz = Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)
    return dxz.Magnitude
end

local function attackTarget(part)
    local remote = getRemote("PlaySoundRemote")
    if not remote then return end

    local health = getHealth(part)
    if not health or health.Value <= 0 then return end

    local root = Character:FindFirstChild("HumanoidRootPart")
    local offset = MAX_UNDERGROUND_OFFSET

    -- วาร์ปเข้าใกล้ต้นไม้
    if distanceXZ(root.Position, part.Position) > HORIZONTAL_DISTANCE_THRESHOLD then
        teleportTo(part, TELEPORT_NEAR_TREE_OFFSET)
        task.wait(0.05) -- เร็วขึ้น
    end

    local success = false
    while offset >= MIN_UNDERGROUND_OFFSET do
        teleportTo(part, offset)
        task.wait(0.05) -- เร็วขึ้น

        local before = health.Value
        for _ = 1, 5 do -- เพิ่มจำนวนการยิง
            remote:FireServer("Breath", "Destructibles", part)
            task.wait(ATTACK_DELAY)
        end

        if health.Value < before then
            lastSafePosition = part.Position + Vector3.new(0, 10, 0)
            success = true
            break
        end
        offset -= 3 -- ลดการเปลี่ยน offset
    end

    -- ยิงต่อเนื่องจนกว่า health จะเป็น 0
    if success then
        while health.Value > 0 do
            for _ = 1, 3 do -- ลดจำนวนการยิง
                remote:FireServer("Breath", "Destructibles", part)
            end
            
            -- ดูดของระหว่างที่ยิง (แต่แบบค่อยๆ)
            pullItemToPlayerSafely()
            task.wait(ATTACK_DELAY)
        end
    end

    -- จบแล้ววาร์ปกลับขึ้นมาจากใต้ดิน
    teleportTo(part, MAX_UNDERGROUND_OFFSET)
    
    -- ดูดของอีกครั้งหลังจากฟาร์มเสร็จ
    task.wait(0.2)
    pullItemToPlayerSafely()
end

-- 🍎 ระบบดูดของแบบอัตโนมัติ (ค่อยๆ ดูด)
task.spawn(function()
    while true do
        if isFarming and not collectingItems then
            pcall(pullItemToPlayerSafely)
        end
        task.wait(2) -- ดูดทุก 2 วินาที (ช้าลงเพื่อความปลอดภัย)
    end
end)

-- ✅ ใช้ Heartbeat ฟาร์มแบบเร็ว
print("[⚡] เริ่มฟาร์ม LargeFoodNode แบบเทอร์โบ!")
local lastFarmCheck = 0
RunService.Heartbeat:Connect(function(dt)
    local now = tick()
    if now - lastFarmCheck >= FARM_CHECK_DELAY then
        lastFarmCheck = now
        if not isFarming then return end -- ⛔ หากหยุดฟาร์มอยู่
        
        local foodFolder = workspace:FindFirstChild("Interactions")
            and workspace.Interactions:FindFirstChild("Nodes")
            and workspace.Interactions.Nodes:FindFirstChild("Food")

        if foodFolder then
            for _, node in ipairs(foodFolder:GetChildren()) do
                if node:IsA("Model") and node.Name == "LargeFoodNode" then
                    local part = node:FindFirstChild("BillboardPart")
                    local health = getHealth(part)
                    if part and health and health.Value > 0 then
                        print("[⚡] ฟาร์มเทอร์โบ:", node:GetFullName())
                        pcall(function() attackTarget(part) end)
                        break
                    end
                end
            end
        end
    end
end)

-- ✅ สร้าง UI
createModernUI()
