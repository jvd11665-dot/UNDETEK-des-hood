--[[
  UNDETEK xhub — Des Hood (FREE STANDALONE)
  No hub / no key / no shieldDeliver
  Discord: https://discord.gg/cgRsTMUa9J
  Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/jvd11665-dot/UNDETEK-des-hood/main/script.lua"))()
]]

-- PlaceId guard (abort outside Des Hood)
do
  local allowed = { "2788229376" }
  local ok = false
  local pid = tostring(game.PlaceId)
  for _, id in ipairs(allowed) do
    if pid == id then ok = true break end
  end
  if not ok and not (getgenv and getgenv().__XHUB_FORCE) then
    warn("[UNDETEK] Des Hood: wrong PlaceId (" .. pid .. ") — aborted")
    return
  end
end

--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║  XHUB PRESENTS · CAPUCHE RETOUR                                 ║
    ║  BY MRN STUDIO & PURGATORIZZ                                 ║
    ╚══════════════════════════════════════════════════════════════╝
    Da Hood-like PvP · Silent / Aura / ESP / Shop · Theme noir-rouge
]]

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local TeleportService    = game:GetService("TeleportService")
local StarterGui         = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ================= ETAT GLOBAL =================
local M = {}
M.state = {
    -- Silent aim (gun)
    silent            = false,
    silentAuto        = false,     -- tire tout seul (pas besoin de clic)
    silentKey         = Enum.UserInputType.MouseButton1,
    silentFov         = 250,       -- rayon ecran (px) pour choisir la cible
    silentUseFov      = true,
    silentMaxDist     = 500,       -- distance max 3D (studs)
    silentInterval    = 0.12,      -- cadence auto (s)
    silentPart        = "Head",    -- Head / HumanoidRootPart
    silentWallbang    = true,      -- ignore les murs (hit fabrique)
    silentVisibleOnly = false,     -- ne tirer que si cible visible
    -- Aura (gun) : tire sur tous les joueurs proches
    aura              = false,
    auraRange         = 120,       -- studs
    auraInterval      = 0.14,
    auraPart          = "Head",
    auraWallbang      = true,
    auraMax           = 3,         -- nb cibles par tick
    -- Tracer maison (Drawing) muzzle -> cible
    tracer            = true,
    tracerColor       = Color3.fromRGB(0, 255, 140),
    tracerTime        = 0.25,
    -- Team check
    ignoreCrew        = true,      -- ne pas viser membres du crew
    ignoreFriends     = false,

    -- Aimbot camera
    camAim            = false,
    camAimKey         = Enum.KeyCode.E,
    camAimFov         = 120,
    camAimPart        = "Head",
    camAimSmooth      = 0.5,

    -- ESP
    esp               = false,
    espBox            = true,
    espName           = true,
    espHealth         = true,
    espDist           = true,
    espSkeleton       = false,
    espTracer         = false,     -- ligne bas ecran -> cible
    espSnapline       = false,     -- ligne centre -> tete
    espMaxDist        = 1000,
    espTeamColor      = Color3.fromRGB(255, 80, 80),
    espCrewColor      = Color3.fromRGB(80, 200, 255),

    -- Movement

    -- Camera / visuals
    fov               = false, fovVal = 90,
    fullbright        = false,
    nofog             = false,

    -- Loadout (shop direct)
    loadoutSlots      = {"None", "None", "None", "None"},

    -- Divers
    antiafk           = true,
}

-- caches
M.drawings   = {}   -- ESP objets Drawing
M.tracers    = {}   -- tracers de tir temporaires
M.conns      = {}   -- connexions RunService/Input

-- ================= UTILS =================
local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 4 })
    end)
end

local function getChar()
    return LocalPlayer.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function partOf(model, name)
    if not model then return nil end
    return model:FindFirstChild(name) or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
end

local function isAlive(model)
    if not model then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

-- Retourne le remote MainGameEvent
function M.mainEvent()
    local gr = ReplicatedStorage:FindFirstChild("GameRemotes")
    return gr and gr:FindFirstChild("MainGameEvent")
end

function M.remotesFolder()
    return ReplicatedStorage:FindFirstChild("Remotes")
end

function M.gunHandler()
    local mod = ReplicatedStorage:FindFirstChild("Modules")
    mod = mod and mod:FindFirstChild("GunHandler")
    if not mod then return nil end
    local ok, res = pcall(require, mod)
    if ok then return res end
    return nil
end

-- ================= TEAM CHECK =================
function M.sameCrew(plr)
    -- Da Hood-like : crew via attribut/valeur. On tente plusieurs pistes.
    if not M.state.ignoreCrew then return false end
    local myCrew, theirCrew
    local function readCrew(p)
        local df = p:FindFirstChild("DataFolder")
        if df then
            local c = df:FindFirstChild("Crew") or df:FindFirstChild("Team")
            if c then return tostring(c.Value) end
        end
        if p.Team then return tostring(p.Team.Name) end
        return nil
    end
    myCrew = readCrew(LocalPlayer)
    theirCrew = readCrew(plr)
    if myCrew and theirCrew and myCrew ~= "" and myCrew ~= "None" then
        return myCrew == theirCrew
    end
    return false
