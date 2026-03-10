--[[
╔══════════════════════════════════════════════════════════════╗
║           RONY MENU FREEMIUN v2  |  Flash Mouse Fire™        ║
║  ✅ AIMBOT CORRIGIDO — Câmera + Head Lock funcionando        ║
║  Predição dt-based • Steering v2 • ESP • Fluent UI           ║
║  🔪 SMART WEAPON SWAP • MELEE COMBAT • RELOAD SKIP           ║
║  🔥 AUTO FIRE V1 (mouse1click) + V2 (ByteNetReliable)        ║
║  ✅ SEM NOME HARDCODED — busca inimigo automático            ║
╚══════════════════════════════════════════════════════════════╝
--]]

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
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local VIM                = game:GetService("VirtualInputManager")

local LP     = Players.LocalPlayer
local Mouse  = LP:GetMouse()
local Camera = Workspace.CurrentCamera

-- ═══════════════════════════════════════
--  CONFIG
-- ═══════════════════════════════════════
local Cfg = {
    -- AIMBOT
    AimbotOn    = true,
    AutoFire    = true,
    AutoFireV1  = true,
    AutoFireV2  = true,
    WallCheck   = false,   -- ✅ CORRIGIDO: false por padrão (wallcheck bloqueava mira)
    SnapOn      = true,
    Smooth      = 0.25,    -- ✅ CORRIGIDO: valor mais suave para lerp funcionar
    FOVOn       = false,
    FOVRadius   = 400,
    MaxDist     = 800,
    FireRate    = 0.08,
    SilentAim   = false,
    Prediction  = true,
    BulletSpd   = 350,

    -- BOT INTELIGENTE
    BotOn       = true,
    SmartBot    = true,
    MeleeRange  = 25,
    RangedRange = 120,
    KillRange   = 60,
    ChaseRange  = 600,
    RoamRad     = 220,
    JumpOn      = true,

    -- TROCA DE ARMAS
    WeaponSwap  = true,
    MeleeSlot   = 3,
    RangeSlot1  = 1,
    RangeSlot2  = 2,
    SwapDelay   = 0.12,

    -- MOVIMENTO
    NoclipOn    = false,
    TeleportOn  = false,
    SpeedOn     = false,
    SpeedVal    = 26,
    InfJump     = false,

    -- UTILITÁRIOS
    KillAura    = false,
    AntiAFK     = true,
    AutoReload  = true,
    TeamCheck   = true,

    -- ESP
    ESPOn       = true,
    BoxOn       = true,
    NameOn      = true,
    HpOn        = true,
    DistOn      = true,
    TraceOn     = true,
    SkeletonOn  = false,
    FOVShow     = false,
}

-- ═══════════════════════════════════════
--  ESTADO
-- ═══════════════════════════════════════
local S = {
    LastFire         = 0,
    Target           = nil,
    TargetHead       = nil,
    PrevHead         = {},
    BotRunning       = false,
    BotThread        = nil,
    BotStatus        = "Inativo",
    Kills            = 0,
    Deaths           = 0,
    RoamPt           = nil,
    LastJump         = 0,
    LastAFK          = 0,
    ESPObj           = {},
    NoclipConn       = nil,
    InfJumpConn      = nil,
    AntiAFKConn      = nil,
    EnemyCache       = nil,
    EnemyCacheTime   = 0,
    FlashActive      = false,
    CurrentWeapon    = 1,
    LastWeaponSwap   = 0,
    LastMeleeSwap    = 0,
    WeaponInUse      = 1,
    LastRangedFire   = 0,
    LastMeleeFire    = 0,
    MouseFireEnabled = true,
}

-- ═══════════════════════════════════════
--  RAYCASTPARAMS
-- ═══════════════════════════════════════
local RP_VIS   = RaycastParams.new(); RP_VIS.FilterType   = Enum.RaycastFilterType.Exclude
local RP_CAM   = RaycastParams.new(); RP_CAM.FilterType   = Enum.RaycastFilterType.Exclude
local RP_STEER = RaycastParams.new(); RP_STEER.FilterType = Enum.RaycastFilterType.Exclude
local RP_FLOOR = RaycastParams.new(); RP_FLOOR.FilterType = Enum.RaycastFilterType.Exclude

-- ═══════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════
local function Alive(p)
    if not p or not p.Character then return false end
    local h = p.Character:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end
local function PHead(p)
    if not p or not p.Character then return nil end
    -- ✅ CORRIGIDO: tenta Head, depois HumanoidRootPart como fallback
    return p.Character:FindFirstChild("Head")
        or p.Character:FindFirstChild("HumanoidRootPart")
end
local function PRoot(p)
    if not p or not p.Character then return nil end
    return p.Character:FindFirstChild("HumanoidRootPart")
end
local function MRoot()
    return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
end
local function MHum()
    return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
end
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
--  WEAPON SYSTEM
-- ═══════════════════════════════════════
local function SwitchToWeapon(slot)
    local now = tick()
    if now - S.LastWeaponSwap < Cfg.SwapDelay then return false end
    S.LastWeaponSwap = now
    S.CurrentWeapon  = slot
    pcall(function()
        local keyCode = Enum.KeyCode[tostring(slot)]
        if keyCode then
            VIM:SendKeyEvent(true, keyCode, false, game)
            task.delay(0.04, function()
                pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end)
            end)
        end
    end)
    return true
end

local function GetCurrentTool()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Tool")
end

local function EquipWeapon(slot)
    SwitchToWeapon(slot)
    task.wait(0.12)
end

local function IsMeleeWeapon(tool)
    if not tool then return false end
    local name = tool.Name:lower()
    return name:find("knife") or name:find("faca") or name:find("melee")
        or name:find("sword") or name:find("espada") or name:find("dagger")
end

local function IsRangedWeapon(tool)
    if not tool then return false end
    local name = tool.Name:lower()
    return name:find("rifle") or name:find("pistol") or name:find("gun")
        or name:find("shotgun") or name:find("ar15") or name:find("revolver")
        or name:find("sniper")
end

-- ═══════════════════════════════════════
--  WALL CHECK
-- ═══════════════════════════════════════
local function CanSee(targetChar, targetPos)
    -- ✅ CORRIGIDO: retorna true se wallcheck desativado
    if not Cfg.WallCheck then return true end
    local myChar = LP.Character; if not myChar then return true end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart"); if not myRoot then return true end
    RP_VIS.FilterDescendantsInstances = { myChar, targetChar }
    local origin = myRoot.Position + Vector3.new(0, 1.5, 0)
    local dir    = targetPos - origin
    local hit    = Workspace:Raycast(origin, dir, RP_VIS)
    if hit then return (hit.Position - origin).Magnitude >= dir.Magnitude - 0.5 end
    return true
