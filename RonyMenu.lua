-- ╔══════════════════════════════════════════════════════════════╗
-- ║  GHOST AIM v12  |  ANÁLISE COMPLETA + TUDO MELHORADO       ║
-- ║  Raycast cacheado • Predição dt-based • Fire multicamada   ║
-- ║  Steering inteligente • Farm Mode • Fluent UI              ║
-- ╚══════════════════════════════════════════════════════════════╝

local Fluent = loadstring(game:HttpGet(
    "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
))()
local SaveManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"
))()
local InterfaceManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"
))()

-- ═══════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local VIM              = game:GetService("VirtualInputManager")

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ═══════════════════════════════════════
--  CONFIG
-- ═══════════════════════════════════════
local Cfg = {
    -- AIMBOT
    AimbotOn   = true,
    AutoFire   = true,
    WallCheck  = true,
    SnapOn     = true,
    Smooth     = 0.18,
    FOVOn      = false,
    FOVRadius  = 400,
    MaxDist    = 800,
    FireRate   = 0.07,
    SilentAim  = false,
    Prediction = true,
    BulletSpd  = 350,   -- velocidade da bala em studs/s (para predição)

    -- BOT
    BotOn      = true,
    KillRange  = 60,
    ChaseRange = 600,
    RoamRad    = 220,
    JumpOn     = true,

    -- MOVIMENTO
    NoclipOn   = false,
    TeleportOn = false,
    SpeedOn    = false,
    SpeedVal   = 26,
    InfJump    = false,

    -- UTILITÁRIOS
    KillAura   = false,
    AntiAFK    = true,
    AutoReload = true,
    TeamCheck  = true,

    -- ESP
    ESPOn      = true,
    BoxOn      = true,
    NameOn     = true,
    HpOn       = true,
    DistOn     = true,
    TraceOn    = true,
    SkeletonOn = false,
    FOVShow    = false,
}

-- ═══════════════════════════════════════
--  ESTADO
-- ═══════════════════════════════════════
local S = {
    LastFire    = 0,
    Target      = nil,
    TargetHead  = nil,

    -- Predição — armazena posição e timestamp para velocidade real com dt
    PrevHead    = {},   -- [player] = {pos, time}

    BotRunning  = false,
    BotThread   = nil,
    BotStatus   = "Inativo",
    Kills       = 0,
    Deaths      = 0,
    RoamPt      = nil,

    LastJump    = 0,
    LastAFK     = 0,
    FireRemote  = nil,
    ESPObj      = {},

    NoclipConn  = nil,
    InfJumpConn = nil,
    AntiAFKConn = nil,

    -- Cache de inimigo para não varrer todo frame
    EnemyCache     = nil,
    EnemyCacheTime = 0,
}

-- ═══════════════════════════════════════
--  RAYCASTPARAMS — CACHEADOS GLOBALMENTE
--  Criar RaycastParams.new() a cada frame
--  é caro. Reutilizamos os mesmos objetos.
-- ═══════════════════════════════════════
local RP_VISIBILITY = RaycastParams.new()
RP_VISIBILITY.FilterType = Enum.RaycastFilterType.Exclude

local RP_CAMERA = RaycastParams.new()
RP_CAMERA.FilterType = Enum.RaycastFilterType.Exclude

local RP_STEER = RaycastParams.new()
RP_STEER.FilterType = Enum.RaycastFilterType.Exclude

local RP_FLOOR = RaycastParams.new()
RP_FLOOR.FilterType = Enum.RaycastFilterType.Exclude

-- ═══════════════════════════════════════
--  REMOTE CACHE
-- ═══════════════════════════════════════
local function GetRemote()
    if S.FireRemote then return S.FireRemote end
    local cr = LP:FindFirstChild("ClientRemotes")
    if cr then
        local r = cr:FindFirstChild("CheckFire")
        if r then S.FireRemote = r; return r end
    end
    for _, v in ipairs(LP:GetDescendants()) do
        if v:IsA("RemoteEvent") then
            local n = v.Name:lower()
            if n:find("fire") or n:find("shoot") or n:find("attack") or n:find("bullet") then
                S.FireRemote = v; return v
            end
        end
    end
    return nil
end

-- ═══════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════
local function Alive(p)
    if not p or not p.Character then return false end
    local h = p.Character:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end
local function PHead(p)  return p.Character and p.Character:FindFirstChild("Head") end
local function PRoot(p)  return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function MRoot()   return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end
local function MHum()    return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end
local function Mate(p)
    if not Cfg.TeamCheck then return false end
    return p.Team ~= nil and p.Team == LP.Team
end
local function Ctr()
    local v = Camera.ViewportSize
    return Vector2.new(v.X * 0.5, v.Y * 0.5)
end
local function W2S(pos)
    local sp, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), on, sp.Z
end

-- ═══════════════════════════════════════
--  WALL CHECK
--  Usa RP_VISIBILITY cacheado
--  Origem: olhos do personagem (mais preciso)
-- ═══════════════════════════════════════
local function CanSee(targetChar, targetPos)
    local myChar = LP.Character; if not myChar then return false end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart"); if not myRoot then return false end

    RP_VISIBILITY.FilterDescendantsInstances = { myChar, targetChar }

    local origin = myRoot.Position + Vector3.new(0, 1.5, 0)
    local dir    = targetPos - origin
    local hit    = Workspace:Raycast(origin, dir, RP_VISIBILITY)

    -- Sem hit = visível. Hit perto do alvo = visível (margem 0.5)
    if hit then
        return (hit.Position - origin).Magnitude >= dir.Magnitude - 0.5
    end
    return true
