--// ==================================================================
--// SCRIPT UNIFICADO: LÓGICA ORIGINAL PRESERVADA
--// ==================================================================

--// ===================== SERVIÇOS DO JOGO =====================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

--// ===================== CONFIGURAÇÕES GLOBAIS =====================
local player = Players.LocalPlayer
local Net = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"))
local DEBUG_LOGS_ENABLED = true
local TARGET_LABEL_NAME = "Generation" 

--// ===================== CONFIGURAÇÃO DE KEYBINDS =====================
--// O script usará a tabela '_G.CustomKeybinds' se ela existir.
--// Caso contrário, usará as keybinds padrão abaixo.
local Keybinds = _G.CustomKeybinds or {
    GrappleFly = Enum.KeyCode.Q,
    AutoSteal = Enum.KeyCode.N,
    Fly = Enum.KeyCode.F,
    GoToBrainrot = Enum.KeyCode.G,
    Platform = Enum.KeyCode.T,
    Desync = Enum.KeyCode.E,
    AutoLaser = Enum.KeyCode.L,
    XRay = nil -- Padrão: X-Ray não tem tecla de atalho
}

--// Configs Grapple Fly
local GRAPPLE_FLY_SPEED = 250
local GRAPPLE_NORMAL_WALKSPEED = 16
local GRAPPLE_SECONDARY_WALKSPEED = 34

--// Configs Auto Steal
local AUTO_STEAL_SCAN_INTERVAL = 0.5

--// Configs Fly (Original fly.lua)
local FLY_SPEED = 100
local GOTO_BRAINROT_SPEED = 150 -- Velocidade para o Go To Brainrot
local FLY_BYPASS_COOLDOWN = 3.1

--// Configs ESP Brainrot (Original baba.lua)
local ESP_PET_MIN_VALUE = 10e6 -- 10M
local ESP_PET_EXCEPTION_NAME = "Chicleteira Bicicleteira"
local ESP_PET_SHOW_ONLY_BEST = false -- false = mostra todos acima do valor, true = mostra só o melhor

--// Configs ESP Player (Original baba.lua)
local ESP_PLAYER_HIGHLIGHT_FILL = Color3.fromRGB(0, 200, 255)
local ESP_PLAYER_HIGHLIGHT_OUTLINE = Color3.fromRGB(0, 0, 0)
local ESP_PLAYER_NAME_COLOR = Color3.fromRGB(255, 255, 255)

--// Configs Auto Laser (NOVO)
local LASER_CAPE_NAME = "Laser Cape"
local LASER_ATTACK_RANGE = 75
local LASER_ATTACK_COOLDOWN = 1.0

--// ===================== VARIÁVEIS DE CONTROLE =====================
local SystemStates = {
    GrappleFly = false, AutoSteal = false, Fly = false, 
    EspPlayer = false, EspBrainrot = false, AntiLag = false, AntiInvis = false,
    GoToBrainrot = false, XRay = false, Desync = false, Platform = false,
    AutoLaser = false -- NOVO
}
local RunningThreads = {}
local isGrappleLogicRunning = false
local lastLaserAttackTime = 0 -- NOVO

--// INICIALIZAÇÃO DOS SISTEMAS AUTOMÁTICOS (NOVO)
--// Verifica variáveis globais para ativar os ESPs
SystemStates.EspPlayer = _G.ESP_PLAYER == true
SystemStates.EspBrainrot = _G.ESP_BRAINROT == true
SystemStates.XRay = _G.XRAY == true
--// O Anti-Invis continua atrelado ao ESP de Jogador
SystemStates.AntiInvis = _G.ESP_PLAYER == true 
--// O Anti-Lag agora é um estado permanente
SystemStates.AntiLag = false


--// ===================== FUNÇÕES AUXILIARES (ORIGINAIS) =====================
local function debugLog(system, message) if DEBUG_LOGS_ENABLED then print("[" .. system .. "] " .. tostring(message)) end end

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

--// ==================================================================
--// LÓGICA DO AUTO LASER (NOVO)
--// ==================================================================
local function executeAutoLaser()
    if not SystemStates.AutoLaser or not player.Character or os.clock() - lastLaserAttackTime < LASER_ATTACK_COOLDOWN then
        return
    end

    local myCharacter = player.Character
    local humanoid = myCharacter:FindFirstChildOfClass("Humanoid")
    local myRootPart = myCharacter:FindFirstChild("HumanoidRootPart")
    local laserCape = (player.Backpack and player.Backpack:FindFirstChild(LASER_CAPE_NAME)) or player:FindFirstChild(LASER_CAPE_NAME)

    if not (humanoid and myRootPart and laserCape) then return end

    local nearestTarget, minDistance = nil, LASER_ATTACK_RANGE
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local targetRootPart = otherPlayer.Character.HumanoidRootPart
            local distance = (myRootPart.Position - targetRootPart.Position).Magnitude
            if distance < minDistance then
                minDistance = distance
                nearestTarget = targetRootPart
            end
        end
    end

    if nearestTarget then
        local originalTool = myCharacter:FindFirstChildOfClass("Tool")
        humanoid:EquipTool(laserCape)
        Net:RemoteEvent("UseItem"):FireServer(nearestTarget.Position, nearestTarget)
        lastLaserAttackTime = os.clock()
        task.wait()
        if originalTool then
            humanoid:EquipTool(originalTool)
        else
            humanoid:UnequipTools()
        end
        debugLog("AutoLaser", "Atirou no alvo a " .. string.format("%.2f", minDistance) .. " studs.")
    end
end