end

-- ═══════════════════════════════════════
--  PREDIÇÃO
-- ═══════════════════════════════════════
local function PredictPos(player, headPos)
    if not Cfg.Prediction then return headPos end
    local now  = tick()
    local prev = S.PrevHead[player]
    S.PrevHead[player] = { pos = headPos, t = now }
    if not prev then return headPos end
    local dt = now - prev.t
    if dt <= 0 or dt > 0.25 then return headPos end
    local vel   = (headPos - prev.pos) / dt
    local mr    = MRoot(); if not mr then return headPos end
    local dist  = (headPos - mr.Position).Magnitude
    local tFly  = dist / math.max(Cfg.BulletSpd, 1)
    local pred  = headPos + vel * tFly
    if (pred - headPos).Magnitude > 20 then
        pred = headPos + (pred - headPos).Unit * 20
    end
    return pred
end

-- ═══════════════════════════════════════
--  ✅ DETECÇÃO CORRIGIDA — FindAnyEnemy
--  Sem filtros desnecessários que bloqueavam alvos
-- ═══════════════════════════════════════
local function FindAnyEnemy()
    local mr = MRoot()
    if not mr then return nil, nil end
    local myPos  = mr.Position
    local center = Ctr()
    local best, bestHead, bestScore = nil, nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if Mate(p) then continue end
        if not Alive(p) then continue end

        local root = PRoot(p)
        if not root then continue end

        local dist = (root.Position - myPos).Magnitude
        if dist > Cfg.MaxDist then continue end

        -- ✅ CORRIGIDO: pega a cabeça corretamente
        local char = p.Character
        if not char then continue end

        local head = char:FindFirstChild("Head")
        if not head then
            -- fallback: usa torso ou root se não achar a cabeça
            head = char:FindFirstChild("UpperTorso")
                or char:FindFirstChild("Torso")
                or root
        end

        -- ✅ CORRIGIDO: wall check só se habilitado
        if Cfg.WallCheck and not CanSee(char, head.Position) then continue end

        -- ✅ CORRIGIDO: verifica se está na tela mas não bloqueia se estiver fora
        local sp, onScreen, depth = Camera:WorldToViewportPoint(head.Position)
        if depth < 0 then continue end  -- atrás da câmera, ignora

        local screenPos  = Vector2.new(sp.X, sp.Y)
        local screenDist = (screenPos - center).Magnitude

        -- FOV check (só bloqueia se FOV estiver ativo)
        if Cfg.FOVOn and screenDist > Cfg.FOVRadius then continue end

        -- Score: prioriza quem está mais no centro da tela
        local score = screenDist * 1.2 + dist * 0.3

        if score < bestScore then
            bestScore = score
            best      = p
            bestHead  = head
        end
    end

    return best, bestHead
end

-- ✅ CORRIGIDO: FindBestTarget unificado com FindAnyEnemy
-- Mantido separado apenas para compatibilidade com o loop principal
local function FindBestTarget()
    return FindAnyEnemy()
end

local function NearestEnemy()
    local now = tick()
    if S.EnemyCache and (now - S.EnemyCacheTime) < 0.15 then
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
    S.EnemyCache = best; S.EnemyCacheTime = now
    return best
end

local function InvalidateCache()
    S.EnemyCache = nil; S.EnemyCacheTime = 0
end

-- ═══════════════════════════════════════
--  ✅ CÂMERA CORRIGIDA — RotateCam
--  Problema original: CFrame montado errado causava câmera invertida
-- ═══════════════════════════════════════
local function RotateCam(targetPos)
    if Cfg.SilentAim then return end

    local mr = MRoot()
    if not mr then return end

    -- ✅ CORRIGIDO: usa LookAt direto da posição da câmera para o alvo
    -- O método anterior montava CFrame manualmente com vetores que podiam ficar invertidos
    local camPos = Camera.CFrame.Position

    -- Calcula a direção da câmera até o alvo
    local lookDir = (targetPos - camPos)
    if lookDir.Magnitude < 0.01 then return end
    lookDir = lookDir.Unit

    -- Monta o CFrame de forma segura usando CFrame.lookAt
    local targetCFrame = CFrame.lookAt(camPos, targetPos)

    if Cfg.SnapOn then
        -- Snap instantâneo: aplica direto
        Camera.CFrame = targetCFrame
    else
        -- Lerp suave: interpola entre câmera atual e alvo
        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, Cfg.Smooth)
    end
end

-- ═══════════════════════════════════════
--  AUTO FIRE V1 — mouse1click
-- ═══════════════════════════════════════
local function AutoFireV1(target, headPos)
    if not Cfg.AutoFireV1 then return end
    local now = tick()
    if now - S.LastFire < Cfg.FireRate then return end
    S.LastFire = now

    if target and headPos then
        RotateCam(PredictPos(target, headPos))
    end

    pcall(function() mouse1click() end)
end

-- ═══════════════════════════════════════
--  BYTENET — Encontra Part no Map automaticamente
-- ═══════════════════════════════════════
local function FindMapPart()
    local mapFolder = Workspace:FindFirstChild("Map")
    if mapFolder then
        for _, folder in ipairs(mapFolder:GetChildren()) do
            if folder:IsA("Folder") or folder:IsA("Model") then
                local part = folder:FindFirstChildOfClass("BasePart")
                if part then return part end
            end
        end
        local part = mapFolder:FindFirstChildOfClass("BasePart")
        if part then return part end
    end
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Folder") or sub:IsA("Model") then
                    local part = sub:FindFirstChildOfClass("BasePart")
                    if part then return part end
                end
                if sub:IsA("BasePart") then return sub end
            end
        end
    end
    return nil
end

local FIRE_BUFFER = buffer.fromstring(
    "\b\001\148\128kC=\016\208@\154]C\194\000S\000\224\178\184\211\136\228\171\176\228\145\169\218\138" ..
    "\227\153\188\225\149\155\225\178\128\228\174\167\216\184\225\155\131\225\153\177\228\183\190\228\142\190" ..
    "\227\152\173\228\185\175\228\184\148\217\162\228\185\156\216\160\216\191\240\159\144\141\228\184\133\217" ..
    "\190\228\185\153\240\159\144\141\216\175\240\159\165\170\216\166\217\188\000\000\000FC\214q\128@\253\205" ..
    "(\195\229\188\152\190\\\"\162\188\130Jt\191\001\a\000Primary\002"
)