end

function M.isEnemyPlayer(plr)
    if plr == LocalPlayer then return false end
    if not plr.Character or not isAlive(plr.Character) then return false end
    if M.state.ignoreFriends and pcall(function() return LocalPlayer:IsFriendsWith(plr.UserId) end) and LocalPlayer:IsFriendsWith(plr.UserId) then
        return false
    end
    if M.sameCrew(plr) then return false end
    return true
end

-- liste des modeles ennemis (joueurs)
function M.enemyChars()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if M.isEnemyPlayer(plr) then
            table.insert(list, plr.Character)
        end
    end
    return list
end

-- ================= DETECTION ARME =================
-- Une arme = Tool avec Handle + Range + Damage (+ Ammo pour gun)
function M.equippedTool()
    local c = getChar()
    if not c then return nil end
    return c:FindFirstChildOfClass("Tool")
end

function M.isGun(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local h = tool:FindFirstChild("Handle")
    return h and tool:FindFirstChild("Range") and tool:FindFirstChild("Damage") and tool:FindFirstChild("Ammo")
end

function M.getGun()
    local t = M.equippedTool()
    if M.isGun(t) then return t end
    return nil
end

function M.isShotgun(tool)
    if not tool then return false end
    local n = tool.Name:lower()
    return n:find("sg") ~= nil or n:find("shotgun") ~= nil or n:find("barrel") ~= nil
end

-- position du canon
function M.muzzlePos(tool)
    local h = tool:FindFirstChild("Handle")
    if not h then return nil end
    local mz = h:FindFirstChild("Muzzle")
    if mz and mz:IsA("Attachment") then
        return mz.WorldPosition
    end
    local def = tool:FindFirstChild("Default")
    if def then
        local mesh = def:FindFirstChild("Mesh")
        local mz2 = mesh and mesh:FindFirstChild("Muzzle")
        if mz2 and mz2:IsA("Attachment") then return mz2.WorldPosition end
    end
    return h.Position
end

-- fabrique un hit vers headPart et envoie au serveur
-- retourne ok, muzzlePos, hitPos
function M.fireGunAt(headPart, opts)
    opts = opts or {}
    local ev = M.mainEvent()
    local gun = M.getGun()
    if not ev or not gun or not headPart then return false end
    if (gun:FindFirstChild("Ammo") and gun.Ammo.Value < 1) then return false end

    local Handle = gun:FindFirstChild("Handle")
    local Range  = (gun:FindFirstChild("Range") and gun.Range.Value) or 200
    local Damage = (gun:FindFirstChild("Damage") and gun.Damage.Value) or 10
    local muzzle = M.muzzlePos(gun)
    if not muzzle then return false end

    local char = getChar()
    local hitPos = headPart.Position
    local normal = Vector3.new(0, 1, 0)
    local wallbang = opts.wallbang
    if wallbang == nil then wallbang = true end

    -- IMPORTANT (client-authoritative) : le vrai GunClient fait
    --   local Result1, Result2, Result3 = GunHandler.Shoot({...})
    --   MainGameEvent:FireServer("ShootGun", Handle, muzzle, nil, Result1, Result2, Result3, Range, Damage)
    -- Le serveur applique les degats sur l'INSTANCE renvoyee (Result1).
    -- On NE se sert PAS du raycast interne de GunHandler.Shoot (qui taperait un
    -- mur ou raterait). On force directement la partie de la cible => hit garanti,
    -- traverse les murs, peu importe ou pointe la camera.
    local function computeHit()
        local nrm = (muzzle - hitPos)
        nrm = (nrm.Magnitude > 1e-3) and nrm.Unit or Vector3.new(0, 1, 0)
        return headPart, hitPos, nrm
    end

    local ok = pcall(function()
        if M.isShotgun(gun) then
            local t = {}
            for _ = 1, 5 do
                local r1, r2, r3 = computeHit()
                table.insert(t, { AimPosition = hitPos, Result1 = r1, Result2 = r2, Result3 = r3 })
            end
            ev:FireServer("ShootGun", Handle, muzzle, t, nil, nil, nil, Range, Damage)
        else
            local r1, r2, r3 = computeHit()
            ev:FireServer("ShootGun", Handle, muzzle, nil, r1, r2, r3, Range, Damage)
        end
    end)

    if ok and M.state.tracer then
        M.spawnTracer(muzzle, hitPos)
    end
    return ok, muzzle, hitPos
end

-- ================= SELECTION CIBLE (silent) =================
local function worldToScreen(pos)
    local v, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), on, v.Z
end

function M.canSee(part)
    if not part then return false end
    local origin = Camera.CFrame.Position
    local dir = (part.Position - origin)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { getChar(), Camera }
    rp.FilterDescendantsInstances = ignore
    local res = Workspace:Raycast(origin, dir, rp)
    if not res then return true end
    return res.Instance and res.Instance:IsDescendantOf(part.Parent)
end

