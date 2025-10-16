--[[
    Script de Bypass e Teleporte para Coordenada Específica (Tecla G)
    + ESP para Brainrots (mostrando apenas o melhor)

    Lógica de TP baseada no exemplo fornecido pelo usuário.
    1. Usa o Grapple Hook para bypass (sem puxar).
    2. Aplica um impulso vertical com LinearVelocity.
    3. Teleporta para a coordenada do melhor plot usando o Flying Carpet.
    
    Lógica de ESP baseada no arquivo ola.lua.
    - Mostra o nome e a geração apenas do melhor pet.
]]

--// ==================================================================
--// SERVIÇOS E VARIÁVEIS
--// ==================================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Net = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"))
local KEY_TO_PRESS = Enum.KeyCode.K
local isTeleporting = false -- Trava para evitar execuções múltiplas

-- A lista de coordenadas.
local TARGET_COORDINATES = {
    Vector3.new(-479, 19.1, 221.1),
    Vector3.new(-479, 19.1, 112.0),
    Vector3.new(-479, 19.1, 5.1),
    Vector3.new(-479, 19.1, -98.4),
    Vector3.new(-340, 19.1, -100),
    Vector3.new(-340, 19.1, 7),
    Vector3.new(-340, 19.1, 113),
    Vector3.new(-340, 19.1, 218)
}

--// ==================================================================
--// CONFIGURAÇÕES E FUNÇÕES DO ESP (de ola.lua)
--// ==================================================================
local TARGET_LABEL_NAME = "Generation"
local espElements = { Brainrots = {} }

local function parseNum(text)
    text = tostring(text or "")
    local token = text:match("([%d%.]+%s*[KkMmBbTtQq]?)") or "0"
    token = token:gsub("%s","")
    local num, suf = token:match("([%d%.]+)([KkMmBbTtQq]?)")
    num = tonumber(num) or 0
    local mult = ({K=1e3, M=1e6, B=1e9, T=1e12, Q=1e15})[suf and suf:upper() or ""] or 1
    return num * mult
end

local function findBasePart(model)
    if model:FindFirstChild("Base") and model.Base:IsA("BasePart") then return model.Base end
    for _,v in ipairs(model:GetChildren()) do if v:IsA("BasePart") then return v end end
end

local function findDisplayName(model) 
    local d = model:FindFirstChild("DisplayName", true)
    return (d and d:IsA("TextLabel")) and d.Text or model.Name 
end

local function createPetBillboard(model) 
    local basePart = findBasePart(model)
    if not basePart then return end
    local bb = Instance.new("BillboardGui", CoreGui)
    bb.Size = UDim2.new(0, 160, 0, 40)
    bb.AlwaysOnTop = true
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.Adornee = basePart
    local top = Instance.new("TextLabel", bb)
    top.Name = "Top"
    top.Size = UDim2.new(1, 0, 0.5, 0)
    top.BackgroundTransparency = 1
    top.TextColor3 = Color3.fromRGB(255, 255, 0)
    top.TextStrokeTransparency = 0
    top.Font = Enum.Font.GothamBold
    top.TextScaled = true
    local bottom = Instance.new("TextLabel", bb)
    bottom.Name = "Bottom"
    bottom.Size = UDim2.new(1, 0, 0.5, 0)
    bottom.Position = UDim2.new(0, 0, 0.5, 0)
    bottom.BackgroundTransparency = 1
    bottom.TextColor3 = Color3.fromRGB(0, 255, 0)
    bottom.TextStrokeTransparency = 0
    bottom.Font = Enum.Font.GothamBold
    bottom.TextScaled = true
    espElements.Brainrots[model] = bb
    return bb
end

local function updatePetBillboard(model, displayName, genText) 
    local bb = espElements.Brainrots[model]
    if not bb then bb = createPetBillboard(model) end
    if not bb or not bb.Parent then espElements.Brainrots[model] = nil; return; end
    bb.Top.Text = displayName
    bb.Bottom.Text = genText