local ByteNetReliable = ReplicatedStorage:WaitForChild("ByteNetReliable", 5)

local function AutoFireV2()
    if not Cfg.AutoFireV2 then return end
    if not ByteNetReliable then return end
    local now = tick()
    if now - S.LastFire < Cfg.FireRate then return end
    S.LastFire = now
    local part = FindMapPart()
    if not part then return end
    local args = { FIRE_BUFFER, { part, part } }
    pcall(function() ByteNetReliable:FireServer(unpack(args)) end)
end

local function DoFire(target, headPos)
    if Cfg.AutoFireV1 then AutoFireV1(target, headPos) end
    if Cfg.AutoFireV2 then AutoFireV2() end
end

local FlashFire = DoFire

-- ═══════════════════════════════════════
--  SMART BOT — Troca arma + combate
-- ═══════════════════════════════════════
local function DoMeleeAttack()
    local now = tick()
    if now - S.LastMeleeFire < 0.35 then return end
    S.LastMeleeFire = now
    pcall(function() mouse1click() end)
end

local function DoSmartAttack(enemy)
    if not enemy or not Alive(enemy) then return end
    local mr = MRoot()
    local er = PRoot(enemy)
    if not mr or not er then return end
    local dist = (er.Position - mr.Position).Magnitude

    if dist <= Cfg.MeleeRange then
        local tool = GetCurrentTool()
        if tool and not IsMeleeWeapon(tool) then
            EquipWeapon(Cfg.MeleeSlot)
            task.wait(0.15)
        end
        DoMeleeAttack()
    else
        local tool = GetCurrentTool()
        if tool and IsMeleeWeapon(tool) then
            EquipWeapon(Cfg.RangeSlot1)
            task.wait(0.15)
        end
        if Cfg.WeaponSwap and tool and IsRangedWeapon(tool) then
            local now2 = tick()
            if S.WeaponInUse == Cfg.RangeSlot1 then
                if now2 - S.LastRangedFire > 0.25 then
                    SwitchToWeapon(Cfg.RangeSlot2)
                    S.WeaponInUse = Cfg.RangeSlot2
                end
            elseif S.WeaponInUse == Cfg.RangeSlot2 then
                if now2 - S.LastRangedFire > 0.25 then
                    SwitchToWeapon(Cfg.RangeSlot1)
                    S.WeaponInUse = Cfg.RangeSlot1
                end
            end
        end
        S.LastRangedFire = tick()
        DoFire(enemy, er.Position + Vector3.new(0, 1.5, 0))
    end
end

local function DoKillAura()
    if not Cfg.KillAura then return end
    local mr = MRoot(); if not mr then return end
    local myPos = mr.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP or Mate(p) or not Alive(p) then continue end
        local h = PHead(p); if not h then continue end
        if (h.Position - myPos).Magnitude <= Cfg.KillRange * 1.8 then
            DoFire(p, h.Position)
            task.wait(0.02)
        end
    end
end

-- ═══════════════════════════════════════
--  STEERING v2
-- ═══════════════════════════════════════
local function TryJump()
    local now = tick()
    if now - S.LastJump < 0.65 then return end
    S.LastJump = now
    local h = MHum(); if h then h.Jump = true end
end

local function SteerToward(origin, rawDir)
    local flat = Vector3.new(rawDir.X, 0, rawDir.Z)
    if flat.Magnitude < 0.01 then return Vector3.new(0, 0, 1) end
    flat = flat.Unit
    local chest = origin + Vector3.new(0, 1.2, 0)
    local probe = 6.5
    local char  = LP.Character; if not char then return flat end
    RP_STEER.FilterDescendantsInstances = { char }
    RP_FLOOR.FilterDescendantsInstances = { char }
    local angles = {0,20,-20,40,-40,60,-60,80,-80,105,-105,135,-135,180}
    for _, deg in ipairs(angles) do
        local r  = math.rad(deg)
        local c  = math.cos(r)
        local s_ = math.sin(r)
        local dir = Vector3.new(flat.X*c - flat.Z*s_, 0, flat.X*s_ + flat.Z*c)
        if not Workspace:Raycast(chest, dir * probe, RP_STEER) then
            local fwdPt = origin + dir * probe
            local fhit  = Workspace:Raycast(fwdPt + Vector3.new(0, 5, 0), Vector3.new(0, -12, 0), RP_FLOOR)
            if fhit then return dir end
        end
    end
    return flat
end

local function NeedsJump(origin, dir)
    if not Cfg.JumpOn then return false end
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.01 then return false end
    flat = flat.Unit
    local char = LP.Character; if not char then return false end
    RP_STEER.FilterDescendantsInstances = { char }
    local low = origin + Vector3.new(0, 0.5, 0)
    local hi  = origin + Vector3.new(0, 2.4, 0)
    return Workspace:Raycast(low, flat*3.5, RP_STEER) ~= nil
       and Workspace:Raycast(hi,  flat*3.5, RP_STEER) == nil
end

local stuckTimer = 0
local stkRefPos  = nil
local stkEscDir  = nil
local stkEscT    = 0

local function CheckStuck(pos)
    if not stkRefPos then stkRefPos = pos; return false end
    if (pos - stkRefPos).Magnitude < 0.8 then stuckTimer = stuckTimer + 0.05
    else stuckTimer = 0; stkRefPos = pos; stkEscDir = nil end
    stkRefPos = pos
    return stuckTimer > 1.0
end

local function ResetStuck()
    stuckTimer = 0; stkRefPos = nil; stkEscDir = nil; stkEscT = 0