--// ==================================================================
--// LÓGICA DO GRAPPLE FLY (ORIGINAL)
--// ==================================================================
local grappleFlightConnection = nil
local grappleTracerLine, grappleTracerAdornee
local function executeGrappleFly()
    if isGrappleLogicRunning then return end
    isGrappleLogicRunning = true
    local SCAN_INTERVAL,BYPASS_COOLDOWN,ARRIVAL_DISTANCE,STOP_COOLDOWN,BRAKING_DISTANCE,MIN_FLY_SPEED = 0.25,3.1,3,0.1,20,40
    local grappleTargetPart,lastStopTime = nil,0
    local function createTracerLine() if grappleTracerLine and grappleTracerLine.Parent then return end; pcall(function() CoreGui:FindFirstChild("GrappleTracerLine"):Destroy() end); pcall(function() CoreGui:FindFirstChild("GrappleTracerAdornee"):Destroy() end); grappleTracerLine = Instance.new("LineHandleAdornment"); grappleTracerLine.Name = "GrappleTracerLine"; grappleTracerLine.Color3 = Color3.fromRGB(255, 0, 255); grappleTracerLine.Thickness = 1; grappleTracerLine.Transparency = 0.4; grappleTracerLine.Parent = CoreGui; grappleTracerAdornee = Instance.new("Part"); grappleTracerAdornee.Name = "GrappleTracerAdornee"; grappleTracerAdornee.Size = Vector3.new(0.1, 0.1, 0.1); grappleTracerAdornee.Transparency = 1; grappleTracerAdornee.Anchored = true; grappleTracerAdornee.CanCollide = false; grappleTracerAdornee.Parent = CoreGui; end
    local function updateTracerLine(startPos, endPos) if not grappleTracerLine or not grappleTracerAdornee or not grappleTracerLine.Parent or not grappleTracerAdornee.Parent then createTracerLine() end; grappleTracerAdornee.Position = startPos; grappleTracerLine.Adornee = grappleTracerAdornee; grappleTracerLine.Length = (startPos - endPos).Magnitude; grappleTracerAdornee.CFrame = CFrame.new(startPos, endPos); grappleTracerLine.Visible = true; end
    local function hideTracerLine() if grappleTracerLine then grappleTracerLine.Visible = false end end
    local function stopFlying(reason) if grappleFlightConnection then grappleFlightConnection:Disconnect(); grappleFlightConnection = nil; end; local char = player.Character; local rootPart = char and char:FindFirstChild("HumanoidRootPart"); if rootPart then pcall(function() rootPart:FindFirstChild("GrappleLinearVelocity"):Destroy() end); pcall(function() rootPart:FindFirstChild("GrappleAttachment"):Destroy() end); rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0); end; debugLog("GrappleFly", "Voo interrompido: " .. (reason or "N/A")); grappleTargetPart = nil; hideTracerLine(); lastStopTime = os.clock(); end
    local function startFlyingTo(rootPart, targetPart)
        if grappleFlightConnection then return end
        debugLog("GrappleFly", "Iniciando voo para: " .. targetPart:GetFullName())
        grappleTargetPart = targetPart
        local targetModel = grappleTargetPart:FindFirstAncestorOfClass("Model")
        local lastBypassTime = 0
        local attachment = Instance.new("Attachment", rootPart)
        attachment.Name = "GrappleAttachment"
        local linearVelocity = Instance.new("LinearVelocity", rootPart)
        linearVelocity.Name = "GrappleLinearVelocity"
        linearVelocity.Attachment0 = attachment
        linearVelocity.MaxForce = 100000
        linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
        grappleFlightConnection = RunService.Heartbeat:Connect(function()
            if not isGrappleLogicRunning or not grappleTargetPart or not grappleTargetPart.Parent or not player.Character or (targetModel and not targetModel.Parent) then stopFlying("Alvo/Sistema inválido"); return end
            local currentRootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if not currentRootPart then stopFlying("RootPart inválido"); return end
            local targetPosition = targetModel and targetModel:GetBoundingBox().Position or grappleTargetPart.Position
            local distanceToTarget = (currentRootPart.Position - targetPosition).Magnitude
            if distanceToTarget < ARRIVAL_DISTANCE then
                linearVelocity.VectorVelocity = Vector3.new(0, 0, 0)
                local petModel = grappleTargetPart:FindFirstAncestorOfClass("Model")
                if petModel then
                    local prompt = petModel:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and string.find(prompt.ActionText:lower(), "roubar") then
                        debugLog("GrappleFly", "Chegou e acionou prompt")
                        prompt:InputHoldBegin()
                    end
                end
                stopFlying("Chegou ao destino")
                return
            end
            if os.clock() - lastBypassTime > BYPASS_COOLDOWN then
                Net:RemoteEvent("UseItem"):FireServer(90 / 120)
                lastBypassTime = os.clock()
            end
            local currentSpeed
            if distanceToTarget < BRAKING_DISTANCE then
                local ratio = math.max(0, (distanceToTarget - ARRIVAL_DISTANCE) / (BRAKING_DISTANCE - ARRIVAL_DISTANCE))
                currentSpeed = math.max(MIN_FLY_SPEED, ratio * GRAPPLE_FLY_SPEED)
            else
                currentSpeed = GRAPPLE_FLY_SPEED
            end
            linearVelocity.VectorVelocity = (targetPosition - currentRootPart.Position).Unit * currentSpeed
            updateTracerLine(currentRootPart.Position, targetPosition)
        end) -- O 'end)' que faltava está aqui
    end
        RunningThreads.GrappleFly = task.spawn(function() debugLog("GrappleFly", "Loop iniciado."); while isGrappleLogicRunning do task.wait(SCAN_INTERVAL); if grappleFlightConnection then continue end; local char = player.Character; local rootPart = char and char:FindFirstChild("HumanoidRootPart"); if not rootPart or os.clock() - lastStopTime < STOP_COOLDOWN then hideTracerLine(); continue; end; local tool = char:FindFirstChildOfClass("Tool"); if not (tool and tool.Name == "Grapple Hook") then local hook = player:FindFirstChildOfClass("Backpack"):FindFirstChild("Grapple Hook"); if hook then char.Humanoid:EquipTool(hook); end; end; local bestPet = {model=nil, value=-1}; for _,lbl in ipairs(Workspace:GetDescendants()) do if lbl:IsA("TextLabel") and lbl.Name == TARGET_LABEL_NAME then if string.find(lbl.Text, "/s") then local mdl = lbl:FindFirstAncestorOfClass("Model"); if mdl and not tostring(mdl):lower():find("board") then local val = parseNum(lbl.Text); if val > bestPet.value then bestPet = {model=mdl, value=val}; end; end; end; end; end; if bestPet.model then local petPart = findBasePart(bestPet.model); if petPart then startFlyingTo(rootPart, petPart); end; else hideTracerLine(); end; end; stopFlying("Loop encerrado"); isGrappleLogicRunning = false; RunningThreads.GrappleFly = nil; debugLog("GrappleFly", "Loop finalizado."); end)