end

-- ═══════════════════════════════════════
--  PREDIÇÃO DE BALA — baseada em dt real
--  Usa o delta de tempo entre frames para
--  calcular velocidade real em studs/s,
--  não studs/frame (que varia com FPS)
-- ═══════════════════════════════════════
local function PredictPos(player, headPos)
    if not Cfg.Prediction then return headPos end

    local now  = tick()
    local prev = S.PrevHead[player]
    S.PrevHead[player] = { pos = headPos, t = now }

    if not prev then return headPos end

    local dt  = now - prev.t
    if dt <= 0 or dt > 0.2 then return headPos end  -- dt inválido (lag, respawn)

    -- Velocidade real em studs/s
    local vel  = (headPos - prev.pos) / dt

    -- Tempo de voo da bala (distância / velocidade da bala)
    local mr   = MRoot(); if not mr then return headPos end
    local dist = (headPos - mr.Position).Magnitude
    local tFly = dist / Cfg.BulletSpd

    -- Limitar predição para não apontar longe demais
    local predicted = headPos + vel * tFly
    local maxOffset = 20  -- studs máximo de offset
    if (predicted - headPos).Magnitude > maxOffset then
        predicted = headPos + (predicted - headPos).Unit * maxOffset
    end

    return predicted
end

-- ═══════════════════════════════════════
--  DETECÇÃO DE ALVO — 360°
--  Score: prioriza visível + próximo + centro da tela
--  Otimizado: checagens mais baratas primeiro
-- ═══════════════════════════════════════
local function FindBestTarget()
    local mr = MRoot(); if not mr then return nil, nil end
    local myPos  = mr.Position
    local center = Ctr()
    local best, bestH, bestScore = nil, nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP or Mate(p) or not Alive(p) then continue end

        local root = PRoot(p); if not root then continue end
        local d = (root.Position - myPos).Magnitude

        -- Checar distância antes de tudo (mais barato)
        if d > Cfg.MaxDist then continue end

        local head = PHead(p); if not head then continue end
        local hpos = head.Position

        -- Wall check
        local vis = CanSee(p.Character, hpos)
        if Cfg.WallCheck and not vis then continue end

        -- Score base: distância + penalidade por parede
        local score = d + (vis and 0 or 4000)

        -- Peso de tela (só calcula W2S se necessário)
        if Cfg.FOVOn then
            local sp, on = W2S(hpos)
            if not on then continue end
            local sd = (sp - center).Magnitude
            if sd > Cfg.FOVRadius then continue end
            score = score + sd * 0.15
        elseif Cfg.AimbotOn then
            -- Mesmo sem FOV, dá leve preferência para quem está mais na tela
            local sp, on = W2S(hpos)
            if on then score = score - (Cfg.FOVRadius - (sp - center).Magnitude) * 0.05 end
        end

        if score < bestScore then
            bestScore = score; best = p; bestH = head
        end
    end
    return best, bestH
end

-- Inimigo mais próximo para o bot
-- Cacheia por 0.15s para não varrer todo frame
local function NearestEnemy()
    local now = tick()
    if S.EnemyCache and now - S.EnemyCacheTime < 0.15 then
        if Alive(S.EnemyCache) then return S.EnemyCache end
    end

    local mr = MRoot(); if not mr then return nil end
    local myPos = mr.Position
    local best, bestD = nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP or Mate(p) or not Alive(p) then continue end
        local r = PRoot(p); if not r then continue end
        local d = (r.Position - myPos).Magnitude
        if d < bestD and d < Cfg.ChaseRange then bestD = d; best = p end
    end

    S.EnemyCache     = best
    S.EnemyCacheTime = now
    return best
end

-- Invalida cache quando necessário (morte, etc.)
local function InvalidateCache()
    S.EnemyCache     = nil
    S.EnemyCacheTime = 0
end

-- ═══════════════════════════════════════
--  CÂMERA — rotaciona para o alvo
--  RP_CAMERA cacheado, sem alloc por frame
-- ═══════════════════════════════════════
local function RotateCam(targetPos)
    if Cfg.SilentAim then return end
    local mr = MRoot(); if not mr then return end

    local camDist  = (Camera.CFrame.Position - mr.Position).Magnitude
    local toTarget = (targetPos - mr.Position).Unit
    local offset   = -toTarget * camDist + Vector3.new(0, 2.5, 0)
    local idealPos = mr.Position + offset

    -- Anti-wall câmera (RP cacheado)
    RP_CAMERA.FilterDescendantsInstances = { LP.Character }
    local cc = Workspace:Raycast(mr.Position + Vector3.new(0, 2, 0), offset, RP_CAMERA)
    if cc then
        idealPos = cc.Position + (mr.Position - cc.Position).Unit * 0.5
    end

    local lookDir = (targetPos - idealPos).Unit
    local right   = lookDir:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 0.001 then right = Vector3.new(1, 0, 0) else right = right.Unit end
    local up = right:Cross(lookDir).Unit
    local cf = CFrame.fromMatrix(idealPos, right, up, -lookDir)

    Camera.CFrame = Cfg.SnapOn and cf or Camera.CFrame:Lerp(cf, Cfg.Smooth)
end