end

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
        if Cfg.NoclipOn then hum:MoveTo(dest); continue end
        local rawDir = dest - myPos
        local flat   = Vector3.new(rawDir.X, 0, rawDir.Z)
        if CheckStuck(myPos) then
            TryJump()
            if not stkEscDir or (tick()-stkEscT) > 2.0 then
                local opp = -flat.Unit
                local a   = (math.random()-0.5) * math.pi * 0.6
                local c   = math.cos(a); local s_ = math.sin(a)
                stkEscDir = Vector3.new(opp.X*c - opp.Z*s_, 0, opp.X*s_ + opp.Z*c)
                stkEscT   = tick(); stuckTimer = 0
            end
            hum:MoveTo(myPos + stkEscDir * 14); continue
        end
        if NeedsJump(myPos, flat) then TryJump() end
        local steerDir  = SteerToward(myPos, flat)
        local lookahead = math.clamp(dist * 0.4, 8, 24)
        local movePt    = myPos + steerDir * lookahead
        RP_FLOOR.FilterDescendantsInstances = { LP.Character }
        local fhit = Workspace:Raycast(movePt + Vector3.new(0, 6, 0), Vector3.new(0, -16, 0), RP_FLOOR)
        if fhit then movePt = fhit.Position + Vector3.new(0, 3, 0) end
        hum:MoveTo(movePt)
    end
end

-- ═══════════════════════════════════════
--  BOT
-- ═══════════════════════════════════════
local botThread = nil

local function StopBot()
    S.BotRunning = false
    if botThread then task.cancel(botThread); botThread = nil end
    S.BotStatus = "Inativo"; InvalidateCache()
    local h = MHum(); local r = MRoot()
    if h and r then h:MoveTo(r.Position) end
end

local function StartBot()
    if S.BotRunning then return end
    S.BotRunning = true; InvalidateCache()
    botThread = task.spawn(function()
        while S.BotRunning and Cfg.BotOn do
            local mr   = MRoot()
            local mhum = MHum()
            if not mr or not mhum or mhum.Health <= 0 then
                S.BotStatus = "⏳ Respawnando..."; task.wait(0.4); continue
            end
            if Cfg.SpeedOn and mhum.WalkSpeed ~= Cfg.SpeedVal then
                mhum.WalkSpeed = Cfg.SpeedVal
            end
            if Cfg.AutoReload then
                pcall(function()
                    local char = LP.Character; if not char then return end
                    for _, tool in ipairs(char:GetChildren()) do
                        if not tool:IsA("Tool") then continue end
                        for _, v in ipairs(tool:GetDescendants()) do
                            local n = v.Name:lower()
                            if (n:find("ammo") or n:find("bullet") or n:find("magazine") or n:find("clip"))
                            and (v:IsA("IntValue") or v:IsA("NumberValue")) and v.Value <= 0 then
                                pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.R, false, game) end)
                                task.delay(0.08, function()
                                    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game) end)
                                end)
                            end
                        end
                    end
                end)
            end
            local enemy = NearestEnemy()
            if not enemy then
                S.BotStatus = "🌐 Explorando"
                if not S.RoamPt then
                    local a   = math.random() * math.pi * 2
                    local d   = 60 + math.random() * Cfg.RoamRad
                    local probe = mr.Position + Vector3.new(math.cos(a)*d, 10, math.sin(a)*d)
                    RP_FLOOR.FilterDescendantsInstances = { LP.Character }
                    local ray = Workspace:Raycast(probe, Vector3.new(0, -80, 0), RP_FLOOR)
                    S.RoamPt  = ray and ray.Position + Vector3.new(0, 3, 0)
                              or mr.Position + Vector3.new(math.cos(a)*d, 0, math.sin(a)*d)
                end
                MoveToTarget(
                    function() return S.RoamPt end,
                    function()
                        if NearestEnemy() then InvalidateCache(); S.RoamPt = nil; return true end
                        local r2 = MRoot()
                        if r2 and (r2.Position - S.RoamPt).Magnitude < 8 then S.RoamPt = nil; return true end
                        return false
                    end
                )
                continue
            end
            if Cfg.TeleportOn then
                S.BotStatus = "⚡ " .. enemy.Name
                local er2 = PRoot(enemy); local mr2 = MRoot()
                if er2 and mr2 then mr2.CFrame = CFrame.new(er2.Position + Vector3.new(2, 0, 2)) end
                DoKillAura()
                local t0 = tick()
                while S.BotRunning and tick()-t0 < 6 do
                    task.wait(0.05)
                    DoSmartAttack(enemy)
                    if not Alive(enemy) then
                        S.Kills += 1; InvalidateCache()
                        S.BotStatus = "💀 Kill #" .. S.Kills; break
                    end
                    local er3 = PRoot(enemy); local mr3 = MRoot()
                    if er3 and mr3 and (er3.Position - mr3.Position).Magnitude > 8 then
                        mr3.CFrame = CFrame.new(er3.Position + Vector3.new(2, 0, 2))
                    end
                end
                continue
            end
            local er = PRoot(enemy)
            if not er then InvalidateCache(); task.wait(0.05); continue end
            local dist = (er.Position - mr.Position).Magnitude
            S.BotStatus = (dist <= Cfg.KillRange and "💀 FARM: " or "🏃 Chase: ") .. enemy.Name
            MoveToTarget(
                function()
                    local er2 = PRoot(enemy)
                    if not er2 then return nil end
                    return er2.Position
                end,
                function()
                    if not Alive(enemy) then
                        S.Kills += 1; InvalidateCache()
                        S.BotStatus = "💀 Kill #" .. S.Kills; return true
                    end
                    return false
                end
            )
            DoSmartAttack(enemy)
            task.wait(0.02)
        end
        S.BotRunning = false; S.BotStatus = "Inativo"
    end)
end

-- ═══════════════════════════════════════
--  NOCLIP / INF JUMP / ANTI-AFK
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
    if S.NoclipConn then S.NoclipConn:Disconnect(); S.NoclipConn = nil end
    local char = LP.Character; if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = true end
    end
end
local function SetupInfJump()
    if S.InfJumpConn then S.InfJumpConn:Disconnect() end
    S.InfJumpConn = UserInputService.JumpRequest:Connect(function()
        if not Cfg.InfJump then return end
        local h = MHum(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end
local function SetupAntiAFK()
    if S.AntiAFKConn then S.AntiAFKConn:Disconnect() end
    S.AntiAFKConn = RunService.Heartbeat:Connect(function()
        if not Cfg.AntiAFK then return end
        if tick() - S.LastAFK > 55 then
            S.LastAFK = tick()
            pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game) end)
            task.delay(0.06, function()
                pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game) end)
            end)
        end
    end)
end