-- choisit la meilleure cible selon FOV ecran / distance
function M.getSilentTarget()
    local hrp = getHRP()
    if not hrp then return nil end
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local mouse = UserInputService:GetMouseLocation()
    local best, bestScore
    for _, char in ipairs(M.enemyChars()) do
        local part = char:FindFirstChild(M.state.silentPart) or char:FindFirstChild("HumanoidRootPart")
        if part then
            local dist3d = (part.Position - hrp.Position).Magnitude
            if dist3d <= M.state.silentMaxDist then
                local sp, on = worldToScreen(part.Position)
                if on then
                    local screenDist = (sp - Vector2.new(mouse.X, mouse.Y)).Magnitude
                    local ok = true
                    if M.state.silentUseFov and screenDist > M.state.silentFov then ok = false end
                    if ok and M.state.silentVisibleOnly and not M.canSee(part) then ok = false end
                    if ok and (not bestScore or screenDist < bestScore) then
                        bestScore = screenDist
                        best = part
                    end
                end
            end
        end
    end
    return best
end

function M.doSilent()
    local part = M.getSilentTarget()
    if part then
        M.fireGunAt(part, { wallbang = M.state.silentWallbang })
    end
end

-- ================= AURA =================
function M.stepAura()
    local hrp = getHRP()
    if not hrp then return end
    local fired = 0
    for _, char in ipairs(M.enemyChars()) do
        if fired >= M.state.auraMax then break end
        local part = char:FindFirstChild(M.state.auraPart) or char:FindFirstChild("HumanoidRootPart")
        if part and (part.Position - hrp.Position).Magnitude <= M.state.auraRange then
            local ok = M.fireGunAt(part, { wallbang = M.state.auraWallbang })
            if ok then fired = fired + 1 end
        end
    end
end

-- ================= TRACER DE TIR (Drawing) =================
function M.spawnTracer(fromPos, toPos)
    local ok, line = pcall(function() return Drawing.new("Line") end)
    if not ok or not line then return end
    line.Thickness = 1.6
    line.Color = M.state.tracerColor
    line.Transparency = 1
    table.insert(M.tracers, { line = line, from = fromPos, to = toPos, t = tick() })
end

function M.stepTracers()
    for i = #M.tracers, 1, -1 do
        local tr = M.tracers[i]
        local age = tick() - tr.t
        if age > M.state.tracerTime then
            pcall(function() tr.line:Remove() end)
            table.remove(M.tracers, i)
        else
            local a, onA = worldToScreen(tr.from)
            local b, onB = worldToScreen(tr.to)
            if onA and onB then
                tr.line.Visible = true
                tr.line.From = a
                tr.line.To = b
                tr.line.Transparency = 1 - (age / M.state.tracerTime)
            else
                tr.line.Visible = false
            end
        end
    end
end

-- ================= ESP =================
local function newDraw(kind, props)
    local ok, obj = pcall(function() return Drawing.new(kind) end)
    if not ok or not obj then return nil end
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    return obj
end

function M.espColorFor(char)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character == char then
            if M.sameCrew(plr) then return M.state.espCrewColor end
            return M.state.espTeamColor
        end
    end
    return M.state.espTeamColor
end