end

local function startEspBrainrotLoop()
    task.spawn(function()
        while task.wait(0.5) do
            local bestPet = {value = -1, model = nil}
            local qualifyingPets = {}

            -- 1. Coleta todos os pets e encontra o melhor
            for _, lbl in ipairs(Workspace:GetDescendants()) do
                if lbl:IsA("TextLabel") and lbl.Name == TARGET_LABEL_NAME then
                    if string.find(lbl.Text, "/s") then -- Ignora temporizadores
                        local mdl = lbl:FindFirstAncestorOfClass("Model")
                        if mdl and not tostring(mdl):lower():find("board") then
                            local val = parseNum(lbl.Text)
                            if val > bestPet.value then
                                local dName = findDisplayName(mdl)
                                bestPet = {model = mdl, label = lbl, displayName = dName, value = val}
                            end
                        end
                    end
                end
            end

            -- 2. Decide o que mostrar (apenas o melhor)
            if bestPet.model then
                qualifyingPets[bestPet.model] = bestPet
            end

            -- 3. Atualiza os ESPs na tela
            for mdl, esp in pairs(espElements.Brainrots) do
                if not qualifyingPets[mdl] or not mdl.Parent then
                    esp:Destroy()
                    espElements.Brainrots[mdl] = nil
                end
            end
            for mdl, data in pairs(qualifyingPets) do
                updatePetBillboard(mdl, data.displayName, data.label.Text)
            end
        end
    end)
    print("[ESP Brainrot] Ativado.")
end


--// ==================================================================
--// FUNÇÕES DE BUSCA (MELHOR PLOT E COORDENADA)
--// ==================================================================

-- Encontra o modelo da Plot pai a partir de um objeto filho (como a base do pódio)
local function findParentPlot(object)
    local current = object
    while current and current.Parent do
        if current:IsA("Model") and current.Parent == game.Workspace.Plots then
            return current
        end
        current = current.Parent
    end
    return nil
end

-- Encontra a plot que contém o pet com a maior "Generation"
local function findBestPlotModel()
    local bestPetLabel = nil
    local highestGeneration = -1

    if not Workspace:FindFirstChild("Plots") then
        print("[Bypass TP] Erro: Pasta 'Plots' não encontrada no Workspace.")
        return nil
    end

    for _, plot in ipairs(Workspace.Plots:GetChildren()) do
        if plot:IsA("Model") then
            for _, descendant in ipairs(plot:GetDescendants()) do
                if descendant:IsA("TextLabel") and descendant.Name == "Generation" then
                    local text = descendant.Text
                    -- CORREÇÃO: Adicionado filtro "/s" também aqui
                    if string.find(text, "/s") then
                        local num = parseNum(text)
                        if num > highestGeneration then
                            highestGeneration = num
                            bestPetLabel = descendant
                        end
                    end
                end
            end
        end
    end

    if bestPetLabel then
        print(string.format("[Bypass TP] Melhor pet encontrado com Geração: %.0f", highestGeneration))
        return findParentPlot(bestPetLabel)
    end

    print("[Bypass TP] Nenhum pet com 'Generation' válido encontrado para TP.")
    return nil
end

-- Verifica qual das coordenadas da lista está dentro dos limites de uma plot
local function findCoordinateInPlot(plotModel)
    if not plotModel then return nil end

    local cf, size = plotModel:GetBoundingBox()
    local min = cf.Position - (size / 2)
    local max = cf.Position + (size / 2)

    for _, coord in ipairs(TARGET_COORDINATES) do
        if (coord.X >= min.X and coord.X <= max.X) and
           (coord.Y >= min.Y and coord.Y <= max.Y) and
           (coord.Z >= min.Z and coord.Z <= max.Z) then
           print("[Bypass TP] Coordenada encontrada na plot: " .. tostring(coord))
           return coord
        end
    end

    print("[Bypass TP] Nenhuma das coordenadas alvo foi encontrada dentro da melhor plot.")
    return nil