-- ═══════════════════════════════════════
--  ESP
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
        bones[i] = Drw("Line", {Visible=false, Color=Color3.new(1,1,1), Thickness=1, Transparency=0.7})
    end
    S.ESPObj[player] = {
        Box  = Drw("Square",{Visible=false,Color=Color3.fromRGB(255,50,50),  Thickness=1.5,Filled=false,Transparency=1}),
        Fill = Drw("Square",{Visible=false,Color=Color3.fromRGB(255,50,50),  Transparency=0.06,Filled=true}),
        Name = Drw("Text",  {Visible=false,Color=Color3.new(1,1,1),          Size=13,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2}),
        Dist = Drw("Text",  {Visible=false,Color=Color3.fromRGB(200,200,200),Size=12,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2}),
        HpBG = Drw("Square",{Visible=false,Color=Color3.new(0,0,0),          Filled=true,Transparency=0.5}),
        HpBr = Drw("Square",{Visible=false,Color=Color3.fromRGB(60,210,60),  Filled=true,Transparency=1}),
        Trc  = Drw("Line",  {Visible=false,Color=Color3.fromRGB(255,50,50),  Thickness=1,Transparency=0.6}),
        HDt  = Drw("Circle",{Visible=false,Color=Color3.fromRGB(255,80,80),  Thickness=1.5,Filled=false,NumSides=32,Radius=5,Transparency=1}),
        Bones = bones,
    }
end
local function DelESP(p)
    local o = S.ESPObj[p]; if not o then return end
    for k, dd in pairs(o) do
        if k == "Bones" then for _, b in pairs(dd) do pcall(function() b:Remove() end) end
        else pcall(function() dd:Remove() end) end
    end
    S.ESPObj[p] = nil
end
local function HideAll(o)
    for k, dd in pairs(o) do
        if k == "Bones" then for _, b in pairs(dd) do pcall(function() b.Visible = false end) end
        else pcall(function() dd.Visible = false end) end
    end
end
local espTimer = 0
local function UpdateESP()
    if tick() - espTimer < 0.033 then return end
    espTimer = tick()
    local mr    = MRoot()
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
        local hsp = W2S(head.Position)
        local dist = myPos and (root.Position - myPos).Magnitude or 0
        local frac = math.clamp(1000 / math.max(dist, 10), 2, 200)
        local bW, bH = frac*1.05, frac*2.9
        local bX, bY = sp.X - bW*0.5, sp.Y - bH*0.78
        local isTarget = S.Target == p
        local col = isTarget and Color3.fromRGB(0,255,200)
            or Mate(p) and Color3.fromRGB(50,120,255)
            or Color3.fromRGB(255,50,50)
        local vis = CanSee(char, head.Position)
        local a   = vis and 1 or 0.28
        if Cfg.BoxOn then
            o.Box.Position = Vector2.new(bX, bY); o.Box.Size = Vector2.new(bW, bH)
            o.Box.Color = col; o.Box.Transparency = a; o.Box.Visible = true
            o.Fill.Position = Vector2.new(bX, bY); o.Fill.Size = Vector2.new(bW, bH)
            o.Fill.Color = col; o.Fill.Transparency = 0.06*a; o.Fill.Visible = true
        else o.Box.Visible = false; o.Fill.Visible = false end
        if Cfg.NameOn then
            o.Name.Text = p.Name; o.Name.Color = col
            o.Name.Position = Vector2.new(sp.X, bY-15)
            o.Name.Transparency = a; o.Name.Visible = true
        else o.Name.Visible = false end
        if Cfg.DistOn then
            o.Dist.Text = string.format("%.0f", dist) .. "m"
            o.Dist.Position = Vector2.new(sp.X, bY+bH+2)
            o.Dist.Transparency = a; o.Dist.Visible = true
        else o.Dist.Visible = false end
        if Cfg.HpOn then
            local hm = char:FindFirstChildOfClass("Humanoid")
            local hp = hm and (hm.Health / math.max(hm.MaxHealth, 1)) or 0
            o.HpBG.Position = Vector2.new(bX-5, bY); o.HpBG.Size = Vector2.new(4, bH); o.HpBG.Visible = true
            o.HpBr.Color    = Color3.fromRGB(math.floor(255*(1-hp)), math.floor(255*hp), 30)
            o.HpBr.Position = Vector2.new(bX-5, bY+bH*(1-hp))
            o.HpBr.Size     = Vector2.new(4, bH*hp)
            o.HpBr.Transparency = a; o.HpBr.Visible = true
        else o.HpBG.Visible = false; o.HpBr.Visible = false end
        if Cfg.TraceOn then
            local vp = Camera.ViewportSize
            o.Trc.From = Vector2.new(vp.X*0.5, vp.Y)
            o.Trc.To   = sp; o.Trc.Color = col
            o.Trc.Transparency = a*0.6; o.Trc.Visible = true
        else o.Trc.Visible = false end
        o.HDt.Position = hsp; o.HDt.Color = col; o.HDt.Transparency = a; o.HDt.Visible = true
        if Cfg.SkeletonOn then
            for i, bone in ipairs(BONES) do
                local p1 = char:FindFirstChild(bone[1])
                local p2 = char:FindFirstChild(bone[2])
                local bl = o.Bones[i]
                if p1 and p2 and bl then
                    local s1, o1 = W2S(p1.Position)
                    local s2, o2 = W2S(p2.Position)
                    if o1 and o2 then
                        bl.From = s1; bl.To = s2; bl.Color = col
                        bl.Transparency = a*0.75; bl.Visible = true
                    else bl.Visible = false end
                end
            end
        else for _, b in pairs(o.Bones) do b.Visible = false end end
    end
end

-- ═══════════════════════════════════════
--  DRAWINGS (HUD)
-- ═══════════════════════════════════════
local FOVCirc   = Drw("Circle",{Visible=false,Color=Color3.fromRGB(255,220,0),Radius=Cfg.FOVRadius,Thickness=1.2,Filled=false,NumSides=80,Transparency=0.65})
local CrossH    = Drw("Line",  {Visible=true, Color=Color3.new(1,1,1),Thickness=1,Transparency=0.5})
local CrossV    = Drw("Line",  {Visible=true, Color=Color3.new(1,1,1),Thickness=1,Transparency=0.5})
local StatLbl   = Drw("Text",  {Visible=true, Color=Color3.fromRGB(0,220,160),  Size=13,Center=false,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Position=Vector2.new(10,50)})
local KDLbl     = Drw("Text",  {Visible=true, Color=Color3.fromRGB(255,200,50), Size=12,Center=false,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Position=Vector2.new(10,68)})
local LockLbl   = Drw("Text",  {Visible=false,Color=Color3.fromRGB(255,50,50),  Size=14,Center=true, Outline=true,OutlineColor=Color3.new(0,0,0),Font=2})
local PredDot   = Drw("Circle",{Visible=false,Color=Color3.fromRGB(0,200,255),  Radius=4,Thickness=1.5,Filled=true,NumSides=16,Transparency=0.8})
local FireMode  = Drw("Text",  {Visible=true, Color=Color3.fromRGB(255,100,100),Size=11,Center=false,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Position=Vector2.new(10,86)})
local FireV2Lbl = Drw("Text",  {Visible=true, Color=Color3.fromRGB(100,200,255),Size=11,Center=false,Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Position=Vector2.new(10,100)})