local SKELETON = {
    {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

function M.ensureEsp(char)
    if M.drawings[char] then return M.drawings[char] end
    local d = {
        box      = newDraw("Square", { Thickness = 1.4, Filled = false, Transparency = 1 }),
        name     = newDraw("Text",   { Size = 14, Center = true, Outline = true }),
        health   = newDraw("Text",   { Size = 13, Center = true, Outline = true }),
        dist     = newDraw("Text",   { Size = 13, Center = true, Outline = true }),
        tracer   = newDraw("Line",   { Thickness = 1.4, Transparency = 1 }),
        snap     = newDraw("Line",   { Thickness = 1.4, Transparency = 1 }),
        bones    = {},
    }
    for i = 1, #SKELETON do
        d.bones[i] = newDraw("Line", { Thickness = 1, Transparency = 1 })
    end
    M.drawings[char] = d
    return d
end

function M.hideEsp(d)
    if not d then return end
    for _, key in ipairs({"box","name","health","dist","tracer","snap"}) do
        if d[key] then d[key].Visible = false end
    end
    for _, b in ipairs(d.bones) do if b then b.Visible = false end end
end

function M.clearEsp(char)
    local d = M.drawings[char]
    if not d then return end
    for _, key in ipairs({"box","name","health","dist","tracer","snap"}) do
        if d[key] then pcall(function() d[key]:Remove() end) end
    end
    for _, b in ipairs(d.bones) do if b then pcall(function() b:Remove() end) end end
    M.drawings[char] = nil
end

function M.stepEsp()
    local alive = {}
    if M.state.esp then
        local hrp = getHRP()
        for _, char in ipairs(M.enemyChars()) do
            alive[char] = true
            local hum  = char:FindFirstChildOfClass("Humanoid")
            local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
            local root = char:FindFirstChild("HumanoidRootPart") or head
            local d = M.ensureEsp(char)
            local dist = hrp and root and (root.Position - hrp.Position).Magnitude or 0
            if not head or not root or (M.state.espMaxDist > 0 and dist > M.state.espMaxDist) then
                M.hideEsp(d)
            else
                local color = M.espColorFor(char)
                local sp, on = worldToScreen(root.Position)
                local topp   = worldToScreen((head.Position + Vector3.new(0, 1.6, 0)))
                local botp   = worldToScreen((root.Position - Vector3.new(0, 3.2, 0)))
                if on then
                    local h = math.abs(botp.Y - topp.Y)
                    local w = h * 0.62
                    -- box
                    if M.state.espBox and d.box then
                        d.box.Size = Vector2.new(w, h)
                        d.box.Position = Vector2.new(sp.X - w/2, topp.Y)
                        d.box.Color = color
                        d.box.Visible = true
                    elseif d.box then d.box.Visible = false end
                    -- name
                    if M.state.espName and d.name then
                        local pname = "?"
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr.Character == char then pname = plr.Name break end
                        end
                        d.name.Text = pname
                        d.name.Position = Vector2.new(sp.X, topp.Y - 16)
                        d.name.Color = color
                        d.name.Visible = true
                    elseif d.name then d.name.Visible = false end
                    -- health
                    if M.state.espHealth and d.health and hum then
                        d.health.Text = string.format("HP %d", math.floor(hum.Health))
                        d.health.Position = Vector2.new(sp.X, botp.Y + 2)
                        d.health.Color = Color3.fromRGB(120, 255, 120)
                        d.health.Visible = true
                    elseif d.health then d.health.Visible = false end
                    -- dist
                    if M.state.espDist and d.dist then
                        d.dist.Text = string.format("[%dm]", math.floor(dist))
                        d.dist.Position = Vector2.new(sp.X, botp.Y + 16)
                        d.dist.Color = color
                        d.dist.Visible = true
                    elseif d.dist then d.dist.Visible = false end
                    -- tracer bas-ecran
                    if M.state.espTracer and d.tracer then
                        d.tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                        d.tracer.To = sp
                        d.tracer.Color = color
                        d.tracer.Visible = true
                    elseif d.tracer then d.tracer.Visible = false end
                    -- snapline centre -> tete
                    if M.state.espSnapline and d.snap then
                        local hsp = worldToScreen(head.Position)
                        d.snap.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
                        d.snap.To = hsp
                        d.snap.Color = color
                        d.snap.Visible = true
                    elseif d.snap then d.snap.Visible = false end
                    -- skeleton
                    if M.state.espSkeleton then
                        for i, bone in ipairs(SKELETON) do
                            local p0 = char:FindFirstChild(bone[1])
                            local p1 = char:FindFirstChild(bone[2])
                            local ln = d.bones[i]
                            if p0 and p1 and ln then
                                local a, oa = worldToScreen(p0.Position)
                                local b, ob = worldToScreen(p1.Position)
                                if oa and ob then
                                    ln.From = a; ln.To = b; ln.Color = color; ln.Visible = true
                                else ln.Visible = false end
                            elseif ln then ln.Visible = false end
                        end
                    else
                        for _, b in ipairs(d.bones) do if b then b.Visible = false end end
                    end
                else
                    M.hideEsp(d)
                end
            end
        end
    end
    for char, _ in pairs(M.drawings) do
        if not alive[char] then M.clearEsp(char) end
    end
end

-- ================= AIMBOT CAMERA =================
function M.getCamTarget()
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local best, bestDist
    for _, char in ipairs(M.enemyChars()) do
        local part = char:FindFirstChild(M.state.camAimPart) or char:FindFirstChild("HumanoidRootPart")
        if part then
            local sp, on = worldToScreen(part.Position)
            if on then
                local d = (sp - center).Magnitude
                if d <= M.state.camAimFov and (not bestDist or d < bestDist) then
                    bestDist = d; best = part
                end
            end
        end
    end
    return best
end

function M.stepCamAim()
    if not M.state.camAim then return end
    if not UserInputService:IsKeyDown(M.state.camAimKey) then return end
    local part = M.getCamTarget()
    if not part then return end
    local goal = CFrame.new(Camera.CFrame.Position, part.Position)
    Camera.CFrame = Camera.CFrame:Lerp(goal, math.clamp(1 - M.state.camAimSmooth, 0.05, 1))
end

-- ================= MOVEMENT =================
function M.applyWalk()
    local hum = getHum()
    if hum then hum.WalkSpeed = M.state.walkspeed and M.state.walkspeedVal or 16 end
end
function M.applyJump()
    local hum = getHum()
    if hum then
        if M.state.jumppower then
            hum.UseJumpPower = true
            hum.JumpPower = M.state.jumppowerVal
        else
            hum.JumpPower = 50
        end
    end
end

    if M.flyBV then M.flyBV:Destroy() M.flyBV = nil end
    if M.flyBG then M.flyBG:Destroy() M.flyBG = nil end
end

-- ================= VISUALS =================
function M.applyVisuals()
    local Lighting = game:GetService("Lighting")
    if M.state.fullbright then
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(180,180,180)
    end
    if M.state.nofog then
        Lighting.FogEnd = 1e9
        Lighting.FogStart = 1e9
    end
end
function M.applyFov()
    Camera.FieldOfView = M.state.fov and M.state.fovVal or 70
end

-- ================= SHOP / LOADOUT (achat direct) =================
function M.loadoutOptions()
    local opts = { "None" }
    local seen = { None = true }
    -- 1) armes connues (table du LoadoutFramework)
    for _, n in ipairs({ "[Revolver]", "[TacticalShotgun]", "[Double-Barrel SG]", "[Knife]" }) do
        if not seen[n] then seen[n] = true; table.insert(opts, n) end
    end
    -- 2) tout ce qui est dans ReplicatedStorage.Assets.Loadout / Weapons
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local function scan(folder)
        if not folder then return end
        for _, child in ipairs(folder:GetChildren()) do
            if not seen[child.Name] then
                seen[child.Name] = true
                table.insert(opts, child.Name)
            end
        end
    end
    if assets then
        scan(assets:FindFirstChild("Loadout"))
        scan(assets:FindFirstChild("Weapons"))
        scan(assets:FindFirstChild("Guns"))
    end
    return opts