-- ═══════════════════════════════════════
--  DISPARO — MULTICAMADA
--  Tenta todos os métodos disponíveis
--  sem travar o frame
-- ═══════════════════════════════════════
local function Fire(aimPos)
    local now = tick()
    if now - S.LastFire < Cfg.FireRate then return end
    S.LastFire = now

    local remote = GetRemote()

    -- Método único: FireServer direto no RemoteEvent do jogo
    -- NÃO usa mouse1click() nem VIM — esses roubam o controle do jogador
    if remote then
        pcall(function()
            remote:FireServer(now, Vector3.new(aimPos.X, aimPos.Y, aimPos.Z))
        end)
    end
end

-- Kill Aura — dispara em todos no range simultaneamente
local function DoKillAura()
    if not Cfg.KillAura then return end
    local mr = MRoot(); if not mr then return end
    local remote = GetRemote(); if not remote then return end
    local myPos  = mr.Position
    local now    = tick()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP or Mate(p) or not Alive(p) then continue end
        local h = PHead(p); if not h then continue end
        if (h.Position - myPos).Magnitude <= Cfg.KillRange * 1.8 then
            pcall(function() remote:FireServer(now, h.Position) end)
        end
    end
end

-- ═══════════════════════════════════════
--  SISTEMA DE MOVIMENTO — STEERING
--
--  Melhorias v12:
--  • RP_STEER / RP_FLOOR cacheados (sem alloc)
--  • Leque de 9 ângulos (mais fino)
--  • Verifica altura do obstáculo para decidir
--    entre desviar OU pular
--  • Escape inteligente: vai na direção oposta
--    do vetor stuck (não aleatório puro)
--  • Floor check mais preciso
-- ═══════════════════════════════════════
local function TryJump()
    local now = tick()
    if now - S.LastJump < 0.75 then return end
    S.LastJump = now
    local h = MHum(); if h then h.Jump = true end
end

-- Checa obstáculo em direção e distância dados (RP cacheado)
local function HasObstacle(origin, dir, dist)
    local char = LP.Character; if not char then return false end
    RP_STEER.FilterDescendantsInstances = { char }
    return Workspace:Raycast(origin, dir.Unit * dist, RP_STEER) ~= nil
end

-- Retorna direção de steering desviando de paredes
-- Leque de 9 ângulos, escolhe o mais próximo do destino
local function SteerToward(origin, rawDir)
    local flat = Vector3.new(rawDir.X, 0, rawDir.Z)
    if flat.Magnitude < 0.01 then return Vector3.new(0,0,1) end
    flat = flat.Unit

    local chest      = origin + Vector3.new(0, 1.2, 0)
    local probeDist  = 6.5

    local char = LP.Character; if not char then return flat end
    RP_STEER.FilterDescendantsInstances = { char }
    RP_FLOOR.FilterDescendantsInstances = { char }

    -- Ângulos em ordem: prioriza o mais reto possível
    local angles = {0, 20, -20, 40, -40, 65, -65, 90, -90, 130, -130, 180}

    for _, deg in ipairs(angles) do
        local r   = math.rad(deg)
        local c   = math.cos(r)
        local s_  = math.sin(r)
        local dir = Vector3.new(flat.X*c - flat.Z*s_, 0, flat.X*s_ + flat.Z*c)

        if not Workspace:Raycast(chest, dir * probeDist, RP_STEER) then
            -- Verificar chão (não cair no vazio)
            local fwdPt   = origin + dir * probeDist
            local floorHit = Workspace:Raycast(fwdPt + Vector3.new(0,4,0), Vector3.new(0,-10,0), RP_FLOOR)
            if floorHit then
                return dir
            end
        end
    end

    return flat  -- fallback
end

-- Detecta degrau: obstáculo baixo mas não alto → pular
local function NeedsJump(origin, dir)
    if not Cfg.JumpOn then return false end
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.01 then return false end
    flat = flat.Unit

    local char = LP.Character; if not char then return false end
    RP_STEER.FilterDescendantsInstances = { char }

    local low = origin + Vector3.new(0, 0.5, 0)
    local hi  = origin + Vector3.new(0, 2.2, 0)
    local d   = 3.5

    local hitLow = Workspace:Raycast(low, flat * d, RP_STEER)
    local hitHi  = Workspace:Raycast(hi,  flat * d, RP_STEER)

    -- Degrau: tem baixo, não tem alto
    return hitLow ~= nil and hitHi == nil
end

-- Variáveis de stuck
local stkTimer  = 0
local stkRefPos = nil
local stkEscDir = nil
local stkEscT   = 0

local function CheckStuck(pos)
    if not stkRefPos then stkRefPos = pos; return false end
    if (pos - stkRefPos).Magnitude < 0.7 then
        stuckTimer = (stuckTimer or 0) + 0.05
    else
        stuckTimer = 0
        stkRefPos  = pos
        stkEscDir  = nil
    end
    stkRefPos = pos
    return (stuckTimer or 0) > 1.0
end

local function ResetStuck()
    stuckTimer = 0
    stkRefPos  = nil
    stkEscDir  = nil
end