end
local function stopGrappleFly() if not isGrappleLogicRunning then return end; isGrappleLogicRunning = false; print("[Sistema] Grapple Fly DESATIVADO."); end

--// ==================================================================
--// LÓGICA DO GOTO BRAINROT (iraobrainrot.lua)
--// ==================================================================
local goToBrainrotConnection = nil
local goToBrainrotLV, goToBrainrotAtt = nil, nil

local function stopGoToBrainrot(reason)
    -- A verificação foi removida na correção anterior, mas se você a adicionou de volta,
    -- vamos garantir que a lógica correta esteja aqui.
    -- A função deve poder ser chamada mesmo que o voo não tenha começado.
    
    debugLog("GoToBrainrot", "Voo interrompido: " .. (reason or "N/A"))


    if goToBrainrotConnection then
        goToBrainrotConnection:Disconnect()
        goToBrainrotConnection = nil
    end
    
    if goToBrainrotLV then goToBrainrotLV:Destroy() end
    if goToBrainrotAtt then goToBrainrotAtt:Destroy() end
    goToBrainrotLV, goToBrainrotAtt = nil, nil
    
    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if rootPart then
        rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
    end

    -- Desativa o estado e ATUALIZA O BOTÃO
    if SystemStates.GoToBrainrot then
        SystemStates.GoToBrainrot = false
        if _G.updateButtons then pcall(_G.updateButtons) end -- CORRIGIDO: Chama a função global
    end
end

local function executeGoToBrainrot()
    if goToBrainrotConnection or not SystemStates.GoToBrainrot then return end

    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        debugLog("GoToBrainrot", "Personagem inválido.")
        stopGoToBrainrot("Personagem inválido")
        return
    end

    -- LÓGICA DE BUSCA ATUALIZADA (USANDO A LÓGICA DO GRAPPLE FLY ORIGINAL)
    local targetPet = {model=nil, value=-1}
    for _,lbl in ipairs(Workspace:GetDescendants()) do 
        if lbl:IsA("TextLabel") and lbl.Name == TARGET_LABEL_NAME then 
            if string.find(lbl.Text, "/s") then
                local mdl = lbl:FindFirstAncestorOfClass("Model")
                if mdl and not tostring(mdl):lower():find("board") then 
                    local val = parseNum(lbl.Text)
                    if val > targetPet.value then 
                        targetPet = {model=mdl, value=val}
                    end
                end 
            end
        end 
    end

    if not targetPet.model then
        debugLog("GoToBrainrot", "Nenhum brainrot encontrado.")
        stopGoToBrainrot("Nenhum alvo")
        return
    end
    
    local targetPart = findBasePart(targetPet.model)
    if not targetPart then
        debugLog("GoToBrainrot", "Parte base do alvo não encontrada.")
        stopGoToBrainrot("Alvo sem parte base")
        return
    end

    local rootPart = char.HumanoidRootPart
    local humanoid = char.Humanoid

    local tool = char:FindFirstChildOfClass("Tool")
    if not (tool and tool.Name == "Grapple Hook") then
        local hook = player.Backpack:FindFirstChild("Grapple Hook")
        if hook then humanoid:EquipTool(hook) else
            debugLog("GoToBrainrot", "Grapple Hook não encontrado.")
            stopGoToBrainrot("Sem ferramenta")
            return
        end
    end

    local currentFlightAltitude
    if targetPart.Position.Y < 10 then currentFlightAltitude = 40
    elseif targetPart.Position.Y < 20 then currentFlightAltitude = 60
    else currentFlightAltitude = 80 end
    
    local currentArrivalDistance = 5 -- Distância de parada aumentada para segurança

    goToBrainrotAtt = Instance.new("Attachment", rootPart)
    goToBrainrotLV = Instance.new("LinearVelocity", rootPart)
    goToBrainrotLV.Attachment0 = goToBrainrotAtt
    goToBrainrotLV.MaxForce = 100000
    goToBrainrotLV.RelativeTo = Enum.ActuatorRelativeTo.World
    
    local forwardTargetPos = rootPart.Position + (rootPart.CFrame.LookVector * 15)
    local upwardTargetPos = nil
    local phase = "forward"
    local lastBypassTime = 0

    goToBrainrotConnection = RunService.Heartbeat:Connect(function()
        if not SystemStates.GoToBrainrot or not targetPet.model or not targetPet.model.Parent or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            stopGoToBrainrot("Estado inválido")
            return
        end
        
        local currentRootPart = player.Character.HumanoidRootPart
        
        if os.clock() - lastBypassTime > FLY_BYPASS_COOLDOWN then
            Net:RemoteEvent("UseItem"):FireServer(90 / 120)
            lastBypassTime = os.clock()
        end

        if phase == "forward" then
            if (currentRootPart.Position - forwardTargetPos).Magnitude < 5 then
                phase = "up"
            else
                goToBrainrotLV.VectorVelocity = (forwardTargetPos - currentRootPart.Position).Unit * GOTO_BRAINROT_SPEED
            end
        elseif phase == "up" then
            if not upwardTargetPos then
                 upwardTargetPos = currentRootPart.Position + Vector3.new(0, currentFlightAltitude, 0)
            end
            if currentRootPart.Position.Y >= (upwardTargetPos.Y - 5) then
                phase = "to_target"
            else
                goToBrainrotLV.VectorVelocity = (upwardTargetPos - currentRootPart.Position).Unit * GOTO_BRAINROT_SPEED
            end
        elseif phase == "to_target" then
            local currentTarget = findBasePart(targetPet.model)
            if not currentTarget then stopGoToBrainrot("Alvo desapareceu"); return end
            
            -- LÓGICA DE POSICIONAMENTO REFORÇADA
            local plot = currentTarget:FindFirstAncestorWhichIsA("Model") and currentTarget:FindFirstAncestorWhichIsA("Model"):FindFirstAncestorWhichIsA("Model")
            local frontVector = plot and plot.PrimaryPart and plot.PrimaryPart.CFrame.LookVector or Vector3.new(0,0,-1)
            
            -- Garante que o vetor seja apenas horizontal
            frontVector = Vector3.new(frontVector.X, 0, frontVector.Z).Unit
            
            -- Ponto de parada na frente do alvo, na passarela
            local finalTargetPos = currentTarget.Position + (frontVector * 10) + Vector3.new(0, 2, 0)

            if (currentRootPart.Position - finalTargetPos).Magnitude < currentArrivalDistance then
                stopGoToBrainrot("Chegou ao destino")
                return
            else
                goToBrainrotLV.VectorVelocity = (finalTargetPos - currentRootPart.Position).Unit * GOTO_BRAINROT_SPEED
            end
        end
    end)