end

function M.getLoadout()
    local rf = M.remotesFolder()
    local lg = rf and rf:FindFirstChild("LoadoutGet")
    if not lg then return nil end
    local ok, res = pcall(function() return lg:InvokeServer() end)
    if ok and type(res) == "table" then return res end
    return nil
end

function M.applyLoadout()
    local rf = M.remotesFolder()
    local ld = rf and rf:FindFirstChild("Loadout")
    if not ld then
        notify("Capuche Hub", "Remote Loadout introuvable", 4)
        return false
    end
    local payload = {}
    for i = 1, 4 do
        payload[i] = M.state.loadoutSlots[i] or "None"
    end
    local ok = pcall(function() ld:FireServer(payload) end)
    if ok then
        notify("Capuche Hub", "Loadout applique (armes recues)", 3)
    end
    return ok
end

function M.refreshLoadout()
    local cur = M.getLoadout()
    if cur then
        for i = 1, 4 do
            M.state.loadoutSlots[i] = cur[i] or "None"
        end
    end
    return cur
end

-- ================= ANTI-AFK =================
function M.setupAntiAfk()
    local vu = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        if not M.state.antiafk then return end
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end)
end

-- ================= BOUCLES =================
local lastSilent, lastAura = 0, 0
function M.startLoops()
    -- rendu (ESP, tracers, aim cam, fov)
    M.conns.render = RunService.RenderStepped:Connect(function()
        pcall(M.stepEsp)
        pcall(M.stepTracers)
        pcall(M.stepCamAim)
        pcall(M.applyFov)
    end)
    -- combat + upkeep
    M.conns.heart = RunService.Heartbeat:Connect(function()
        local now = tick()
        if M.state.silent and M.state.silentAuto and now - lastSilent >= M.state.silentInterval then
            lastSilent = now
            pcall(M.doSilent)
        end
        if M.state.aura and now - lastAura >= M.state.auraInterval then
            lastAura = now
            pcall(M.stepAura)
        end
        if M.state.fullbright or M.state.nofog then pcall(M.applyVisuals) end
    end)
    -- input : silent au clic (mode non-auto) + infinite jump
    M.conns.input = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if M.state.silent and not M.state.silentAuto and input.UserInputType == M.state.silentKey then
            pcall(M.doSilent)
        end
        if M.state.infjump and input.KeyCode == Enum.KeyCode.Space then
            local hum = getHum()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)
end