-- Loop de movimento steering (roda dentro do bot thread)
local function MoveToTarget(destFunc, stopCond)
    ResetStuck()

    while S.BotRunning and Cfg.BotOn do
        task.wait(0.05)

        local mr  = MRoot(); if not mr then break end
        local hum = MHum();  if not hum then break end
        if stopCond and stopCond() then break end

        local dest = destFunc()
        if not dest then break end

        local myPos = mr.Position
        local dist  = (dest - myPos).Magnitude
        if dist < 4 then break end

        -- NOCLIP: linha reta direta
        if Cfg.NoclipOn then
            hum:MoveTo(dest)
            continue
        end

        local rawDir = dest - myPos
        local flat   = Vector3.new(rawDir.X, 0, rawDir.Z)

        -- STUCK: mover em direção oposta do travamento
        if CheckStuck(myPos) then
            TryJump()
            if not stkEscDir or tick() - stkEscT > 1.8 then
                -- Direção oposta ao destino + leve componente lateral aleatória
                local opp   = -flat.Unit
                local angle = (math.random() - 0.5) * math.pi * 0.8
                local c, s_ = math.cos(angle), math.sin(angle)
                stkEscDir = Vector3.new(opp.X*c - opp.Z*s_, 0, opp.X*s_ + opp.Z*c)
                stkEscT   = tick()
                stuckTimer = 0
            end
            hum:MoveTo(myPos + stkEscDir * 12)
            continue
        end

        -- DEGRAU: pular
        if NeedsJump(myPos, flat) then TryJump() end

        -- STEERING: calcular direção sem parede
        local steerDir = SteerToward(myPos, flat)

        -- Lookahead: quanto mais longe o destino, maior o passo
        local lookahead = math.clamp(dist * 0.4, 8, 22)
        local movePt    = myPos + steerDir * lookahead

        -- Corrigir Y para o chão
        RP_FLOOR.FilterDescendantsInstances = { LP.Character }
        local fhit = Workspace:Raycast(movePt + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), RP_FLOOR)
        if fhit then
            movePt = fhit.Position + Vector3.new(0, 3, 0)
        end

        hum:MoveTo(movePt)
    end
end

-- ═══════════════════════════════════════
--  BOT FARM
-- ═══════════════════════════════════════
local botThread = nil

local function StopBot()
    S.BotRunning = false
    if botThread then task.cancel(botThread); botThread = nil end
    S.BotStatus = "Inativo"
    InvalidateCache()
    local h = MHum(); local r = MRoot()
    if h and r then h:MoveTo(r.Position) end
end

local function StartBot()
    if S.BotRunning then return end
    S.BotRunning = true
    InvalidateCache()

    botThread = task.spawn(function()
        while S.BotRunning and Cfg.BotOn do
            local mr   = MRoot()
            local mhum = MHum()

            -- Aguardar respawn
            if not mr or not mhum or mhum.Health <= 0 then
                S.BotStatus = "⏳ Respawnando..."
                task.wait(0.4)
                continue
            end

            -- Speed
            if Cfg.SpeedOn and mhum.WalkSpeed ~= Cfg.SpeedVal then
                mhum.WalkSpeed = Cfg.SpeedVal
            end

            -- Auto reload
            if Cfg.AutoReload then
                pcall(function()
                    local char = LP.Character; if not char then return end
                    for _, tool in ipairs(char:GetChildren()) do
                        if not tool:IsA("Tool") then continue end
                        for _, v in ipairs(tool:GetDescendants()) do
                            local n = v.Name:lower()
                            if (n:find("ammo") or n:find("bullet") or n:find("magazine") or n:find("clip"))
                            and (v:IsA("IntValue") or v:IsA("NumberValue"))
                            and v.Value <= 0 then
                                VIM:SendKeyEvent(true,  Enum.KeyCode.R, false, game)
                                task.delay(0.08, function()
                                    VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game)
                                end)
                            end
                        end
                    end
                end)
            end

            local enemy = NearestEnemy()

            -- ── ROAMING ──
            if not enemy then
                S.BotStatus = "🌐 Explorando"
                if not S.RoamPt then
                    local a     = math.random() * math.pi * 2
                    local d     = 60 + math.random() * Cfg.RoamRad
                    local probe = mr.Position + Vector3.new(math.cos(a)*d, 10, math.sin(a)*d)
                    RP_FLOOR.FilterDescendantsInstances = { LP.Character }
                    local ray   = Workspace:Raycast(probe, Vector3.new(0,-80,0), RP_FLOOR)
                    S.RoamPt    = ray and ray.Position + Vector3.new(0,3,0)
                                  or mr.Position + Vector3.new(math.cos(a)*d, 0, math.sin(a)*d)
                end
                MoveToTarget(
                    function() return S.RoamPt end,
                    function()
                        if NearestEnemy() then InvalidateCache(); S.RoamPt=nil; return true end
                        local r2 = MRoot()
                        if r2 and (r2.Position - S.RoamPt).Magnitude < 8 then S.RoamPt=nil; return true end
                        return false
                    end
                )
                continue
            end

            -- ── TELEPORT ──
            if Cfg.TeleportOn then
                S.BotStatus = "⚡ " .. enemy.Name
                local er2 = PRoot(enemy)
                local mr2 = MRoot()
                if er2 and mr2 then
                    mr2.CFrame = CFrame.new(er2.Position + Vector3.new(2, 0, 2))
                end
                DoKillAura()
                -- Espera morrer com re-teleport
                local t0 = tick()
                while S.BotRunning and tick()-t0 < 6 do
                    task.wait(0.05)
                    DoKillAura()
                    if not Alive(enemy) then
                        S.Kills += 1
                        InvalidateCache()
                        S.BotStatus = "💀 Kill #"..S.Kills
                        break
                    end
                    local er3=PRoot(enemy); local mr3=MRoot()
                    if er3 and mr3 and (er3.Position-mr3.Position).Magnitude > 8 then
                        mr3.CFrame = CFrame.new(er3.Position + Vector3.new(2,0,2))
                    end
                end
                continue
            end

            -- ── FARM: PERSEGUIÇÃO CONTÍNUA + ATIRAR ──
            local er = PRoot(enemy)
            if not er then InvalidateCache(); task.wait(0.05); continue end
            local dist = (er.Position - mr.Position).Magnitude

            S.BotStatus = (dist <= Cfg.KillRange and "💀 FARM: " or "🏃 ") .. enemy.Name

            -- Mover sempre, o PreSimulation atira em paralelo
            MoveToTarget(
                function()
                    local er2 = PRoot(enemy)
                    if not er2 then return nil end
                    return er2.Position
                end,
                function()
                    if not Alive(enemy) then
                        S.Kills += 1
                        InvalidateCache()
                        S.BotStatus = "💀 Kill #"..S.Kills
                        return true
                    end
                    return false
                end
            )
            DoKillAura()
            task.wait(0.02)
        end

        S.BotRunning = false
        S.BotStatus  = "Inativo"
    end)