end

--// ==================================================================
--// LÓGICA DO AUTO STEAL (ORIGINAL)
--// ==================================================================
local autoStealConnection,currentBestStealTarget = nil,nil
local isAutoStealRunning = false
local function executeAutoSteal()
    if isAutoStealRunning or not player.Character then return end
    isAutoStealRunning = true
    -- A conexão com PromptShown foi removida pois a função 'handlePromptShown' não existe
    -- e a lógica principal já força o acionamento do prompt.
    RunningThreads.AutoSteal = task.spawn(function() 
        debugLog("AutoSteal", "Loop iniciado.")
        while isAutoStealRunning do 
            local bestValue,bestModel = -1,nil; for _, label in ipairs(Workspace:GetDescendants()) do if label:IsA("TextLabel") and label.Name == TARGET_LABEL_NAME then local model = label:FindFirstAncestorOfClass("Model"); if model and not tostring(model):lower():find("board") then local value = parseNum(label.Text); if value > bestValue then bestValue = value; bestModel = model; end; end; end; end; currentBestStealTarget = bestModel; if currentBestStealTarget and currentBestStealTarget.Parent then local prompt = currentBestStealTarget:FindFirstChildWhichIsA("ProximityPrompt", true); if prompt and prompt.Enabled then local actionText = prompt.ActionText:lower(); if string.find(actionText, "steal") or string.find(actionText, "roubar") then debugLog("AutoSteal", "Forçando prompt para: " .. currentBestStealTarget.Name); prompt:InputHoldBegin(); end; end; end; task.wait(AUTO_STEAL_SCAN_INTERVAL); 
        end
        debugLog("AutoSteal", "Loop finalizado.")
    end)
    print("[Sistema] Auto Steal ATIVADO.")
end
local function stopAutoSteal() 
    if not isAutoStealRunning then return end
    isAutoStealRunning = false
    -- A desconexão não é mais necessária.
    currentBestStealTarget = nil
    if RunningThreads.AutoSteal then task.cancel(RunningThreads.AutoSteal); RunningThreads.AutoSteal = nil; end
    debugLog("AutoSteal", "Loop finalizado.")
    print("[Sistema] Auto Steal DESATIVADO.")
end

--// ==================================================================
--// LÓGICA DO XRAY (destroy.lua)
--// ==================================================================
local xrayOriginalProperties = {}
local isXRayRunning = false

local function updateXRay()
    local plots = Workspace:FindFirstChild('Plots')
    if not plots then return end

    for _, plot in ipairs(plots:GetChildren()) do
        local decorations = plot:FindFirstChild('Decorations')
        local animals = plot:FindFirstChild('AnimalPodiums')
        local targets = {decorations, animals}

        for _, targetFolder in ipairs(targets) do
            if targetFolder then
                for _, obj in ipairs(targetFolder:GetDescendants()) do
                    if obj:IsA("BasePart") then
                        if SystemStates.XRay then
                            if not xrayOriginalProperties[obj] then
                                xrayOriginalProperties[obj] = {
                                    Transparency = obj.Transparency,
                                    LocalTransparencyModifier = obj.LocalTransparencyModifier
                                }
                            end
                            obj.Transparency = 0.8
                        else
                            if xrayOriginalProperties[obj] then
                                obj.Transparency = xrayOriginalProperties[obj].Transparency
                                xrayOriginalProperties[obj] = nil
                            end
                        end
                    end
                end
            end
        end
    end
end

--// ==================================================================
--// LÓGICA DA PLATAFORMA (ADAPTADA DE lippe.lua)
--// ==================================================================
local platformPart, platformConnection
local isPlatformRising = false
local PLATFORM_RISE_SPEED = 15

local function stopPlatform()
    if platformConnection then platformConnection:Disconnect(); platformConnection = nil; end
    if platformPart then platformPart:Destroy(); platformPart = nil; end
    isPlatformRising = false
    SystemStates.Platform = false
    if _G.updateButtons then pcall(_G.updateButtons) end
    debugLog("Platform", "Plataforma destruída.")
end

local function executePlatform()
    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return stopPlatform() end

    platformPart = Instance.new('Part')
    platformPart.Size = Vector3.new(6, 0.5, 6)
    platformPart.Anchored = true
    platformPart.CanCollide = true
    platformPart.Transparency = 0.2
    platformPart.Material = Enum.Material.Neon
    platformPart.Color = Color3.fromRGB(0, 255, 255)
    platformPart.Position = rootPart.Position - Vector3.new(0, rootPart.Size.Y / 2 + platformPart.Size.Y / 2, 0)
    platformPart.Parent = Workspace
    
    isPlatformRising = true
    debugLog("Platform", "Plataforma criada.")

    platformConnection = RunService.Heartbeat:Connect(function(dt)
        if not SystemStates.Platform or not platformPart or not platformPart.Parent then return stopPlatform() end
        
        local currentRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not currentRoot then return stopPlatform() end

        local canRise = (function()
            local origin = platformPart.Position + Vector3.new(0, platformPart.Size.Y / 2, 0)
            local direction = Vector3.new(0, 2, 0)
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = { platformPart, player.Character }
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist
            return not Workspace:Raycast(origin, direction, rayParams)
        end)()

        local cur = platformPart.Position
        local newXZ = Vector3.new(currentRoot.Position.X, cur.Y, currentRoot.Position.Z)
        
        if isPlatformRising and canRise then
            platformPart.Position = newXZ + Vector3.new(0, dt * PLATFORM_RISE_SPEED, 0)
        else
            isPlatformRising = false
            platformPart.Position = newXZ
        end
    end)
end