-- ═══════════════════════════════════════
--  SETUP PLAYERS
-- ═══════════════════════════════════════
for _, p in ipairs(Players:GetPlayers()) do NewESP(p) end
Players.PlayerAdded:Connect(NewESP)
Players.PlayerRemoving:Connect(DelESP)
LP.CharacterAdded:Connect(function()
    S.Deaths += 1; task.wait(2)
    S.Target = nil; S.TargetHead = nil
    S.RoamPt = nil; S.PrevHead  = {}
    S.FlashActive   = false
    S.CurrentWeapon = 1; S.WeaponInUse = 1
    InvalidateCache(); StopBot(); task.wait(0.3)
    if Cfg.BotOn    then StartBot()     end
    if Cfg.NoclipOn then EnableNoclip() end
end)

-- ═══════════════════════════════════════
--  FLUENT MENU
-- ═══════════════════════════════════════
local Win = Fluent:CreateWindow({
    Title    = "RONY MENU FREEMIUN v2",
    SubTitle = "🔥 Aimbot Corrigido • AutoFire V1+V2 • Smart Weapon",
    TabWidth = 160,
    Size     = UDim2.fromOffset(660, 560),
    Acrylic  = false,
    Theme    = "Dark",
})

local T = {
    Farm = Win:AddTab({Title="Farm Bot",   Icon="bot"}),
    Aim  = Win:AddTab({Title="Aimbot",     Icon="crosshair"}),
    Move = Win:AddTab({Title="Movimento",  Icon="zap"}),
    Weap = Win:AddTab({Title="Armas",      Icon="shield"}),
    ESP  = Win:AddTab({Title="ESP",        Icon="eye"}),
    Cfg  = Win:AddTab({Title="Config",     Icon="settings"}),
}

-- ── FARM BOT ──
T.Farm:AddParagraph({
    Title   = "🤖 AutoBot Inteligente v2",
    Content = "Troca automática de arma • Faca perto + Rifle longe • Rotação de armas para skip reload"
})
T.Farm:AddToggle("BotOn",{Title="Farm Bot",Default=Cfg.BotOn,
    Callback=function(v) Cfg.BotOn=v; if v then StartBot() else StopBot() end end})
T.Farm:AddToggle("SmartBot",{Title="🧠 Smart Weapon System",Description="Faca perto + Rifle longe + Skip reload",Default=Cfg.SmartBot,
    Callback=function(v) Cfg.SmartBot=v end})
T.Farm:AddToggle("KillAura",{Title="Kill Aura",Description="Atira em todos ao redor",Default=Cfg.KillAura,
    Callback=function(v) Cfg.KillAura=v end})
T.Farm:AddToggle("TeleportOn",{Title="Teleportar até Inimigo",Default=Cfg.TeleportOn,
    Callback=function(v) Cfg.TeleportOn=v end})
T.Farm:AddSlider("MeleeRange",  {Title="Range Faca (studs)",    Default=Cfg.MeleeRange, Min=5, Max=50,  Rounding=0, Callback=function(v) Cfg.MeleeRange=v  end})
T.Farm:AddSlider("RangedRange", {Title="Range Arma (studs)",    Default=Cfg.RangedRange,Min=30,Max=200, Rounding=0, Callback=function(v) Cfg.RangedRange=v end})
T.Farm:AddSlider("KillRange",   {Title="Range de Combate",      Default=Cfg.KillRange,  Min=10,Max=200, Rounding=0, Callback=function(v) Cfg.KillRange=v   end})
T.Farm:AddSlider("ChaseRange",  {Title="Range de Perseguição",  Default=Cfg.ChaseRange, Min=50,Max=1000,Rounding=0, Callback=function(v) Cfg.ChaseRange=v  end})
T.Farm:AddSlider("RoamRad",     {Title="Raio de Roaming",       Default=Cfg.RoamRad,    Min=50,Max=600, Rounding=0, Callback=function(v) Cfg.RoamRad=v     end})
T.Farm:AddButton({Title="⛔ Parar Bot",Callback=function()
    StopBot(); Fluent:Notify({Title="Bot parado",Content="",Duration=2})
end})

-- ── AIMBOT ──
T.Aim:AddParagraph({
    Title   = "🎯 Aimbot CORRIGIDO v2",
    Content = "✅ CFrame.lookAt() — aponta câmera direto na cabeça\n✅ FindAnyEnemy() sem filtros bloqueando alvos\n✅ WallCheck OFF por padrão (ativável manualmente)"
})
T.Aim:AddToggle("AimOn",{Title="Aimbot",Default=Cfg.AimbotOn,
    Callback=function(v) Cfg.AimbotOn=v end})
T.Aim:AddToggle("AutoFire",{Title="Auto Fire (Loop)",Default=Cfg.AutoFire,
    Callback=function(v) Cfg.AutoFire=v end})
T.Aim:AddToggle("AutoFireV1",{
    Title="🖱️ Auto Fire V1 — mouse1click",
    Description="Aponta câmera + mouse1click(). Busca inimigo automático.",
    Default=Cfg.AutoFireV1,
    Callback=function(v) Cfg.AutoFireV1=v end
})
T.Aim:AddToggle("AutoFireV2",{
    Title="⚡ Auto Fire V2 — ByteNet Event",
    Description="Dispara via FireServer com buffer capturado.",
    Default=Cfg.AutoFireV2,
    Callback=function(v) Cfg.AutoFireV2=v end
})
T.Aim:AddToggle("MouseFire",{Title="🖱️ Mouse Click = Dispara",Description="Clique do mouse dispara imediatamente se alvo encontrado",Default=S.MouseFireEnabled,
    Callback=function(v) S.MouseFireEnabled=v end})