-- ================= UI (Rayfield) =================
local Rayfield = (typeof(getgenv) == "function" and getgenv().XHubRayfield) or nil
if not (type(Rayfield) == "table" and Rayfield.CreateWindow) then
    local sources = {
        "https://xhub.blog/lua/rayfield.lua",
        "https://xhub-vanguard.vercel.app/lua/rayfield.lua",
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    local function httpGet(url)
        local ok, body = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(body) == "string" and #body > 100 then return body end
        ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" and #body > 100 then return body end
        for _, fn in ipairs({ request, http_request }) do
            if typeof(fn) == "function" then
                ok, body = pcall(function()
                    local r = fn({ Url = url, Method = "GET" })
                    return r and r.Body
                end)
                if ok and type(body) == "string" and #body > 100 then return body end
            end
        end
        if syn and typeof(syn.request) == "function" then
            ok, body = pcall(function()
                local r = syn.request({ Url = url, Method = "GET" })
                return r and r.Body
            end)
            if ok and type(body) == "string" and #body > 100 then return body end
        end
        return nil
    end
    for _, src in ipairs(sources) do
        local body = httpGet(src)
        if body then
            local fn = loadstring(body)
            if type(fn) == "function" then
                local ok, lib = pcall(fn)
                if ok and type(lib) == "table" and lib.CreateWindow then
                    Rayfield = lib
                    break
                end
            end
        end
    end
end
if typeof(getgenv) == "function" then getgenv().XHubRayfield = Rayfield end

-- ===== THEME MONOCHROME (noir & blanc) - Xhub =====
local XHUB_THEME = {
    TextColor = Color3.fromRGB(255, 255, 255),
    Background = Color3.fromRGB(6, 6, 8),
    Topbar = Color3.fromRGB(10, 6, 6),
    Shadow = Color3.fromRGB(0, 0, 0),
    NotificationBackground = Color3.fromRGB(12, 8, 8),
    NotificationActionsBackground = Color3.fromRGB(255, 255, 255),
    TabBackground = Color3.fromRGB(20, 12, 12),
    TabStroke = Color3.fromRGB(90, 28, 32),
    TabBackgroundSelected = Color3.fromRGB(200, 25, 35),
    TabTextColor = Color3.fromRGB(230, 220, 220),
    SelectedTabTextColor = Color3.fromRGB(255, 255, 255),
    ElementBackground = Color3.fromRGB(16, 10, 10),
    ElementBackgroundHover = Color3.fromRGB(30, 16, 16),
    SecondaryElementBackground = Color3.fromRGB(12, 8, 8),
    ElementStroke = Color3.fromRGB(75, 24, 28),
    SecondaryElementStroke = Color3.fromRGB(55, 18, 22),
    SliderBackground = Color3.fromRGB(38, 18, 20),
    SliderProgress = Color3.fromRGB(200, 25, 35),
    SliderStroke = Color3.fromRGB(230, 45, 55),
    ToggleBackground = Color3.fromRGB(26, 14, 14),
    ToggleEnabled = Color3.fromRGB(200, 25, 35),
    ToggleDisabled = Color3.fromRGB(48, 28, 30),
    ToggleEnabledStroke = Color3.fromRGB(255, 90, 100),
    ToggleDisabledStroke = Color3.fromRGB(95, 55, 58),
    ToggleEnabledOuterStroke = Color3.fromRGB(140, 35, 42),
    ToggleDisabledOuterStroke = Color3.fromRGB(38, 20, 22),
    DropdownSelected = Color3.fromRGB(34, 16, 18),
    DropdownUnselected = Color3.fromRGB(16, 10, 10),
    InputBackground = Color3.fromRGB(16, 10, 10),
    InputStroke = Color3.fromRGB(85, 30, 35),
    PlaceholderColor = Color3.fromRGB(165, 145, 145),
}
local Window = Rayfield:CreateWindow({
    Theme = XHUB_THEME,
    Name = "XHUB · Capuche RETOUR",
    LoadingTitle = "XHUB PRESENTS · CAPUCHE RETOUR",
    LoadingSubtitle = "BY MRN STUDIO & PURGATORIZZ",
    ConfigurationSaving = { Enabled = true, FolderName = "CapucheHub", FileName = "CapucheHubV1" },
    KeySystem = false,
})

-- ---------- SILENT AIM ----------
local TabSilent = Window:CreateTab("Silent Aim", 4483362458)
TabSilent:CreateSection("Silent Aim (gun)")
TabSilent:CreateToggle({ Name = "Silent Aim", CurrentValue = false, Flag = "silent",
    Callback = function(v) M.state.silent = v end })
TabSilent:CreateToggle({ Name = "Auto (tire sans clic)", CurrentValue = false, Flag = "silentAuto",
    Callback = function(v) M.state.silentAuto = v end })
TabSilent:CreateToggle({ Name = "Wallbang (traverse murs)", CurrentValue = true, Flag = "silentWall",
    Callback = function(v) M.state.silentWallbang = v end })
TabSilent:CreateToggle({ Name = "Visible seulement", CurrentValue = false, Flag = "silentVis",
    Callback = function(v) M.state.silentVisibleOnly = v end })
TabSilent:CreateToggle({ Name = "Utiliser FOV ecran", CurrentValue = true, Flag = "silentUseFov",
    Callback = function(v) M.state.silentUseFov = v end })
TabSilent:CreateSlider({ Name = "FOV (px)", Range = {20, 800}, Increment = 10, CurrentValue = 250, Flag = "silentFov",
    Callback = function(v) M.state.silentFov = v end })
TabSilent:CreateSlider({ Name = "Distance max (studs)", Range = {50, 1500}, Increment = 10, CurrentValue = 500, Flag = "silentDist",
    Callback = function(v) M.state.silentMaxDist = v end })
TabSilent:CreateSlider({ Name = "Cadence auto (s x100)", Range = {5, 100}, Increment = 1, CurrentValue = 12, Flag = "silentInt",
    Callback = function(v) M.state.silentInterval = v/100 end })
TabSilent:CreateDropdown({ Name = "Cible (partie)", Options = {"Head","HumanoidRootPart"}, CurrentOption = {"Head"}, Flag = "silentPart",
    Callback = function(v) M.state.silentPart = (type(v)=="table" and v[1]) or v end })

-- ---------- AURA ----------
local TabAura = Window:CreateTab("Aura", 4483362458)
TabAura:CreateSection("Kill Aura (gun auto)")
TabAura:CreateToggle({ Name = "Aura", CurrentValue = false, Flag = "aura",
    Callback = function(v) M.state.aura = v end })
TabAura:CreateToggle({ Name = "Wallbang", CurrentValue = true, Flag = "auraWall",
    Callback = function(v) M.state.auraWallbang = v end })
TabAura:CreateSlider({ Name = "Portee (studs)", Range = {20, 400}, Increment = 5, CurrentValue = 120, Flag = "auraRange",
    Callback = function(v) M.state.auraRange = v end })
TabAura:CreateSlider({ Name = "Cadence (s x100)", Range = {5, 100}, Increment = 1, CurrentValue = 14, Flag = "auraInt",
    Callback = function(v) M.state.auraInterval = v/100 end })
TabAura:CreateSlider({ Name = "Cibles / tick", Range = {1, 8}, Increment = 1, CurrentValue = 3, Flag = "auraMax",
    Callback = function(v) M.state.auraMax = v end })
TabAura:CreateDropdown({ Name = "Cible (partie)", Options = {"Head","HumanoidRootPart"}, CurrentOption = {"Head"}, Flag = "auraPart",
    Callback = function(v) M.state.auraPart = (type(v)=="table" and v[1]) or v end })

-- ---------- TEAM CHECK ----------
TabAura:CreateSection("Team check")
TabAura:CreateToggle({ Name = "Ignorer membres du crew", CurrentValue = true, Flag = "ignoreCrew",
    Callback = function(v) M.state.ignoreCrew = v end })
TabAura:CreateToggle({ Name = "Ignorer amis Roblox", CurrentValue = false, Flag = "ignoreFriends",
    Callback = function(v) M.state.ignoreFriends = v end })

-- ---------- TRACER ----------
TabAura:CreateSection("Tracer de tir")
TabAura:CreateToggle({ Name = "Tracer (muzzle -> cible)", CurrentValue = true, Flag = "tracer",
    Callback = function(v) M.state.tracer = v end })
TabAura:CreateColorPicker({ Name = "Couleur tracer", Color = M.state.tracerColor, Flag = "tracerColor",
    Callback = function(c) M.state.tracerColor = c end })

-- ---------- AIMBOT CAMERA ----------
local TabAim = Window:CreateTab("Aimbot", 4483362458)
TabAim:CreateSection("Aimbot camera (maintien touche)")
TabAim:CreateToggle({ Name = "Aimbot camera", CurrentValue = false, Flag = "camAim",
    Callback = function(v) M.state.camAim = v end })
TabAim:CreateSlider({ Name = "FOV (px)", Range = {20, 600}, Increment = 5, CurrentValue = 120, Flag = "camFov",
    Callback = function(v) M.state.camAimFov = v end })
TabAim:CreateSlider({ Name = "Smooth (x100)", Range = {0, 95}, Increment = 5, CurrentValue = 50, Flag = "camSmooth",
    Callback = function(v) M.state.camAimSmooth = v/100 end })
TabAim:CreateDropdown({ Name = "Cible (partie)", Options = {"Head","HumanoidRootPart"}, CurrentOption = {"Head"}, Flag = "camPart",
    Callback = function(v) M.state.camAimPart = (type(v)=="table" and v[1]) or v end })
TabAim:CreateKeybind({ Name = "Touche aimbot", CurrentKeybind = "E", HoldToInteract = false, Flag = "camKey",
    Callback = function(k)
        local ok, key = pcall(function() return Enum.KeyCode[k] end)
        if ok and key then M.state.camAimKey = key end
    end })

-- ---------- ESP ----------
local TabEsp = Window:CreateTab("ESP", 4483362458)
TabEsp:CreateToggle({ Name = "ESP", CurrentValue = false, Flag = "esp",
    Callback = function(v) M.state.esp = v; if not v then for c,_ in pairs(M.drawings) do M.clearEsp(c) end end end })
TabEsp:CreateToggle({ Name = "Box", CurrentValue = true, Flag = "espBox", Callback = function(v) M.state.espBox = v end })
TabEsp:CreateToggle({ Name = "Nom", CurrentValue = true, Flag = "espName", Callback = function(v) M.state.espName = v end })
TabEsp:CreateToggle({ Name = "Vie", CurrentValue = true, Flag = "espHealth", Callback = function(v) M.state.espHealth = v end })
TabEsp:CreateToggle({ Name = "Distance", CurrentValue = true, Flag = "espDist", Callback = function(v) M.state.espDist = v end })
TabEsp:CreateToggle({ Name = "Squelette", CurrentValue = false, Flag = "espSkel", Callback = function(v) M.state.espSkeleton = v end })
TabEsp:CreateToggle({ Name = "Tracer (bas ecran)", CurrentValue = false, Flag = "espTracer", Callback = function(v) M.state.espTracer = v end })
TabEsp:CreateToggle({ Name = "Snapline (centre -> tete)", CurrentValue = false, Flag = "espSnap", Callback = function(v) M.state.espSnapline = v end })
TabEsp:CreateSlider({ Name = "Distance max", Range = {100, 3000}, Increment = 50, CurrentValue = 1000, Flag = "espMax",
    Callback = function(v) M.state.espMaxDist = v end })
TabEsp:CreateColorPicker({ Name = "Couleur ennemi", Color = M.state.espTeamColor, Flag = "espTeamColor",
    Callback = function(c) M.state.espTeamColor = c end })
TabEsp:CreateColorPicker({ Name = "Couleur crew", Color = M.state.espCrewColor, Flag = "espCrewColor",
    Callback = function(c) M.state.espCrewColor = c end })

-- ---------- PLAYER ----------

local TabVis = Window:CreateTab("Camera / Visuals", 4483362458)
TabVis:CreateToggle({ Name = "FOV custom", CurrentValue = false, Flag = "fov",
    Callback = function(v) M.state.fov = v; M.applyFov() end })
TabVis:CreateSlider({ Name = "FOV valeur", Range = {70, 120}, Increment = 1, CurrentValue = 90, Flag = "fovVal",
    Callback = function(v) M.state.fovVal = v; M.applyFov() end })
TabVis:CreateToggle({ Name = "Fullbright", CurrentValue = false, Flag = "fullbright",
    Callback = function(v) M.state.fullbright = v; M.applyVisuals() end })
TabVis:CreateToggle({ Name = "No Fog", CurrentValue = false, Flag = "nofog",
    Callback = function(v) M.state.nofog = v; M.applyVisuals() end })

-- ---------- SHOP / LOADOUT ----------
local TabShop = Window:CreateTab("Shop / Loadout", 4483362458)
TabShop:CreateSection("Acheter les armes directement (sans se deplacer)")
TabShop:CreateParagraph({ Title = "Info", Content = "Choisis une arme par slot puis clique Appliquer. Le serveur te donne/equipe les armes via le remote Loadout, sans aller a la base." })
local loadoutOpts = M.loadoutOptions()
local slotDropdowns = {}
for i = 1, 4 do
    slotDropdowns[i] = TabShop:CreateDropdown({
        Name = "Slot " .. i,
        Options = loadoutOpts,
        CurrentOption = { M.state.loadoutSlots[i] or "None" },
        Flag = "slot" .. i,
        Callback = function(v)
            M.state.loadoutSlots[i] = (type(v) == "table" and v[1]) or v
        end,
    })
end
TabShop:CreateButton({ Name = "Appliquer / Acheter le loadout", Callback = function()
    M.applyLoadout()
end })
TabShop:CreateButton({ Name = "Rafraichir (loadout actuel)", Callback = function()
    local cur = M.refreshLoadout()
    if cur then
        for i = 1, 4 do
            pcall(function() slotDropdowns[i]:Set({ M.state.loadoutSlots[i] or "None" }) end)
        end
        notify("Capuche Hub", "Loadout actuel charge", 3)
    else
        notify("Capuche Hub", "Impossible de lire le loadout", 4)
    end
end })
TabShop:CreateButton({ Name = "Tout armes (Revolver/SG/Shotgun/Knife)", Callback = function()
    M.state.loadoutSlots = { "[Revolver]", "[TacticalShotgun]", "[Double-Barrel SG]", "[Knife]" }
    for i = 1, 4 do pcall(function() slotDropdowns[i]:Set({ M.state.loadoutSlots[i] }) end) end
    M.applyLoadout()
end })

-- ---------- SERVER ----------
local TabServer = Window:CreateTab("Server", 4483362458)
TabServer:CreateToggle({ Name = "Anti-AFK", CurrentValue = true, Flag = "antiafk",
    Callback = function(v) M.state.antiafk = v end })
TabServer:CreateButton({ Name = "Rejoin", Callback = function()
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end })
TabServer:CreateButton({ Name = "Server Hop (nouveau serveur)", Callback = function()
    local HttpService = game:GetService("HttpService")
    local ok, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
    end)
    if ok and servers and servers.data then
        for _, s in ipairs(servers.data) do
            if s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.id ~= game.JobId then
                pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer) end)
                return
            end
        end
    end
    notify("Capuche Hub", "Aucun serveur trouve", 4)