--// ==================================================================
--// LÓGICA DO FLY (ADAPTADA DE fly.lua)
--// ==================================================================
local flyLV, flyAO, flyAtt = nil, nil, nil
local isFlyActive = false -- Renomeado para evitar conflito com a variável 'isFlying' interna
local lastFlyBypassTime = 0 -- NOVA VARIÁVEL para controlar o tempo do bypass

local function setupFly()
    if flyAtt then return end -- Já está configurado
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local rootPart = char.HumanoidRootPart
    
    flyAtt = Instance.new("Attachment", rootPart)
    flyAO = Instance.new("AlignOrientation", rootPart); flyAO.Mode = Enum.OrientationAlignmentMode.OneAttachment; flyAO.Attachment0 = flyAtt; flyAO.MaxTorque = 100000; flyAO.Responsiveness = 200
    flyLV = Instance.new("LinearVelocity", rootPart); flyLV.Attachment0 = flyAtt; flyLV.MaxForce = 100000; flyLV.VectorVelocity = Vector3.new(0,0,0); flyLV.RelativeTo = Enum.ActuatorRelativeTo.World
    
    debugLog("Fly", "Componentes de voo criados.")
end

local function cleanupFly()
    if flyAO then flyAO:Destroy() end
    if flyLV then flyLV:Destroy() end
    if flyAtt then flyAtt:Destroy() end
    flyAO, flyLV, flyAtt = nil, nil, nil
    debugLog("Fly", "Componentes de voo destruídos.")
end

-- Loop de Voo contínuo, controlado pelo estado
RunService.Heartbeat:Connect(function()
    if not SystemStates.Fly then
        if isFlyActive then
            cleanupFly()
            isFlyActive = false
            print("[Sistema] Fly DESATIVADO.")
        end
        return
    end

    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        if isFlyActive then
            cleanupFly()
            isFlyActive = false
            print("[Sistema] Fly DESATIVADO (personagem inválido).")
        end
        return
    end

    if not isFlyActive then
        setupFly()
        isFlyActive = true
        lastFlyBypassTime = 0 -- Reseta o timer ao ativar o fly
        print("[Sistema] Fly ATIVADO.")
    end

    if not flyLV or not flyAO then return end

    -- Lógica de Bypass CORRIGIDA
    if os.clock() - lastFlyBypassTime > FLY_BYPASS_COOLDOWN then
        Net:RemoteEvent("UseItem"):FireServer(90/120)
        lastFlyBypassTime = os.clock()
    end

    -- Força o equipamento do Grapple Hook
    local char = player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local hook = player.Backpack:FindFirstChild("Grapple Hook")
        local currentTool = char:FindFirstChildOfClass("Tool")
        if humanoid and hook and (not currentTool or currentTool.Name ~= "Grapple Hook") then
            humanoid:EquipTool(hook)
        end
    end

    -- Controle de movimento
    flyAO.CFrame = Workspace.CurrentCamera.CFrame
    local dir = Vector3.new(0,0,0)
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir - Vector3.new(0,0,1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir + Vector3.new(0,0,1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - Vector3.new(1,0,0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + Vector3.new(1,0,0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0,1,0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0,1,0) end

    if dir.Magnitude > 0 then
        flyLV.VectorVelocity = (Workspace.CurrentCamera.CFrame:VectorToWorldSpace(dir.Unit)) * FLY_SPEED
    else
        flyLV.VectorVelocity = Vector3.new(0,0,0)
    end
end)

-- Garante que o voo pare se o personagem morrer
player.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid").Died:Connect(function()
        if isFlyActive then
            cleanupFly()
            isFlyActive = false
        end
        -- Reseta o Desync ao morrer
        if SystemStates.Desync then
            SystemStates.Desync = false
            if _G.updateButtons then pcall(_G.updateButtons) end
        end
        -- Reseta a Plataforma ao morrer
        if SystemStates.Platform then
            stopPlatform()
        end
    end)
end)


--// ==================================================================
--// LÓGICA DO ANTI-LAG, ANTI-INVIS E ESP (ORIGINAL baba.lua)
--// ==================================================================
local espElements = {PlayersHL = {}, PlayersBB = {}, Brainrots = {}}
-- Anti-Lag
local function clearCharAppearance(c) for _,a in ipairs(c:GetChildren()) do if a:IsA("Accessory") or a:IsA("Shirt") or a:IsA("Pants") or a:IsA("ShirtGraphic") or a:IsA("Clothing") then a:Destroy() end end end
local function startAntiLag()
    for _,p in ipairs(Players:GetPlayers()) do if p.Character then clearCharAppearance(p.Character) end end
    RunningThreads.AntiLagP = Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(clearCharAppearance) end)
    RunningThreads.AntiLagC = player.CharacterAdded:Connect(clearCharAppearance)
    print("[Sistema] Anti-Lag ATIVADO.")