T.Aim:AddToggle("SilentOn",{Title="Silent Aim",Description="Dispara sem mover câmera",Default=Cfg.SilentAim,
    Callback=function(v) Cfg.SilentAim=v end})
T.Aim:AddToggle("PredOn",{Title="Bullet Prediction",Description="Compensa movimento do alvo",Default=Cfg.Prediction,
    Callback=function(v) Cfg.Prediction=v end})
T.Aim:AddToggle("WallOn",{
    Title="Wall Check",
    Description="⚠️ ATENÇÃO: Deixe OFF se o aimbot não mirar em ninguém",
    Default=Cfg.WallCheck,
    Callback=function(v) Cfg.WallCheck=v end
})
T.Aim:AddToggle("SnapOn",{Title="Snap Instantâneo",Default=Cfg.SnapOn,
    Callback=function(v) Cfg.SnapOn=v end})
T.Aim:AddToggle("FOVOn",{Title="Limitar FOV",Default=Cfg.FOVOn,
    Callback=function(v) Cfg.FOVOn=v end})
T.Aim:AddSlider("FOVRad",    {Title="Raio FOV",               Default=Cfg.FOVRadius, Min=50, Max=700,  Rounding=0, Callback=function(v) Cfg.FOVRadius=v; FOVCirc.Radius=v end})
T.Aim:AddSlider("MaxDist",   {Title="Alcance Máximo (studs)", Default=Cfg.MaxDist,   Min=50, Max=1000, Rounding=0, Callback=function(v) Cfg.MaxDist=v    end})
T.Aim:AddSlider("FRateMs",   {Title="Fire Rate (ms)",         Default=math.floor(Cfg.FireRate*1000),Min=20,Max=500,Rounding=0,Callback=function(v) Cfg.FireRate=v/1000 end})
T.Aim:AddSlider("BulletSpd", {Title="Velocidade Bala (s/s)",  Default=Cfg.BulletSpd, Min=100,Max=1000, Rounding=0, Callback=function(v) Cfg.BulletSpd=v  end})
T.Aim:AddSlider("SmoothVal", {Title="Suavidade do Lerp",      Default=math.floor(Cfg.Smooth*100),Min=1,Max=100,Rounding=0,Callback=function(v) Cfg.Smooth=v/100 end})
T.Aim:AddButton({Title="🧪 Testar Aimbot Agora",Callback=function()
    local t, h = FindAnyEnemy()
    if t and h then
        RotateCam(h.Position)
        DoFire(t, h.Position)
        Fluent:Notify({Title="✅ Aimbot OK",Content="Mirou em: "..t.Name,Duration=3})
    else
        Fluent:Notify({Title="❌ Nenhum Inimigo",Content="Nenhum jogador encontrado no range",Duration=3})
    end
end})

-- ── MOVIMENTO ──
T.Move:AddToggle("NoclipOn",{Title="Noclip",Default=Cfg.NoclipOn,
    Callback=function(v) Cfg.NoclipOn=v; if v then EnableNoclip() else DisableNoclip() end end})
T.Move:AddToggle("SpeedOn",{Title="Speed Boost",Default=Cfg.SpeedOn,
    Callback=function(v) Cfg.SpeedOn=v
        if not v then local h=MHum(); if h then h.WalkSpeed=16 end end end})
T.Move:AddSlider("SpeedVal",{Title="WalkSpeed",Default=Cfg.SpeedVal,Min=16,Max=120,Rounding=0,
    Callback=function(v) Cfg.SpeedVal=v end})
T.Move:AddToggle("InfJump",{Title="Infinite Jump",Default=Cfg.InfJump,
    Callback=function(v) Cfg.InfJump=v end})
T.Move:AddToggle("JumpOn",{Title="Auto Pular Obstáculos",Default=Cfg.JumpOn,
    Callback=function(v) Cfg.JumpOn=v end})

-- ── ARMAS ──
T.Weap:AddParagraph({
    Title   = "⚔️ Sistema de Armas Inteligente",
    Content = "Troca automática com delay customizável\nFaca em range curto • Rifle em range longo\nPistola como backup pra skip reload"
})
T.Weap:AddToggle("WeaponSwap",{Title="Troca Automática de Armas",Description="Rifle → Pistola → Rifle (skip reload)",Default=Cfg.WeaponSwap,
    Callback=function(v) Cfg.WeaponSwap=v end})
T.Weap:AddSlider("MeleeSlot", {Title="Slot Faca",             Default=Cfg.MeleeSlot,  Min=1,Max=9,Rounding=0,Callback=function(v) Cfg.MeleeSlot=v  end})
T.Weap:AddSlider("RangeSlot1",{Title="Slot Rifle (Principal)",Default=Cfg.RangeSlot1, Min=1,Max=9,Rounding=0,Callback=function(v) Cfg.RangeSlot1=v end})
T.Weap:AddSlider("RangeSlot2",{Title="Slot Pistola (Backup)", Default=Cfg.RangeSlot2, Min=1,Max=9,Rounding=0,Callback=function(v) Cfg.RangeSlot2=v end})
T.Weap:AddSlider("SwapDelay", {Title="Delay Trocas (ms)",     Default=math.floor(Cfg.SwapDelay*1000),Min=50,Max=300,Rounding=0,Callback=function(v) Cfg.SwapDelay=v/1000 end})
T.Weap:AddButton({Title="🔪 Testar Faca",  Callback=function() EquipWeapon(Cfg.MeleeSlot);  Fluent:Notify({Title="Faca Equipada", Content="Slot "..Cfg.MeleeSlot,  Duration=2}) end})
T.Weap:AddButton({Title="🔫 Testar Rifle", Callback=function() EquipWeapon(Cfg.RangeSlot1); Fluent:Notify({Title="Rifle Equipado",Content="Slot "..Cfg.RangeSlot1, Duration=2}) end})