end

--// ==================================================================
--// FUNÇÃO PRINCIPAL DA SEQUÊNCIA DE TELEPORTE
--// ==================================================================
local function executeBypassAndTeleport()
    if isTeleporting then return end
    isTeleporting = true

    -- 1. Encontrar a coordenada de destino
    print("[Bypass TP] Iniciando busca pelo melhor plot...")
    local bestPlot = findBestPlotModel()
    local targetPosition = findCoordinateInPlot(bestPlot)

    if not targetPosition then
        print("[Bypass TP] Falha ao encontrar uma coordenada válida. Ação cancelada.")
        isTeleporting = false
        return
    end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")

    if not (humanoid and backpack and rootPart and humanoid.Health > 0) then
        isTeleporting = false
        return
    end

    -- 2. Bypass com Grapple Hook (sem ser puxado)
    local grappleHook = backpack:FindFirstChild("Grapple Hook")
    if grappleHook then
        print("[Bypass TP] Etapa 1: Usando o Grapple Hook.")
        humanoid:EquipTool(grappleHook)
        task.wait() 
        Net:RemoteEvent("UseItem"):FireServer(90 / 120)
    else
        print("[Bypass TP] AVISO: 'Grapple Hook' não encontrado na mochila.")
    end

    task.wait(0.1)

    -- 3. Impulso para cima
    print("[Bypass TP] Etapa 2: Aplicando impulso vertical.")
    local attachment = Instance.new("Attachment", rootPart)
    local linearVelocity = Instance.new("LinearVelocity", attachment)
    linearVelocity.MaxForce = math.huge
    linearVelocity.VectorVelocity = Vector3.new(0, 100, 0)
    linearVelocity.Attachment0 = attachment
    
    Debris:AddItem(attachment, 0.2)
    Debris:AddItem(linearVelocity, 0.2)

    task.wait(0.3)

    -- 4. Teleporte para a coordenada alvo
    local carpet = backpack:FindFirstChild("Flying Carpet")
    if not carpet then
        print("[Bypass TP] AVISO: 'Flying Carpet' não encontrado para o teleporte.")
        isTeleporting = false
        return
    end

    print("[Bypass TP] Etapa 3: Teleportando para a coordenada " .. tostring(targetPosition) .. "...")
    
    local connection
    connection = character.ChildAdded:Connect(function(child)
        if child == carpet then
            connection:Disconnect()

            local flightHold = Instance.new("BodyPosition", rootPart)
            flightHold.Name = "FlightHold"
            flightHold.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            flightHold.Position = targetPosition
            flightHold.P = 100000
            flightHold.D = 500

            Debris:AddItem(flightHold, 0.2)
            
            task.wait(0.2)

            if rootPart then
                print("[Bypass TP] Aplicando freio e estabilizando.")
                rootPart.Velocity = Vector3.new(0, 0, 0)
                rootPart.RotVelocity = Vector3.new(0, 0, 0)
                rootPart.Anchored = true
                task.wait()
                rootPart.Anchored = false
            end

            humanoid:UnequipTools()

            isTeleporting = false
            print("[Bypass TP] Sequência finalizada.")
        end
    end)

    humanoid:EquipTool(carpet)

    task.delay(2, function()
        if connection then connection:Disconnect() end
        if isTeleporting then
            isTeleporting = false
            print("[Bypass TP] Trava de segurança liberada.")
        end
    end)
end

--// ==================================================================
--// INICIALIZAÇÃO
--// ==================================================================
print("[Bypass TP] Ativado. Pressione '" .. KEY_TO_PRESS.Name .. "' para encontrar o melhor plot e teleportar.")
startEspBrainrotLoop() -- Ativa o ESP

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if input.KeyCode == KEY_TO_PRESS then
        executeBypassAndTeleport()
    end
end)