end
local function stopAntiLag() if RunningThreads.AntiLagP then RunningThreads.AntiLagP:Disconnect() end; if RunningThreads.AntiLagC then RunningThreads.AntiLagC:Disconnect() end; print("[Sistema] Anti-Lag DESATIVADO."); end
-- Anti-Invis
local function restoreCharacterVisibility(char) for _,d in ipairs(char:GetDescendants()) do if d:IsA("BasePart") then if d.LocalTransparencyModifier ~= 0 then d.LocalTransparencyModifier = 0 end; if d.Transparency == 1 then d.Transparency = 0 end; local sz=d.Size; if sz.X<0.4 or sz.Y<0.4 or sz.Z<0.4 then d.Size=Vector3.new(math.max(sz.X,0.4),math.max(sz.Y,0.4),math.max(sz.Z,0.4)) end end end end
-- ESP Player
local function getAdorneePart(char) return char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart") end
local function ensureNameBillboard(char, p) local adornee = getAdorneePart(char); if not adornee then return end; if not espElements.PlayersBB[p] or not espElements.PlayersBB[p].Parent then if espElements.PlayersBB[p] then espElements.PlayersBB[p]:Destroy() end; local bb=Instance.new("BillboardGui",CoreGui); bb.AlwaysOnTop=true; bb.Size=UDim2.new(0,140,0,30); bb.StudsOffset=Vector3.new(0,2.5,0); local lbl=Instance.new("TextLabel",bb); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.TextStrokeTransparency=0; lbl.Font=Enum.Font.GothamBold; lbl.TextScaled=true; espElements.PlayersBB[p]=bb; end; espElements.PlayersBB[p].Adornee = adornee; espElements.PlayersBB[p].TextLabel.Text = p.Name; espElements.PlayersBB[p].TextLabel.TextColor3 = ESP_PLAYER_NAME_COLOR; end
local function ensureHighlight(char, p) if not espElements.PlayersHL[p] or not espElements.PlayersHL[p].Parent then if espElements.PlayersHL[p] then espElements.PlayersHL[p]:Destroy() end; local hl=Instance.new("Highlight",CoreGui); hl.FillTransparency=0.3; hl.OutlineTransparency=0; hl.FillColor=ESP_PLAYER_HIGHLIGHT_FILL; hl.OutlineColor=ESP_PLAYER_HIGHLIGHT_OUTLINE; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; espElements.PlayersHL[p]=hl; end; espElements.PlayersHL[p].Adornee = char; end
-- ESP Brainrot
local function findDisplayName(model) local d=model:FindFirstChild("DisplayName",true); return (d and d:IsA("TextLabel")) and d.Text or model.Name end
local function createPetBillboard(model) local basePart=findBasePart(model); if not basePart then return end; local bb=Instance.new("BillboardGui",CoreGui); bb.Size=UDim2.new(0,160,0,40); bb.AlwaysOnTop=true; bb.StudsOffset=Vector3.new(0,2.5,0); bb.Adornee=basePart; local top=Instance.new("TextLabel",bb); top.Name="Top"; top.Size=UDim2.new(1,0,0.5,0); top.BackgroundTransparency=1; top.TextColor3=Color3.fromRGB(255,255,0); top.TextStrokeTransparency=0; top.Font=Enum.Font.GothamBold; top.TextScaled=true; local bottom=Instance.new("TextLabel",bb); bottom.Name="Bottom"; bottom.Size=UDim2.new(1,0,0.5,0); bottom.Position=UDim2.new(0,0,0.5,0); bottom.BackgroundTransparency=1; bottom.TextColor3=Color3.fromRGB(0,255,0); bottom.TextStrokeTransparency=0; bottom.Font=Enum.Font.GothamBold; bottom.TextScaled=true; espElements.Brainrots[model]=bb; return bb; end
local function updatePetBillboard(model, displayName, genText) local bb=espElements.Brainrots[model]; if not bb then bb=createPetBillboard(model) end; if not bb or not bb.Parent then espElements.Brainrots[model]=nil; return; end; bb.Top.Text=displayName; bb.Bottom.Text=genText; end
-- Loop Unificado para ESP e Anti-Invis
local function startEspAndInvisLoop()
    if RunningThreads.EspLoop then return end -- Previne múltiplos loops
    RunningThreads.EspLoop = task.spawn(function()
        while SystemStates.EspPlayer or SystemStates.EspBrainrot or SystemStates.AntiInvis do
            -- Player Loop
            if SystemStates.EspPlayer or SystemStates.AntiInvis then
                local activePlayers = {}
                for _,p in ipairs(Players:GetPlayers()) do
                    if p ~= player and p.Character and p.Character.Parent then
                        activePlayers[p] = true
                        if SystemStates.AntiInvis then restoreCharacterVisibility(p.Character) end
                        if SystemStates.EspPlayer then ensureHighlight(p.Character, p); ensureNameBillboard(p.Character, p) end
                    end
                end
                -- Limpa jogadores que saíram
                for p, hl in pairs(espElements.PlayersHL) do if not activePlayers[p] then hl:Destroy(); espElements.PlayersHL[p] = nil end end
                for p, bb in pairs(espElements.PlayersBB) do if not activePlayers[p] then bb:Destroy(); espElements.PlayersBB[p] = nil end end
            end
            -- Brainrot Loop
            if SystemStates.EspBrainrot then
                local allPets, highValuePets, bestPet = {}, {}, {value = -1}
                local exceptionNameLower = ESP_PET_EXCEPTION_NAME:lower()

                -- 1. Coleta todos os pets e os categoriza
                for _,lbl in ipairs(Workspace:GetDescendants()) do
                    if lbl:IsA("TextLabel") and lbl.Name == TARGET_LABEL_NAME then
                        -- NOVO: Verifica se o texto contém "/s" para ignorar temporizadores
                        if string.find(lbl.Text, "/s") then
                            local mdl = lbl:FindFirstAncestorOfClass("Model")
                            if mdl and not tostring(mdl):lower():find("board") then
                                local val = parseNum(lbl.Text)
                                local dName = findDisplayName(mdl)
                                local petData = {model = mdl, label = lbl, displayName = dName, value = val}
                                
                                allPets[mdl] = petData
                                if val > bestPet.value then bestPet = petData end
                                if val >= ESP_PET_MIN_VALUE or (dName and dName:lower() == exceptionNameLower) then
                                    highValuePets[mdl] = petData
                                end
                            end
                        end
                    end
                end

                -- 2. Decide o que mostrar
                local finalQualifying = {}
                if next(highValuePets) then -- Se encontrou pets de 10M+
                    finalQualifying = highValuePets
                elseif bestPet.model then -- Senão, usa o melhor pet encontrado
                    finalQualifying[bestPet.model] = bestPet
                end

                -- 3. Atualiza os ESPs na tela
                for mdl,esp in pairs(espElements.Brainrots) do
                    if not finalQualifying[mdl] or not mdl.Parent then
                        esp:Destroy()
                        espElements.Brainrots[mdl] = nil
                    end
                end
                for mdl,data in pairs(finalQualifying) do
                    updatePetBillboard(mdl, data.displayName, data.label.Text)
                end
            end
            task.wait(0.5)
        end
        -- Limpeza final movida para a função stop
        RunningThreads.EspLoop = nil
        debugLog("ESP", "Loop finalizado.")
    end)
    print("[Sistema] Loop de ESP / Anti-Invis ATIVADO.")