-- ── ESP ──
T.ESP:AddToggle("ESPOn",   {Title="ESP",         Default=Cfg.ESPOn,      Callback=function(v) Cfg.ESPOn=v      end})
T.ESP:AddToggle("BoxOn",   {Title="Box",          Default=Cfg.BoxOn,      Callback=function(v) Cfg.BoxOn=v      end})
T.ESP:AddToggle("NameOn",  {Title="Nome",         Default=Cfg.NameOn,     Callback=function(v) Cfg.NameOn=v     end})
T.ESP:AddToggle("HpOn",    {Title="Health Bar",   Default=Cfg.HpOn,       Callback=function(v) Cfg.HpOn=v       end})
T.ESP:AddToggle("DistOn",  {Title="Distância",    Default=Cfg.DistOn,     Callback=function(v) Cfg.DistOn=v     end})
T.ESP:AddToggle("TraceOn", {Title="Tracer",       Default=Cfg.TraceOn,    Callback=function(v) Cfg.TraceOn=v    end})
T.ESP:AddToggle("SkelOn",  {Title="Skeleton ESP", Default=Cfg.SkeletonOn, Callback=function(v) Cfg.SkeletonOn=v end})
T.ESP:AddToggle("FOVShow", {Title="Círculo FOV",  Default=Cfg.FOVShow,
    Callback=function(v) Cfg.FOVShow=v; FOVCirc.Visible=v end})

-- ── CONFIG ──
T.Cfg:AddToggle("TeamOn",     {Title="Team Check",  Default=Cfg.TeamCheck,  Callback=function(v) Cfg.TeamCheck=v  end})
T.Cfg:AddToggle("AntiAFK",    {Title="Anti-AFK",    Default=Cfg.AntiAFK,    Callback=function(v) Cfg.AntiAFK=v    end})
T.Cfg:AddToggle("AutoReload", {Title="Auto Reload", Default=Cfg.AutoReload, Callback=function(v) Cfg.AutoReload=v end})
T.Cfg:AddButton({Title="⚡ Otimizar FPS",Callback=function()
    for _, v in pairs(game:GetDescendants()) do
        if v:IsA("PostEffect") or v:IsA("ParticleEmitter") or v:IsA("Trail") then
            pcall(function() v.Enabled = false end)
        end
    end
    Fluent:Notify({Title="FPS Boost",Content="Efeitos visuais removidos",Duration=2})
end})
T.Cfg:AddButton({Title="📊 Status Detalhado",Callback=function()
    local tool = GetCurrentTool()
    Fluent:Notify({
        Title   = "RONY MENU v2 Status",
        Content = string.format(
            "K:%d D:%d | Bot:%s | Arma:%s\nV1:%s | V2:%s | Wall:%s",
            S.Kills, S.Deaths,
            S.BotRunning and "ON" or "OFF",
            tool and tool.Name or "Nenhuma",
            Cfg.AutoFireV1 and "ON" or "OFF",
            Cfg.AutoFireV2 and "ON" or "OFF",
            Cfg.WallCheck  and "ON ⚠️" or "OFF ✅"
        ),
        Duration = 5
    })
end})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:BuildInterfaceSection(T.Cfg)
SaveManager:BuildConfigSection(T.Cfg)
Win:SelectTab(1)

-- ═══════════════════════════════════════
--  MAIN LOOP — PreSimulation (60fps)
-- ═══════════════════════════════════════
RunService.PreSimulation:Connect(function()
    local c = Ctr()

    -- Crosshair
    CrossH.From = Vector2.new(c.X-10, c.Y); CrossH.To = Vector2.new(c.X+10, c.Y)
    CrossV.From = Vector2.new(c.X, c.Y-10); CrossV.To = Vector2.new(c.X, c.Y+10)
    FOVCirc.Position = c

    -- HUD labels
    StatLbl.Text   = "◈ " .. S.BotStatus
    KDLbl.Text     = "K: " .. S.Kills .. "  D: " .. S.Deaths
    FireMode.Text  = Cfg.AutoFireV1 and "[🖱️ V1 ON]" or "[🖱️ V1 OFF]"
    FireV2Lbl.Text = Cfg.AutoFireV2 and "[⚡ V2 ON]"  or "[⚡ V2 OFF]"

    -- ESP
    UpdateESP()

    -- Aimbot desligado → limpa
    if not Cfg.AimbotOn then
        S.Target = nil; S.TargetHead = nil
        LockLbl.Visible = false; PredDot.Visible = false
        return
    end

    -- ✅ CORRIGIDO: usa FindAnyEnemy unificado
    local p, h = FindAnyEnemy()
    S.Target     = p
    S.TargetHead = h

    if not p or not h then
        LockLbl.Visible = false
        PredDot.Visible = false
        return
    end

    -- Posição da cabeça com predição
    local headPos = h.Position
    local aimPos  = PredictPos(p, headPos)

    -- ✅ CORRIGIDO: lock label posicionado corretamente
    local lsp, on = W2S(headPos)
    if on then
        LockLbl.Text     = "[ ◉ " .. p.Name .. " ]"
        LockLbl.Position = Vector2.new(lsp.X, lsp.Y - 24)
    else
        LockLbl.Text     = "[ ◉ " .. p.Name .. " ◄ ]"
        LockLbl.Position = Vector2.new(c.X, c.Y - 40)
    end
    LockLbl.Visible = true

    -- Dot de predição
    if Cfg.Prediction then
        local ps, po = W2S(aimPos)
        PredDot.Position = ps
        PredDot.Visible  = po
    else
        PredDot.Visible = false
    end

    -- ✅ Rotaciona câmera para a posição prevista
    RotateCam(aimPos)

    -- Auto Fire loop
    if Cfg.AutoFire then
        DoFire(p, headPos)
    end
end)

-- ═══════════════════════════════════════
--  MOUSE CLICK — dispara imediatamente
-- ═══════════════════════════════════════
UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if not S.MouseFireEnabled then return end

    S.LastFire = 0  -- reset cooldown para atirar no ato

    local target, head = FindAnyEnemy()
    if not target or not head then return end

    DoFire(target, head.Position)
end)

-- ═══════════════════════════════════════
--  INICIALIZAÇÃO
-- ═══════════════════════════════════════
SetupInfJump()
SetupAntiAFK()
if Cfg.NoclipOn then EnableNoclip() end
if Cfg.BotOn    then StartBot()     end

FireMode.Text  = "[🖱️ V1 ON]"
FireV2Lbl.Text = "[⚡ V2 ON]"

task.delay(1.5, function()
    Fluent:Notify({
        Title   = "✅ RONY MENU v2 — Aimbot Corrigido",
        Content = "🎯 CFrame.lookAt() • Head lock funcionando\n⚠️ WallCheck OFF por padrão — ative se quiser filtrar paredes",
        Duration = 6,
    })
end)

print("[RONY MENU v2] ✅ Aimbot corrigido — CFrame.lookAt + FindAnyEnemy sem bloqueios")
