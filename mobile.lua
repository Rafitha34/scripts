local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local KEY = rawget(_G, "script_key") or getgenv().script_key or script_key
local FIREBASE_KEY_URL = "https://codenova-f5457-default-rtdb.firebaseio.com/mobile.json"
local FIREBASE_JOB_URL = "https://codenova-f5457-default-rtdb.firebaseio.com/ccc.json"

local function prints(str)
    print("[KeySystem]: " .. str)
end

if not KEY or KEY == "" then
    prints("❌ Defina a variável script_key antes de executar o script!")
    return
end

local function parseKeyData(data)
    -- data = { ["key"] = "2025-09-23T23:57:56.580Z,nick1,nick2" }
    for k, v in pairs(data) do
        if k == KEY then
            local parts = {}
            for part in string.gmatch(v, "([^,]+)") do
                table.insert(parts, part)
            end
            local expires = parts[1]
            table.remove(parts, 1)
            local nicks = parts
            return expires, nicks
        end
    end
    return nil, nil
end

local function isExpired(isoDate)
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):([%d%.]+)Z"
    local y, m, d, h, min, s = isoDate:match(pattern)
    if not y then return true end
    local now = os.time(os.date("!*t"))
    local exp = os.time({
        year = tonumber(y),
        month = tonumber(m),
        day = tonumber(d),
        hour = tonumber(h),
        min = tonumber(min),
        sec = math.floor(tonumber(s)),
    })
    return now > exp
end

local function checkKey()
    local success, response = pcall(function()
        return game:HttpGet(FIREBASE_KEY_URL)
    end)
    if not success or not response then
        prints("❌ Erro ao acessar o banco de dados de keys.")
        return false
    end

    local successDecode, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)
    if not successDecode or not data then
        prints("❌ Erro ao decodificar dados de keys.")
        return false
    end

    local expires, nicks = parseKeyData(data)
    if not expires then
        prints("❌ Key inválida ou não encontrada.")
        return false
    end

    if isExpired(expires) then
        prints("❌ Key expirada! Validade: " .. expires)
        return false
    end

    local found = false
    for _, nick in ipairs(nicks) do
        if nick:lower() == LocalPlayer.Name:lower() then
            found = true
            break
        end
    end

    if found then
        prints("✅ Key válida e nick autorizado!")
        return true
    else
        prints("⚠️ Key válida, mas seu nick NÃO está autorizado!")
        return false
    end
end

local function readJobID()
    local success, response = pcall(function()
        return game:HttpGet(FIREBASE_JOB_URL)
    end)

    if not success or not response then
        prints("❌ Erro ao buscar JobID do site.")
        return nil
    end

    local successDecode, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not successDecode or not data then
        prints("❌ Erro ao decodificar dados do JobID.")
        return nil
    end

    -- Se for string pura, retorna direto
    if typeof(data) == "string" and data ~= "" then
        local jobID = data:gsub("%s+", "")
        prints("🔎 JobID encontrado!")
        return jobID
    end

    -- Se for objeto, busca o campo job_id
    if typeof(data) == "table" and data.job_id and data.job_id ~= "" then
        local jobID = data.job_id:gsub("%s+", "")
        prints("🔎 JobID encontrado!")
        return jobID
    end

    prints("❌ JobID não encontrado no site.")
    return nil
end

local function setJobIdInput(jobId)
    for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if gui:IsA("ScreenGui") then
            for _, descendant in ipairs(gui:GetDescendants()) do
                if descendant:IsA("TextBox") then
                    local path = ""
                    pcall(function() path = descendant:GetFullName() end)
                    
                    -- Caminho 1 (Mobile): Job-ID Input.InputFrame.InputBox
                    if descendant.Name == "InputBox" and path:find("Job%-ID ?Input%.InputFrame%.InputBox") then
                        pcall(function()
                            descendant:CaptureFocus() -- Simula o clique no TextBox
                            descendant.Text = jobId -- Define o valor
                            descendant:ReleaseFocus() -- Libera o foco após alterar
                        end)
                        return true
                    end

                    -- Caminho 2 (Desktop/Outros): Job-ID Input. ... .Input
                    if descendant.Name == "Input" and path:find("Job%-ID ?Input") then
                        pcall(function()
                            descendant:CaptureFocus() -- Simula o clique no TextBox
                            descendant.Text = jobId -- Define o valor
                            descendant:ReleaseFocus() -- Libera o foco após alterar
                        end)
                        return true
                    end
                end
            end
        end
    end
    prints("❌ Campo de input do Job ID não encontrado com nenhum caminho conhecido.")
    return false
end

local function clicarBotaoJoin()
    for _, obj in ipairs(game:GetService("CoreGui"):GetDescendants()) do
        -- Caminho 1 (Mobile): Frame "Join Job-ID" com um botão dentro
        if obj:IsA("Frame") and obj.Name == "Join Job-ID" then
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("TextButton") or child:IsA("ImageButton") then
                    if getconnections then
                        for _, conn in ipairs(getconnections(child.MouseButton1Click)) do
                            conn:Fire()
                        end
                    end
                    return true
                end
            end
        end
        
        -- Caminho 2 (Desktop/Outros): Botão chamado "Join Job-ID" diretamente
        if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and obj.Name == "Join Job-ID" then
            if getconnections then
                for _, conn in ipairs(getconnections(obj.MouseButton1Click)) do
                    conn:Fire()
                end
            end
            return true
        end
    end
    prints("❌ Botão 'Join' não encontrado com nenhum caminho conhecido.")
    return false
end

-- Execução principal
task.spawn(function()
    if not checkKey() then
        prints("❌ A chave é inválida ou não autorizada. Encerrando o script.")
        return
    end

    prints("✅ Chave validada com sucesso! Iniciando monitoramento de Job IDs...")
    local ultimoJobId = nil

    while true do
        local jobID = readJobID()
        if jobID and jobID ~= ultimoJobId then
            prints("🆕 Novo JobID encontrado: " .. tostring(jobID))
            setJobIdInput(jobID) -- Preenche o campo de texto
            task.wait(0.005) -- Aguarda 0.005 segundos
            clicarBotaoJoin() -- Clica no botão
            ultimoJobId = jobID -- Atualiza o último JobID
        end
        task.wait(0.5) -- Verifica atualizações a cada 0.5 segundos
    end
end)