end
local function stopEspAndInvisLoop() 
    if not (SystemStates.EspPlayer or SystemStates.EspBrainrot or SystemStates.AntiInvis) then
        if RunningThreads.EspLoop then
            task.cancel(RunningThreads.EspLoop)
            RunningThreads.EspLoop = nil
        end
        for _,hl in pairs(espElements.PlayersHL) do hl:Destroy() end; 
        for _,bb in pairs(espElements.PlayersBB) do bb:Destroy() end; 
        for _,bb in pairs(espElements.Brainrots) do bb:Destroy() end
        espElements = {PlayersHL={}, PlayersBB={}, Brainrots={}}
        print("[Sistema] Loop de ESP / Anti-Invis DESATIVADO e limpo.")
    end
end

--// ==================================================================
--// INTERFACE E CONTROLE PRINCIPAL (REDESENHADO)
--// ==================================================================

-- [[ FUNÇÕES DO DESYNC SCRIPT ]]
local function enableMobileDesync()
    local success, err = pcall(function()
        local ReplicatedStorage = game:GetService('ReplicatedStorage')
        local Players = game:GetService('Players')
        local LocalPlayer = Players.LocalPlayer
        local backpack = LocalPlayer:WaitForChild('Backpack')
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = character:WaitForChild('Humanoid')

        local packages = ReplicatedStorage:WaitForChild('Packages', 5)
        if not packages then return false end

        local netFolder = packages:WaitForChild('Net', 5)
        if not netFolder then return false end

        local useItemRemote = netFolder:WaitForChild('RE/UseItem', 5)
        local teleportRemote = netFolder:WaitForChild('RE/QuantumCloner/OnTeleport', 5)
        if not useItemRemote or not teleportRemote then return false end

        local toolNames = { 'Quantum Cloner', 'Brainrot', 'brainrot' }
        local tool
        for _, toolName in ipairs(toolNames) do
            tool = backpack:FindFirstChild(toolName) or character:FindFirstChild(toolName)
            if tool then break end
        end
        if not tool then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA('Tool') then
                    tool = item
                    break
                end
            end
        end

        if tool and tool.Parent == backpack then
            humanoid:EquipTool(tool)
            task.wait(0.5)
        end

        if setfflag then setfflag('WorldStepMax', '-9999999999') end
        task.wait(0.2)
        useItemRemote:FireServer()
        task.wait(1)
        teleportRemote:FireServer()
        task.wait(2)
        if setfflag then setfflag('WorldStepMax', '-1') end
        return true
    end)
    if not success then
        warn("[Desync] Falha ao ativar: " .. tostring(err))
    end
    return success
end

local function disableMobileDesync()
    pcall(function()
        if setfflag then setfflag('WorldStepMax', '-1') end
    end)
end
-- [[ FIM DAS FUNÇÕES DO DESYNC ]]