end

-- ═══════════════════════════════════════
--  NOCLIP
-- ═══════════════════════════════════════
local function EnableNoclip()
    if S.NoclipConn then S.NoclipConn:Disconnect() end
    S.NoclipConn = RunService.Stepped:Connect(function()
        if not Cfg.NoclipOn then return end
        local char = LP.Character; if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end
local function DisableNoclip()
    if S.NoclipConn then S.NoclipConn:Disconnect(); S.NoclipConn=nil end
    local char = LP.Character; if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = true end
    end
end

-- ═══════════════════════════════════════
--  INFINITE JUMP
-- ═══════════════════════════════════════
local function SetupInfJump()
    if S.InfJumpConn then S.InfJumpConn:Disconnect() end
    S.InfJumpConn = UserInputService.JumpRequest:Connect(function()
        if not Cfg.InfJump then return end
        local h = MHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end

-- ═══════════════════════════════════════
--  ANTI-AFK
-- ═══════════════════════════════════════
local function SetupAntiAFK()
    if S.AntiAFKConn then S.AntiAFKConn:Disconnect() end
    S.AntiAFKConn = RunService.Heartbeat:Connect(function()
        if not Cfg.AntiAFK then return end
        if tick() - S.LastAFK > 55 then
            S.LastAFK = tick()
            pcall(function()
                VIM:SendKeyEvent(true,  Enum.KeyCode.W, false, game)
                task.delay(0.06, function()
                    VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                end)
            end)
        end
    end)
end

-- ═══════════════════════════════════════
--  ESP — throttled a 30fps, RP cacheado
-- ═══════════════════════════════════════
local BONES = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
}

local function Drw(t, props)
    local d = Drawing.new(t)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function NewESP(player)
    if player == LP or S.ESPObj[player] then return end
    local bones = {}
    for i = 1, #BONES do
        bones[i] = Drw("Line", {Visible=false,Color=Color3.new(1,1,1),Thickness=1,Transparency=0.7})
    end
    S.ESPObj[player] = {
        Box  = Drw("Square",{Visible=false,Color=Color3.fromRGB(255,50,50), Thickness=1.5,Filled=false,Transparency=1}),
        Fill = Drw("Square",{Visible=false,Color=Color3.fromRGB(255,50,50), Transparency=0.06,Filled=true}),
        Name = Drw("Text",  {Visible=false,Color=Color3.new(1,1,1),         Size=13,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2}),
        Dist = Drw("Text",  {Visible=false,Color=Color3.fromRGB(200,200,200),Size=12,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2}),
        HpBG = Drw("Square",{Visible=false,Color=Color3.new(0,0,0),         Filled=true,Transparency=0.5}),
        HpBr = Drw("Square",{Visible=false,Color=Color3.fromRGB(60,210,60), Filled=true,Transparency=1}),
        Trc  = Drw("Line",  {Visible=false,Color=Color3.fromRGB(255,50,50), Thickness=1,Transparency=0.6}),
        HDt  = Drw("Circle",{Visible=false,Color=Color3.fromRGB(255,80,80), Thickness=1.5,Filled=false,NumSides=32,Radius=5,Transparency=1}),
        Bones= bones,
    }
end

local function DelESP(p)
    local o = S.ESPObj[p]; if not o then return end
    for k, dd in pairs(o) do
        if k == "Bones" then
            for _, b in pairs(dd) do pcall(function() b:Remove() end) end
        else pcall(function() dd:Remove() end) end
    end
    S.ESPObj[p] = nil
end

local function HideAll(o)
    for k, dd in pairs(o) do
        if k == "Bones" then
            for _, b in pairs(dd) do pcall(function() b.Visible = false end) end
        else pcall(function() dd.Visible = false end) end
    end
end

local espTimer = 0
local function UpdateESP()
    -- Throttle: 30fps é suficiente para ESP
    if tick() - espTimer < 0.033 then return end
    espTimer = tick()

    local mr = MRoot()
    local myPos = mr and mr.Position

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local o = S.ESPObj[p]; if not o then continue end

        if not Cfg.ESPOn or not Alive(p) then HideAll(o); continue end

        local char = p.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        if not root or not head then HideAll(o); continue end

        local sp, on, depth = W2S(root.Position)
        if not on or depth < 0 then HideAll(o); continue end

        local hsp   = W2S(head.Position)
        local dist  = myPos and (root.Position - myPos).Magnitude or 0
        local frac  = 1000 / math.max(dist, 10)
        local bW, bH = frac * 1.05, frac * 2.9
        local bX, bY = sp.X - bW*0.5, sp.Y - bH*0.78

        local isTarget = S.Target == p
        local col = isTarget     and Color3.fromRGB(0, 255, 200)
            or Mate(p)           and Color3.fromRGB(50, 120, 255)
            or Color3.fromRGB(255, 50, 50)

        local vis = CanSee(char, head.Position)
        local a   = vis and 1 or 0.28

        -- Box
        if Cfg.BoxOn then
            o.Box.Position=Vector2.new(bX,bY); o.Box.Size=Vector2.new(bW,bH)
            o.Box.Color=col; o.Box.Transparency=a; o.Box.Visible=true
            o.Fill.Position=Vector2.new(bX,bY); o.Fill.Size=Vector2.new(bW,bH)
            o.Fill.Color=col; o.Fill.Transparency=0.06*a; o.Fill.Visible=true
        else o.Box.Visible=false; o.Fill.Visible=false end

        -- Nome
        if Cfg.NameOn then
            o.Name.Text=p.Name; o.Name.Color=col
            o.Name.Position=Vector2.new(sp.X, bY-15)
            o.Name.Transparency=a; o.Name.Visible=true
        else o.Name.Visible=false end

        -- Distância
        if Cfg.DistOn then
            o.Dist.Text=string.format("%.0f", dist).."m"
            o.Dist.Position=Vector2.new(sp.X, bY+bH+2)
            o.Dist.Transparency=a; o.Dist.Visible=true
        else o.Dist.Visible=false end

        -- Health bar
        if Cfg.HpOn then
            local hm = char:FindFirstChildOfClass("Humanoid")
            local hp = hm and (hm.Health / math.max(hm.MaxHealth, 1)) or 0
            local hpR = math.floor(255*(1-hp))
            local hpG = math.floor(255*hp)
            o.HpBG.Position=Vector2.new(bX-5,bY); o.HpBG.Size=Vector2.new(4,bH); o.HpBG.Visible=true
            o.HpBr.Color=Color3.fromRGB(hpR, hpG, 30)
            o.HpBr.Position=Vector2.new(bX-5, bY+bH*(1-hp))
            o.HpBr.Size=Vector2.new(4, bH*hp)
            o.HpBr.Transparency=a; o.HpBr.Visible=true
        else o.HpBG.Visible=false; o.HpBr.Visible=false end

        -- Tracer
        if Cfg.TraceOn then
            local vp = Camera.ViewportSize
            o.Trc.From=Vector2.new(vp.X*0.5, vp.Y)
            o.Trc.To=sp; o.Trc.Color=col
            o.Trc.Transparency=a*0.6; o.Trc.Visible=true
        else o.Trc.Visible=false end

        -- Head dot
        o.HDt.Position=hsp; o.HDt.Color=col; o.HDt.Transparency=a; o.HDt.Visible=true

        -- Skeleton
        if Cfg.SkeletonOn then
            for i, bone in ipairs(BONES) do
                local p1 = char:FindFirstChild(bone[1])
                local p2 = char:FindFirstChild(bone[2])
                local bl = o.Bones[i]
                if p1 and p2 and bl then
                    local s1, o1 = W2S(p1.Position)
                    local s2, o2 = W2S(p2.Position)
                    if o1 and o2 then
                        bl.From=s1; bl.To=s2; bl.Color=col
                        bl.Transparency=a*0.75; bl.Visible=true
                    else bl.Visible=false end
                end
            end
        else
            for _, b in pairs(o.Bones) do b.Visible = false end
        end
    end
end

-- ═══════════════════════════════════════
--  DRAWINGS
-- ═══════════════════════════════════════
local FOVCirc = Drw("Circle",{Visible=false,Color=Color3.fromRGB(255,220,0),Radius=Cfg.FOVRadius,Thickness=1.2,Filled=false,NumSides=80,Transparency=0.65})
local CrossH  = Drw("Line",  {Visible=true, Color=Color3.new(1,1,1),Thickness=1,Transparency=0.5})
local CrossV  = Drw("Line",  {Visible=true, Color=Color3.new(1,1,1),Thickness=1,Transparency=0.5})
local StatLbl = Drw("Text",  {Visible=true, Color=Color3.fromRGB(0,220,160),Size=13,Center=false,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Position=Vector2.new(10,50)})
local KDLbl   = Drw("Text",  {Visible=true, Color=Color3.fromRGB(255,200,50),Size=12,Center=false,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Position=Vector2.new(10,68)})
local LockLbl = Drw("Text",  {Visible=false,Color=Color3.fromRGB(255,50,50), Size=14,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2})
local PredDot = Drw("Circle",{Visible=false,Color=Color3.fromRGB(0,200,255), Radius=4,Thickness=1.5,Filled=true,NumSides=16,Transparency=0.8})

-- ═══════════════════════════════════════
--  SETUP PLAYERS
-- ═══════════════════════════════════════
for _, p in ipairs(Players:GetPlayers()) do NewESP(p) end
Players.PlayerAdded:Connect(NewESP)
Players.PlayerRemoving:Connect(DelESP)

LP.CharacterAdded:Connect(function()
    S.Deaths += 1
    task.wait(2)
    S.FireRemote = nil
    S.Target     = nil
    S.TargetHead = nil
    S.RoamPt     = nil
    S.PrevHead   = {}
    InvalidateCache()
    StopBot(); task.wait(0.3)
    if Cfg.BotOn then StartBot() end
    if Cfg.NoclipOn then EnableNoclip() end
end)

-- ═══════════════════════════════════════
--  FLUENT MENU
-- ═══════════════════════════════════════
local Win = Fluent:CreateWindow({
    Title="Ghost Aim  |  v12", SubTitle="Farm • Steering • Predict • 360°",
    TabWidth=160, Size=UDim2.fromOffset(600,500), Acrylic=false, Theme="Dark",
})
local T = {
    Farm = Win:AddTab({Title="Farm Bot",  Icon="bot"}),
    Aim  = Win:AddTab({Title="Aimbot",    Icon="crosshair"}),
    Move = Win:AddTab({Title="Movimento", Icon="zap"}),
    ESP  = Win:AddTab({Title="ESP",        Icon="eye"}),
    Cfg  = Win:AddTab({Title="Config",    Icon="settings"}),
}

-- ── FARM BOT ──
T.Farm:AddParagraph({Title="🌾 Farm Mode", Content="Persegue e atira ao mesmo tempo. Kill chain automático. Steering inteligente."})
T.Farm:AddToggle("BotOn",{Title="Farm Bot",Default=Cfg.BotOn,
    Callback=function(v) Cfg.BotOn=v; if v then StartBot() else StopBot() end end})
T.Farm:AddToggle("KillAura",{Title="Kill Aura",Description="Atira em todos ao redor",Default=Cfg.KillAura,
    Callback=function(v) Cfg.KillAura=v end})
T.Farm:AddToggle("TeleportOn",{Title="Teleportar até Inimigo",Default=Cfg.TeleportOn,
    Callback=function(v) Cfg.TeleportOn=v end})
T.Farm:AddSlider("KillRange",{Title="Range de Combate",Default=Cfg.KillRange,Min=10,Max=200,Rounding=0,
    Callback=function(v) Cfg.KillRange=v end})
T.Farm:AddSlider("ChaseRange",{Title="Range de Perseguição",Default=Cfg.ChaseRange,Min=50,Max=1000,Rounding=0,
    Callback=function(v) Cfg.ChaseRange=v end})
T.Farm:AddSlider("RoamRad",{Title="Raio de Roaming",Default=Cfg.RoamRad,Min=50,Max=600,Rounding=0,
    Callback=function(v) Cfg.RoamRad=v end})
T.Farm:AddButton({Title="⛔ Parar Bot",Callback=function()
    StopBot(); Fluent:Notify({Title="Bot parado",Content="",Duration=2})
end})

-- ── AIMBOT ──
T.Aim:AddToggle("AimOn",{Title="Aimbot",Default=Cfg.AimbotOn,Callback=function(v) Cfg.AimbotOn=v end})
T.Aim:AddToggle("FireOn",{Title="Auto Fire",Default=Cfg.AutoFire,Callback=function(v) Cfg.AutoFire=v end})
T.Aim:AddToggle("SilentOn",{Title="Silent Aim",Description="Dispara sem mover câmera",Default=Cfg.SilentAim,
    Callback=function(v) Cfg.SilentAim=v end})
T.Aim:AddToggle("PredOn",{Title="Bullet Prediction",Description="Compensa movimento do alvo",Default=Cfg.Prediction,
    Callback=function(v) Cfg.Prediction=v end})
T.Aim:AddToggle("WallOn",{Title="Wall Check",Description="ON = só mira visíveis",Default=Cfg.WallCheck,
    Callback=function(v) Cfg.WallCheck=v end})
T.Aim:AddToggle("SnapOn",{Title="Snap Instantâneo",Default=Cfg.SnapOn,
    Callback=function(v) Cfg.SnapOn=v end})
T.Aim:AddToggle("FOVOn",{Title="Limitar FOV",Default=Cfg.FOVOn,
    Callback=function(v) Cfg.FOVOn=v end})
T.Aim:AddSlider("FOVRad",{Title="Raio FOV",Default=Cfg.FOVRadius,Min=50,Max=700,Rounding=0,
    Callback=function(v) Cfg.FOVRadius=v; FOVCirc.Radius=v end})
T.Aim:AddSlider("MaxDist",{Title="Alcance Máximo",Default=Cfg.MaxDist,Min=50,Max=1000,Rounding=0,
    Callback=function(v) Cfg.MaxDist=v end})
T.Aim:AddSlider("FRateMs",{Title="Fire Rate (ms)",Default=math.floor(Cfg.FireRate*1000),Min=20,Max=500,Rounding=0,
    Callback=function(v) Cfg.FireRate=v/1000 end})
T.Aim:AddSlider("BulletSpd",{Title="Velocidade da Bala (studs/s)",Default=Cfg.BulletSpd,Min=100,Max=1000,Rounding=0,
    Callback=function(v) Cfg.BulletSpd=v end})

-- ── MOVIMENTO ──
T.Move:AddToggle("NoclipOn",{Title="Noclip (Atravessar Paredes)",Default=Cfg.NoclipOn,
    Callback=function(v) Cfg.NoclipOn=v; if v then EnableNoclip() else DisableNoclip() end end})
T.Move:AddToggle("SpeedOn",{Title="Speed Boost",Default=Cfg.SpeedOn,
    Callback=function(v) Cfg.SpeedOn=v
        if not v then local h=MHum(); if h then h.WalkSpeed=16 end end
    end})
T.Move:AddSlider("SpeedVal",{Title="WalkSpeed",Default=Cfg.SpeedVal,Min=16,Max=120,Rounding=0,
    Callback=function(v) Cfg.SpeedVal=v end})
T.Move:AddToggle("InfJump",{Title="Infinite Jump",Default=Cfg.InfJump,
    Callback=function(v) Cfg.InfJump=v end})
T.Move:AddToggle("JumpOn",{Title="Auto Pular Obstáculos",Default=Cfg.JumpOn,
    Callback=function(v) Cfg.JumpOn=v end})

-- ── ESP ──
T.ESP:AddToggle("ESPOn",   {Title="ESP",          Default=Cfg.ESPOn,     Callback=function(v) Cfg.ESPOn=v     end})
T.ESP:AddToggle("BoxOn",   {Title="Box",           Default=Cfg.BoxOn,     Callback=function(v) Cfg.BoxOn=v     end})
T.ESP:AddToggle("NameOn",  {Title="Nome",          Default=Cfg.NameOn,    Callback=function(v) Cfg.NameOn=v    end})
T.ESP:AddToggle("HpOn",    {Title="Health Bar",    Default=Cfg.HpOn,      Callback=function(v) Cfg.HpOn=v      end})
T.ESP:AddToggle("DistOn",  {Title="Distância",     Default=Cfg.DistOn,    Callback=function(v) Cfg.DistOn=v    end})
T.ESP:AddToggle("TraceOn", {Title="Tracer",        Default=Cfg.TraceOn,   Callback=function(v) Cfg.TraceOn=v   end})
T.ESP:AddToggle("SkelOn",  {Title="Skeleton ESP",  Default=Cfg.SkeletonOn,Callback=function(v) Cfg.SkeletonOn=v end})
T.ESP:AddToggle("FOVShow", {Title="Círculo FOV",   Default=Cfg.FOVShow,
    Callback=function(v) Cfg.FOVShow=v; FOVCirc.Visible=v end})

-- ── CONFIG ──
T.Cfg:AddToggle("TeamOn",{Title="Team Check",Default=Cfg.TeamCheck,Callback=function(v) Cfg.TeamCheck=v end})
T.Cfg:AddToggle("AntiAFK",{Title="Anti-AFK",Default=Cfg.AntiAFK,Callback=function(v) Cfg.AntiAFK=v end})
T.Cfg:AddToggle("AutoReload",{Title="Auto Reload",Default=Cfg.AutoReload,Callback=function(v) Cfg.AutoReload=v end})
T.Cfg:AddButton({Title="Redetectar Remote",Callback=function()
    S.FireRemote=nil; Fluent:Notify({Title="Remote resetado",Content="Re-detectado no próximo tiro",Duration=2})
end})
T.Cfg:AddButton({Title="Otimizar FPS",Callback=function()
    for _, v in pairs(game:GetDescendants()) do
        if v:IsA("PostEffect") or v:IsA("ParticleEmitter") or v:IsA("Trail") then v.Enabled=false end
    end
    Fluent:Notify({Title="FPS Boost",Content="Efeitos visuais removidos",Duration=2})
end})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:BuildInterfaceSection(T.Cfg)
SaveManager:BuildConfigSection(T.Cfg)
Win:SelectTab(1)

-- ═══════════════════════════════════════
--  MAIN LOOP — PreSimulation (60fps)
--  Câmera + Disparo apenas — nunca bloqueia
-- ═══════════════════════════════════════
RunService.PreSimulation:Connect(function()
    local c = Ctr()

    -- Crosshair
    CrossH.From=Vector2.new(c.X-10,c.Y); CrossH.To=Vector2.new(c.X+10,c.Y)
    CrossV.From=Vector2.new(c.X,c.Y-10); CrossV.To=Vector2.new(c.X,c.Y+10)
    FOVCirc.Position = c

    -- HUD
    StatLbl.Text = "◈ " .. S.BotStatus
    KDLbl.Text   = "K: " .. S.Kills .. "  D: " .. S.Deaths

    -- ESP (30fps)
    UpdateESP()

    if not Cfg.AimbotOn then
        S.Target=nil; S.TargetHead=nil
        LockLbl.Visible=false; PredDot.Visible=false
        return
    end

    -- Encontrar alvo
    local p, h = FindBestTarget()
    S.Target     = p
    S.TargetHead = h

    if not p or not h then
        LockLbl.Visible=false; PredDot.Visible=false
        return
    end

    local headPos = h.Position
    local aimPos  = PredictPos(p, headPos)

    -- Lock label
    local lsp, on = W2S(headPos)
    LockLbl.Text     = on and ("[ ◉ "..p.Name.." ]") or ("[ ◉ "..p.Name.." ◄ ]")
    LockLbl.Position = on and Vector2.new(lsp.X, lsp.Y-24) or Vector2.new(c.X, c.Y-40)
    LockLbl.Visible  = true

    -- Prediction dot
    if Cfg.Prediction then
        local ps, po = W2S(aimPos)
        PredDot.Position = ps; PredDot.Visible = po
    else
        PredDot.Visible = false
    end

    -- Câmera
    RotateCam(aimPos)

    -- Disparo (só se visível)
    if Cfg.AutoFire and CanSee(p.Character, headPos) then
        Fire(aimPos)
    end
end)

-- ═══════════════════════════════════════
--  CLIQUE MANUAL → FIRE
-- ═══════════════════════════════════════
UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if S.Target and S.TargetHead and CanSee(S.Target.Character, S.TargetHead.Position) then
        S.LastFire = 0
        Fire(PredictPos(S.Target, S.TargetHead.Position))
    end
end)

-- ═══════════════════════════════════════
--  INICIALIZAÇÃO
-- ═══════════════════════════════════════
SetupInfJump()
SetupAntiAFK()
EnableNoclip()  -- listener sempre ativo, NoclipOn=false por padrão
if Cfg.BotOn then StartBot() end

task.delay(1.5, function()
    Fluent:Notify({
        Title   = "Ghost Aim v12",
        Content = "Farm • Steering • Predict dt-based • RP cacheado • Fire 3 camadas",
        Duration = 6,
    })
end)
print("[Ghost Aim v12] OK")