end })

-- ---------- PANIC / CONFIG ----------
local TabConfig = Window:CreateTab("Panic / Config", 4483362458)
TabConfig:CreateButton({ Name = "PANIC (tout off)", Callback = function()
    M.state.silent=false; M.state.silentAuto=false; M.state.aura=false
    M.state.camAim=false; M.state.esp=false
    M.applyWalk(); M.applyJump()
    for c,_ in pairs(M.drawings) do M.clearEsp(c) end
    notify("Capuche Hub", "PANIC : toutes les features desactivees", 3)
end })
TabConfig:CreateKeybind({ Name = "Toggle UI", CurrentKeybind = "RightShift", HoldToInteract = false, Flag = "toggleUI",
    Callback = function() end })

local TabCredits = Window:CreateTab("Credits", 4483362458)
TabCredits:CreateParagraph({ Title = "Capuche RETOUR Hub V1", Content = "BY XHUB 2026\nSilent aim + Aura + Tracer + ESP + Aimbot + Shop direct (Loadout).\nCombat client-autoritaire (ShootGun). Utilise en solo pour tester." })

-- ================= INIT =================
M.setupAntiAfk()
M.startLoops()

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    pcall(M.applyWalk)
    pcall(M.applyJump)
    pcall(M.applyFov)
    pcall(M.applyVisuals)
end)

notify("Capuche RETOUR Hub V1", "Charge. Silent + Aura + Shop direct prets.", 5)


--[XHUB_CFG_RELOAD]
task.defer(function()
    task.wait(0.5)
    pcall(function()
        if Rayfield and Rayfield.LoadConfiguration then Rayfield:LoadConfiguration() end
    end)
end)