local function createMasterControlMenu()
    pcall(function() CoreGui:FindFirstChild("MasterControlMenu"):Destroy() end)

    --// Componentes Principais
    local ScreenGui = Instance.new("ScreenGui", CoreGui)
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Name = "MasterControlMenu"

    local MainFrame = Instance.new("Frame", ScreenGui)
    MainFrame.Size = UDim2.new(0, 240, 0, 230)
    MainFrame.Position = UDim2.new(1, -250, 0.5, -115) -- Canto direito, centralizado verticalmente
    MainFrame.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
    MainFrame.BorderColor3 = Color3.fromRGB(50, 52, 60)
    MainFrame.Active = true
    MainFrame.Draggable = true
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", MainFrame).Thickness = 1

    local TitleLabel = Instance.new("TextLabel", MainFrame)
    TitleLabel.Size = UDim2.new(1, 0, 0, 40)
    TitleLabel.BackgroundColor3 = Color3.fromRGB(38, 40, 48)
    TitleLabel.Text = "CodeNova Script"
    TitleLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextSize = 18
    local titleCorner = Instance.new("UICorner", TitleLabel)
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent.ClipsDescendants = true 
    local titleFrame = Instance.new("Frame", TitleLabel)
    titleFrame.Size = UDim2.new(1,0,1,2)
    titleFrame.Position = UDim2.new(0,0,1,-8)
    titleFrame.BackgroundColor3 = TitleLabel.BackgroundColor3
    titleFrame.BorderSizePixel = 0

    --// Layout Automático para Botões
    local ButtonContainer = Instance.new("Frame", MainFrame)
    ButtonContainer.Size = UDim2.new(1, -20, 1, -50)
    ButtonContainer.Position = UDim2.new(0, 10, 0, 40)
    ButtonContainer.BackgroundTransparency = 1
    local ListLayout = Instance.new("UIListLayout", ButtonContainer)
    ListLayout.Padding = UDim.new(0, 8)
    ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    --// Função para criar botões estilizados (CORRIGIDA)
    local function createButton(text)
        local btn = Instance.new("TextButton", ButtonContainer)
        btn.Size = UDim2.new(1, 0, 0, 35)
        btn.Font = Enum.Font.Gotham
        btn.TextColor3 = Color3.fromRGB(200, 200, 200)
        btn.TextSize = 16
        btn.Text = text -- CORRIGIDO: Define o texto inicial aqui
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        Instance.new("UIStroke", btn).Color = Color3.fromRGB(80, 82, 90)
        return btn
    end

    --// Declarações
    local updateButtons
    
    -- Helper para gerar o texto da keybind
    local function getKeybindText(name)
        if Keybinds[name] then
            return " (" .. Keybinds[name].Name .. ")"
        end
        return ""
    end

    local buttons = {
        GrappleFly = {btn = createButton(""), text = "Grapple Fly" .. getKeybindText("GrappleFly")},
        AutoSteal = {btn = createButton(""), text = "Auto Steal Nearest" .. getKeybindText("AutoSteal")},
        Fly = {btn = createButton(""), text = "Fly" .. getKeybindText("Fly")},
        GoToBrainrot = {btn = createButton(""), text = "Go To Brainrot" .. getKeybindText("GoToBrainrot")},
        Platform = {btn = createButton(""), text = "3rd Floor" .. getKeybindText("Platform")},
        Desync = {btn = createButton(""), text = "Desync" .. getKeybindText("Desync")},
        AutoLaser = {btn = createButton(""), text = "Auto Laser" .. getKeybindText("AutoLaser")},
        XRay = {btn = createButton(""), text = "X-Ray" .. getKeybindText("XRay")}
    }
    -- Reordenando os botões na UI
    buttons.GrappleFly.btn.LayoutOrder = 1
    buttons.AutoSteal.btn.LayoutOrder = 2
    buttons.Fly.btn.LayoutOrder = 3
    buttons.GoToBrainrot.btn.LayoutOrder = 4
    buttons.Platform.btn.LayoutOrder = 5
    buttons.Desync.btn.LayoutOrder = 6
    buttons.AutoLaser.btn.LayoutOrder = 7 -- Ordem ajustada
    buttons.XRay.btn.LayoutOrder = 8      -- Ordem ajustada

    MainFrame.Size = UDim2.new(0, 240, 0, 40 + (#ButtonContainer:GetChildren() * (35 + ListLayout.Padding.Offset)) + 15)
    MainFrame.Position = UDim2.new(1, -250, 0.5, -MainFrame.AbsoluteSize.Y / 2)

    --// Função de Atualização Visual
    updateButtons = function()
        for name, data in pairs(buttons) do
            if SystemStates[name] then
                data.btn.Text = data.text .. ": ON"
                data.btn.BackgroundColor3 = Color3.fromRGB(0, 130, 90) -- Verde Ativo
                data.btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                data.btn.Text = data.text .. ": OFF"
                data.btn.BackgroundColor3 = Color3.fromRGB(65, 45, 50) -- Vermelho Inativo
                data.btn.TextColor3 = Color3.fromRGB(200, 200, 200)
            end
        end
    end
    _G.updateButtons = updateButtons
    updateButtons() -- ADICIONADO: Define as cores iniciais dos botões

    --// Lógica dos Botões e Funções de Toggle
    local function toggleSystem(name)
        SystemStates[name] = not SystemStates[name]
        if name == "XRay" then updateXRay() end
        updateButtons()
    end

    local function handleGoToBrainrot()
        if SystemStates.GoToBrainrot then
            stopGoToBrainrot("Cancelado pelo usuário")
        else
            SystemStates.GoToBrainrot = true
            updateButtons()
            executeGoToBrainrot()
        end
    end

    local function handlePlatform()
        SystemStates.Platform = not SystemStates.Platform
        if SystemStates.Platform then
            executePlatform()
        else
            stopPlatform()
        end
        updateButtons()
    end

    local function handleDesync()
        -- Se já estiver ativo, apenas desativa.
        if SystemStates.Desync then
            SystemStates.Desync = false
            disableMobileDesync()
            updateButtons()
            return
        end

        -- Se estiver inativo, inicia o processo de ativação.
        SystemStates.Desync = true
        local desyncBtn = buttons.Desync.btn
        desyncBtn.Text = "Desync (E): Ativando..."
        desyncBtn.BackgroundColor3 = Color3.fromRGB(250, 160, 0) -- Laranja para "Ativando"
        
        -- A função enableMobileDesync tem pausas, então a UI atualizará.
        if not enableMobileDesync() then
            SystemStates.Desync = false -- Falhou, reverte o estado.
        end
        
        -- Atualiza o botão para o estado final (ON ou OFF).
        updateButtons()
    end

    buttons.GrappleFly.btn.MouseButton1Click:Connect(function() toggleSystem("GrappleFly") end)
    buttons.AutoSteal.btn.MouseButton1Click:Connect(function() toggleSystem("AutoSteal") end)
    buttons.Fly.btn.MouseButton1Click:Connect(function() toggleSystem("Fly") end)
    buttons.XRay.btn.MouseButton1Click:Connect(function() toggleSystem("XRay") end)
    buttons.AutoLaser.btn.MouseButton1Click:Connect(function() toggleSystem("AutoLaser") end) -- NOVO
    buttons.GoToBrainrot.btn.MouseButton1Click:Connect(handleGoToBrainrot)
    buttons.Platform.btn.MouseButton1Click:Connect(handlePlatform)
    buttons.Desync.btn.MouseButton1Click:Connect(handleDesync)

    --// Lógica dos Atalhos (Keybinds)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end -- Ignora se estiver digitando no chat, etc.

        -- Mapeia a tecla pressionada para a função correspondente
        for funcName, keyCode in pairs(Keybinds) do
            if keyCode and input.KeyCode == keyCode then
                -- Chama a função de tratamento específica, se houver
                if funcName == "GoToBrainrot" then handleGoToBrainrot()
                elseif funcName == "Platform" then handlePlatform()
                elseif funcName == "Desync" then handleDesync()
                else
                    -- Usa o toggle padrão para as outras funções
                    toggleSystem(funcName)
                end
                break -- Para a verificação após encontrar a tecla
            end
        end
    end)

    -- Loop de controle principal para gerenciar os estados
    task.spawn(function() 
        while true do 
            task.wait(0.2)
            
            local char = player.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")

            -- Controle do Grapple Fly
            if humanoid then 
                local correctSpeed = (humanoid.WalkSpeed == GRAPPLE_NORMAL_WALKSPEED or humanoid.WalkSpeed == GRAPPLE_SECONDARY_WALKSPEED)
                if SystemStates.GrappleFly and correctSpeed and not isGrappleLogicRunning then executeGrappleFly() 
                elseif (not SystemStates.GrappleFly or not correctSpeed) and isGrappleLogicRunning then stopGrappleFly() end 
            elseif isGrappleLogicRunning then 
                stopGrappleFly() 
            end

            -- Controle do Auto Steal
            if SystemStates.AutoSteal and not isAutoStealRunning then executeAutoSteal() 
            elseif not SystemStates.AutoSteal and isAutoStealRunning then stopAutoSteal() end
            
            -- Controle do Auto Laser
            executeAutoLaser()

            -- Controle do X-Ray (NOVO)
            if SystemStates.XRay then
                updateXRay()
            end
        end 
    end)
end

--// Inicia tudo
createMasterControlMenu()

--// INICIA SISTEMAS AUTOMÁTICOS (NOVO)
if SystemStates.AntiLag then
    startAntiLag()
end
if SystemStates.XRay then
    updateXRay()
end
if SystemStates.EspPlayer or SystemStates.EspBrainrot or SystemStates.AntiInvis then
    startEspAndInvisLoop()
e

-- [[ DESYNC SCRIPT ]] -- REMOVA TODO O BLOCO ANTIGO DAQUI
-- [[ FIM DO DESYNC SCRIPT ]] -- ATÉ AQUI
