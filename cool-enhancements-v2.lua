--[[
    Cool Enhancements v1.5
    5 ports from Splash base + wall check fix + rebrand
    Unload: getgenv().rivals.unload()
--]]

if getgenv().rivals and getgenv().rivals.loaded then
    pcall(function() getgenv().rivals.unload() end)
end

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")
local StarterGui         = game:GetService("StarterGui")
local Lighting           = game:GetService("Lighting")
local SoundService       = game:GetService("SoundService")
local AssetService       = game:GetService("AssetService")

local LocalPlayer        = Players.LocalPlayer
local Camera             = Workspace.CurrentCamera

local BRAND = "Cool Enhancements"

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 3 })
    end)
end

local EX = { has = {
    sethiddenprop = type(sethiddenproperty) == "function",
    getrawmeta    = type(getrawmetatable) == "function",
} }

local Mods = {}
local function req(path, timeout)
    timeout = timeout or 10
    local deadline = tick() + timeout
    local node = ReplicatedStorage
    for _, seg in ipairs(path) do
        if typeof(node) == "Instance" then
            node = node:WaitForChild(seg, math.max(0.1, deadline - tick()))
        else return nil end
        if not node then return nil end
    end
    local ok, m = pcall(require, node)
    if ok then return m end
    return nil
end
local function refresh_modules()
    Mods.Utility         = req({"Modules", "Utility"})
    Mods.EnumLibrary     = req({"Modules", "EnumLibrary"})
    Mods.ItemLibrary     = req({"Modules", "ItemLibrary"})
    Mods.CosmeticLibrary = req({"Modules", "CosmeticLibrary"})
    pcall(function()
        local ps = LocalPlayer:WaitForChild("PlayerScripts", 8)
        local ctrls = ps and ps:WaitForChild("Controllers", 8)
        local fm = ctrls and ctrls:WaitForChild("FighterController", 8)
        if fm then local ok, m = pcall(require, fm) if ok then Mods.Fighter = m end end
    end)
end
refresh_modules()

local Connections = {}
local function track(c) if c then Connections[#Connections+1] = c end return c end
local function disconnect_all()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
end

-- TT LOOKBACK
local TT = { live = {}, ALPHA_MIN = 0.15, ALPHA_MAX = 0.55 }
local function ok_num(n) return n == n and math.abs(n) ~= math.huge end
local function ok_vec(v) return v and ok_num(v.X) and ok_num(v.Y) and ok_num(v.Z) end

local function read_cf(part)
    if not part then return nil end
    local ok, cf = pcall(function() return part.CFrame end)
    if ok and cf and ok_vec(cf.Position) then return cf end
    if EX.has.getrawmeta then
        local mt_ok, mt = pcall(getrawmetatable, part)
        if mt_ok and mt then
            local idx = rawget(mt, "__index")
            if idx then
                local ni_ok, raw_cf = pcall(idx, part, "CFrame")
                if ni_ok and raw_cf and ok_vec(raw_cf.Position) then return raw_cf end
            end
        end
    end
    return nil
end

local function tt_record(part, cf, now)
    if not part or not cf then return end
    local x, y, z = cf.X, cf.Y, cf.Z
    if not (ok_num(x) and ok_num(y) and ok_num(z)) then return end
    local live = TT.live[part]
    if not live then
        TT.live[part] = { x=x, y=y, z=z, t=now, lkg_x=x, lkg_y=y, lkg_z=z, vx=0, vy=0, vz=0 }
    else
        local dt = now - live.t
        if dt > 0.0001 then
            local rvx = (x - live.x) / dt
            local rvy = (y - live.y) / dt
            local rvz = (z - live.z) / dt
            local speed = math.sqrt(rvx^2 + rvy^2 + rvz^2)
            local a = math.clamp(TT.ALPHA_MIN + (speed/5000)*(TT.ALPHA_MAX - TT.ALPHA_MIN), TT.ALPHA_MIN, TT.ALPHA_MAX)
            live.vx = live.vx*(1-a) + rvx*a
            live.vy = live.vy*(1-a) + rvy*a
            live.vz = live.vz*(1-a) + rvz*a
        end
        local jump = math.sqrt((x-live.lkg_x)^2 + (y-live.lkg_y)^2 + (z-live.lkg_z)^2)
        if jump < 50000 then live.lkg_x, live.lkg_y, live.lkg_z = x, y, z end
        live.x, live.y, live.z, live.t = x, y, z, now
    end
end

local function tt_best(part)
    local live = TT.live[part]
    if not live then local cf = read_cf(part) return cf and cf.Position end
    return Vector3.new(live.lkg_x, live.lkg_y, live.lkg_z)
end

local function tt_predict(part, ping, blend)
    blend = math.clamp(tonumber(blend) or 0, 0, 1)
    if blend <= 0.001 then return tt_best(part) end
    local live = TT.live[part]
    if not live then return tt_best(part) end
    local pos = Vector3.new(live.lkg_x, live.lkg_y, live.lkg_z)
    local speed = math.sqrt(live.vx^2 + live.vy^2 + live.vz^2)
    if speed < 1 then return pos end
    local t = math.clamp((ping or 0.05) * blend, 0, 0.15)
    local pred = Vector3.new(pos.X + live.vx*t, pos.Y + live.vy*t, pos.Z + live.vz*t)
    if ok_vec(pred) then return pred end
    return pos
end

local function tt_ping()
    local ok, s = pcall(function() return game:GetService("Stats") end)
    if ok and s then
        local ok2, p = pcall(function() return s.Network.ServerStatsItem["Data Ping"].Value end)
        if ok2 and ok_num(p) then return math.clamp(p/1000, 0, 0.4) end
    end
    return 0.05
end

local function my_char() return LocalPlayer.Character end
local function my_hrp() local c = my_char() return c and c:FindFirstChild("HumanoidRootPart") end
local function alive(c)
    if not c or not c.Parent then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    return c:FindFirstChild("HumanoidRootPart") ~= nil
end

-- PORT 2: ANTI-KATANA + ANTI-RIOT
local DeflectState = { by_player = {} }
local RiotState    = { by_player = {} }

do
    pcall(function()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local katana = ps and ps.Modules and ps.Modules.Items and ps.Modules.Items:FindFirstChild("Katana")
        if katana then
            local ok, mod = pcall(require, katana)
            if ok and type(mod) == "table" and mod.StartAiming then
                local old = mod.StartAiming
                mod.StartAiming = function(self, force)
                    local fighter = self.ClientFighter
                    local plr = fighter and fighter.Player
                    if plr then
                        DeflectState.by_player[plr] = true
                        local dur = (self.Info and self.Info.DeflectDuration) or 0.6
                        task.delay(dur, function() DeflectState.by_player[plr] = nil end)
                    end
                    return old(self, force)
                end
            end
        end
    end)

    local function scan_riot()
        local vm = Workspace:FindFirstChild("ViewModels")
        if not vm then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                RiotState.by_player[plr] = vm:FindFirstChild(plr.Name .. " - Riot Shield - Riot Shield") ~= nil
            end
        end
    end
    track(RunService.Heartbeat:Connect(scan_riot))
end

local function is_deflecting(plr) return DeflectState.by_player[plr] == true end
local function has_riot(plr) return RiotState.by_player[plr] == true end

-- AIMBOT STATE
local AimState = {
    enabled=false, fov=120, smoothness=0.15, target_part="Head",
    wall_check=true, team_check=true, priority="Closest",
    method="Keybind", keybind_key=Enum.KeyCode.Q,
    is_held=false, is_toggled=false,
    locked_target=nil, smooth_cf=nil, aim_curve="linear",
    predictive=5, fire_method="camera", show_fov_circle=true, override=nil,
    _los_tick = 0,
}

local cam_controller
pcall(function()
    local ps = LocalPlayer:WaitForChild("PlayerScripts", 8)
    local ctrls = ps and ps:WaitForChild("Controllers", 8)
    local cm = ctrls and ctrls:WaitForChild("CameraController", 8)
    if cm then local ok, m = pcall(require, cm) if ok then cam_controller = m end end
end)

-- COMBAT
local Combat = {}
Combat.get_target = function(cfg)
    cfg = cfg or {}
    local myhrp = my_hrp()
    if not myhrp then return nil end
    local mypos = myhrp.Position
    local myteam = LocalPlayer:GetAttribute("TeamID") or LocalPlayer.Team
    local best, best_score = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and alive(p.Character) then
            if not p.Character:FindFirstChildOfClass("ForceField") then
                local theirteam = p:GetAttribute("TeamID") or p.Team
                local same = myteam and theirteam and myteam == theirteam
                if not (cfg.team_check and same) then
                    if not is_deflecting(p) and not has_riot(p) then
                        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                        local head = p.Character:FindFirstChild("Head")
                        if hrp and head then
                            local dist = (mypos - hrp.Position).Magnitude
                            if not cfg.max_dist or dist <= cfg.max_dist then
                                local los = true
                                if cfg.wall_check then
                                    local rp = RaycastParams.new()
                                    rp.FilterType = Enum.RaycastFilterType.Exclude
                                    rp.IgnoreWater = true
                                    local filter = {}
                                    local mc = my_char()
                                    if mc then filter[#filter+1] = mc end
                                    if p.Character then filter[#filter+1] = p.Character end
                                    rp.FilterDescendantsInstances = filter
                                    local hit = Workspace:Raycast(Camera.CFrame.Position, head.Position - Camera.CFrame.Position, rp)
                                    if hit then los = false end
                                end
                                if los then
                                    local score = (mypos - head.Position).Magnitude
                                    if cfg.prefer_low_hp then
                                        local hum = p.Character:FindFirstChildOfClass("Humanoid")
                                        if hum then score = score + hum.Health * 0.5 end
                                    end
                                    if score < best_score then best_score = score best = p end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- WALL CHECK FIX
local function find_aim_target()
    local myhrp = my_hrp()
    if not myhrp then return nil end
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local myteam = LocalPlayer:GetAttribute("TeamID") or LocalPlayer.Team
    local vs = cam.ViewportSize
    local center_v = Vector2.new(vs.X / 2, vs.Y / 2)
    local my_c = my_char()

    local candidates = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and alive(p.Character) then
            if not p.Character:FindFirstChildOfClass("ForceField") then
                local theirteam = p:GetAttribute("TeamID") or p.Team
                local same = myteam and theirteam and myteam == theirteam
                if not (AimState.team_check and same) then
                    if not is_deflecting(p) and not has_riot(p) then
                        local part = p.Character:FindFirstChild(AimState.target_part) or p.Character:FindFirstChild("Head")
                        if part then
                            local v, on = cam:WorldToViewportPoint(part.Position)
                            if on and v.Z > 0 then
                                local dx = v.X - center_v.X
                                local dy = v.Y - center_v.Y
                                local sd = math.sqrt(dx*dx + dy*dy)
                                if sd <= AimState.fov then
                                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                                    local score = sd
                                    if AimState.priority == "LowestHP" and hum then
                                        score = hum.Health * 10 + sd * 0.1
                                    elseif AimState.priority == "Closest" then
                                        score = (myhrp.Position - part.Position).Magnitude
                                    end
                                    candidates[#candidates+1] = { head = part, char = p.Character, score = score }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a,b) return a.score < b.score end)

    if not AimState.wall_check then return candidates[1].head end

    local cam_pos = cam.CFrame.Position
    for _, c in ipairs(candidates) do
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.IgnoreWater = true
        local filter = {}
        if my_c then filter[#filter+1] = my_c end
        if c.char then filter[#filter+1] = c.char end
        rp.FilterDescendantsInstances = filter
        local hit = Workspace:Raycast(cam_pos, c.head.Position - cam_pos, rp)
        if not hit then return c.head end
    end

    return nil  -- all occluded: no snap
end

-- LOS CHECK helper
local function target_has_los(part)
    if not part or not part.Parent then return false end
    local cam = Workspace.CurrentCamera
    if not cam then return false end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local filter = {}
    local mc = my_char()
    if mc then filter[#filter+1] = mc end
    if part.Parent then filter[#filter+1] = part.Parent end
    rp.FilterDescendantsInstances = filter
    local hit = Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, rp)
    return hit == nil
end

local function aim_step(dt)
    if AimState.override then pcall(AimState.override, dt) return end
    if not AimState.enabled then AimState.smooth_cf = nil return end
    local should
    if AimState.method == "Always" then should = true
    elseif AimState.method == "Toggle" then should = AimState.is_toggled
    else should = AimState.is_held end
    if not should then AimState.smooth_cf = nil return end

    local part = AimState.locked_target
    AimState._los_tick = (AimState._los_tick or 0) + 1

    -- invalidate target: dead, gone, or (wall_check on + re-check says occluded)
    local invalid = false
    if part then
        if not part.Parent or not alive(part.Parent) then
            invalid = true
        elseif AimState.wall_check and AimState._los_tick % 10 == 0 then
            if not target_has_los(part) then
                invalid = true
            end
        end
    end
    if invalid then
        AimState.locked_target = nil
        part = nil
    end

    if not part then
        part = find_aim_target()
        AimState.locked_target = part
    end
    if not part then return end

    local cam = Workspace.CurrentCamera
    if not cam then return end
    local blend = AimState.predictive / 100
    local aim_pos = tt_predict(part, tt_ping(), blend) or part.Position
    local origin = cam.CFrame.Position
    local look = CFrame.lookAt(origin, aim_pos)

    if not AimState.smooth_cf then
        AimState.smooth_cf = look
    else
        local smooth = math.clamp(tonumber(AimState.smoothness) or 0.15, 0.02, 20)
        local speed = 6 / smooth
        local alpha
        if AimState.aim_curve == "linear" then alpha = math.clamp(speed*dt, 0, 1)
        elseif AimState.aim_curve == "ease" then local t = math.clamp(speed*dt, 0, 1) alpha = t*t*(3-2*t)
        else alpha = 1 - math.exp(-(4/smooth)*dt) end
        AimState.smooth_cf = AimState.smooth_cf:Lerp(look, alpha)
    end

    if cam_controller and cam_controller.MimicRotation then
        pcall(function() cam_controller:MimicRotation(AimState.smooth_cf) end)
    else
        pcall(function() cam.CFrame = AimState.smooth_cf end)
    end
end

local AIM_BIND = "ce_aim"
function AimState.set_enabled(v)
    AimState.enabled = v
    if v then
        pcall(function()
            RunService:UnbindFromRenderStep(AIM_BIND)
            RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, aim_step)
        end)
    else
        pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
        AimState.locked_target = nil
        AimState.smooth_cf = nil
    end
end

track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == AimState.keybind_key then
        if AimState.method == "Keybind" then AimState.is_held = true AimState.smooth_cf = nil end
        if AimState.method == "Toggle" and not AimState.is_toggled then AimState.is_toggled = true AimState.smooth_cf = nil
        elseif AimState.method == "Toggle" then AimState.is_toggled = false end
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == AimState.keybind_key and AimState.method == "Keybind" then AimState.is_held = false end
end))

-- FOV circle
local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1.5
fov_circle.NumSides = 64
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.Color = Color3.fromRGB(255, 255, 255)
track(RunService.RenderStepped:Connect(function()
    if not AimState.enabled or not AimState.show_fov_circle then
        fov_circle.Visible = false
        return
    end
    local cam = workspace.CurrentCamera
    if not cam then fov_circle.Visible = false return end
    local vs = cam.ViewportSize
    fov_circle.Position = Vector2.new(vs.X / 2, vs.Y / 2)
    fov_circle.Radius = AimState.fov
    fov_circle.Visible = true
end))
track(function() pcall(function() fov_circle:Remove() end) end)

-- PORT 1: SILENT AIM VIA RAYCAST HOOK
local SilentState = {
    enabled=false, hit_part="Head", auto_fire=false,
    wall_check=true, team_check=true, hit_chance=100, max_dist=2000,
    through_wall=false, raycast_hook_installed=false,
}
local SilentLast = 0

local function pick_target()
    return Combat.get_target and Combat.get_target({
        team_check = SilentState.team_check,
        wall_check = (not SilentState.through_wall) and SilentState.wall_check or false,
        max_dist   = SilentState.max_dist,
    })
end

if Mods.Utility and Mods.Utility.Raycast then
    local old_raycast = Mods.Utility.Raycast
    Mods.Utility.Raycast = function(...)
        if SilentState.enabled then
            local caller_name = nil
            pcall(function() caller_name = debug.info(3, "n") end)
            if caller_name == "StartShooting" then
                if math.random(1, 100) <= SilentState.hit_chance then
                    local target = pick_target()
                    if target and target.Character then
                        local part = target.Character:FindFirstChild(SilentState.hit_part)
                            or target.Character:FindFirstChild("Head")
                            or target.Character:FindFirstChild("HumanoidRootPart")
                        if part then
                            local aim_pos = tt_predict(part, tt_ping(), AimState.predictive / 100) or part.Position
                            local args = { ... }
                            if type(args[2]) == "Vector3" then
                                args[2] = (aim_pos - args[1])
                            end
                            return old_raycast(table.unpack(args))
                        end
                    end
                end
            end
        end
        return old_raycast(...)
    end
    SilentState.raycast_hook_installed = true
end

local function silent_step()
    if not SilentState.enabled then return end
    if not alive(my_char()) then return end
    local f = Mods.Fighter
    if not f or not f.LocalFighter or not f.LocalFighter.EquippedItem then return end
    local now = os.clock()
    if now - SilentLast < (1/25) then return end
    SilentLast = now
    if not SilentState.auto_fire and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    local target = pick_target()
    if not target or not target.Character then return end
    pcall(function() f.LocalFighter:Input("StartShooting") end)
end
track(RunService.Heartbeat:Connect(silent_step))

-- PORT 3: CUSTOM HIT SOUNDS
local HitSoundState = {
    enabled = false, selected = "Rust HS",
    volume = 0.5, pitch = 1.0,
    remove_default = false,
    raycast_hook_installed = false,
}

local hitsound_ids = {
    ["Rust HS"]       = "rbxassetid://1255040462",
    ["Neverlose"]     = "rbxassetid://97643101798871",
    ["Minecraft Bow"] = "rbxassetid://3442683707",
    ["Minecraft Hit"] = "rbxassetid://8766809464",
    ["CSGO"]          = "rbxassetid://5764885315",
    ["Bubble"]        = "rbxassetid://6534947588",
    ["Laser"]         = "rbxassetid://130791043",
    ["Pop"]           = "rbxassetid://198598793",
    ["Sans"]          = "rbxassetid://3188795283",
    ["Bonk"]          = "rbxassetid://5766898159",
}
local hitsound_names = {}
for name in pairs(hitsound_ids) do hitsound_names[#hitsound_names+1] = name end
table.sort(hitsound_names)

local function play_hitsound()
    if not HitSoundState.enabled then return end
    local id = hitsound_ids[HitSoundState.selected]
    if not id then return end
    local snd = Instance.new("Sound")
    snd.SoundId = id
    snd.Volume = HitSoundState.volume
    snd.PlaybackSpeed = HitSoundState.pitch
    local cam = Workspace.CurrentCamera
    if cam then
        local att = Instance.new("Attachment")
        att.Parent = cam
        snd.Parent = att
    else
        snd.Parent = Workspace
    end
    snd:Play()
    game:GetService("Debris"):AddItem(snd, 5)
end

pcall(function()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local cvm = ps and ps.Modules and ps.Modules.ClientReplicatedClasses
        and ps.Modules.ClientReplicatedClasses.ClientFighter
        and ps.Modules.ClientReplicatedClasses.ClientFighter.ClientItem
        and ps.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
    if cvm then
        local ok, mod = pcall(require, cvm)
        if ok and type(mod) == "table" and mod.PlayHitmarkerSound then
            local old = mod.PlayHitmarkerSound
            mod.PlayHitmarkerSound = function(self, critical, pitch)
                play_hitsound()
                if HitSoundState.remove_default then
                    return
                end
                return old(self, critical, pitch)
            end
            HitSoundState.raycast_hook_installed = true
        end
    end
end)

-- PORT 5: DAMAGE NUMBERS
local DamageState = {
    enabled = false,
    remove_ingame = false,
    color_type = "Gradient",
    color1 = Color3.fromRGB(255, 80, 80),
    color2 = Color3.fromRGB(255, 210, 90),
    duration = 0.8,
    rise = 42,
    text_size = 18,
    raycast_hook_installed = false,
}

local DamageGui = Instance.new("ScreenGui")
DamageGui.Name = "\0ce_dmg"
DamageGui.ResetOnSpawn = false
DamageGui.IgnoreGuiInset = true
DamageGui.DisplayOrder = 500
DamageGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
track(function() pcall(function() DamageGui:Destroy() end) end)

local function spawn_damage_number(pos, amount, is_headshot)
    local cfg = DamageState
    local sp, on = Camera:WorldToViewportPoint(pos)
    if not on then return end
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.fromOffset(140, 26)
    lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.Position = UDim2.fromOffset(sp.X, sp.Y)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = cfg.text_size
    lbl.Text = "-" .. tostring(math.floor(amount + 0.5))
    lbl.TextStrokeTransparency = 1
    lbl.TextColor3 = cfg.color1
    lbl.ZIndex = 10
    lbl.Parent = DamageGui

    local stroke = Instance.new("UIStroke", lbl)
    stroke.Thickness = 1.5
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Transparency = 0.15
    stroke.LineJoinMode = Enum.LineJoinMode.Round

    local scale = Instance.new("UIScale", lbl)
    scale.Scale = 0.5

    if cfg.color_type == "Gradient" then
        local grad = Instance.new("UIGradient", lbl)
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, cfg.color1),
            ColorSequenceKeypoint.new(1, cfg.color2),
        })
        grad.Rotation = 90
        lbl.TextColor3 = Color3.new(1, 1, 1)
    end

    local startX, startY = sp.X, sp.Y
    local jitter = math.random(-14, 14)
    local start = tick()
    local dur = cfg.duration
    local rise = cfg.rise
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local t = (tick() - start) / dur
        if t >= 1 then
            conn:Disconnect()
            pcall(function() lbl:Destroy() end)
            return
        end
        local ease = 1 - (1 - t) * (1 - t) * (1 - t)
        if cfg.color_type == "Rainbow" then
            lbl.TextColor3 = Color3.fromHSV((tick() * 0.6) % 1, 0.75, 1)
        end
        local s
        if t < 0.16 then
            s = 0.5 + (t / 0.16) * 0.62
        else
            s = 1.12 - ((t - 0.16) / 0.84) * 0.12
        end
        scale.Scale = s
        local fade = t < 0.55 and 0 or (t - 0.55) / 0.45
        lbl.Position = UDim2.fromOffset(startX + jitter * ease, startY - rise * ease)
        lbl.TextTransparency = fade
        stroke.Transparency = 0.15 + 0.85 * fade
    end)
end

pcall(function()
    local fighter = Mods.Fighter
    if not fighter then return end
    local old = fighter.ReplicateFromServer
    if not old then return end
    fighter.ReplicateFromServer = function(self, _type, ...)
        if _type == "DamageNumberEffect" then
            local args = { ... }
            local hit_root, hit_dmg, headshot = args[1], args[2], args[3]
            if hit_root and hit_dmg and hit_root.Parent then
                local plr = Players:GetPlayerFromCharacter(hit_root.Parent)
                if plr then
                    local pos
                    pcall(function()
                        pos = hit_root.Position + Vector3.new(0, headshot and 2.6 or 2.1, 0)
                    end)
                    if pos and DamageState.enabled then
                        spawn_damage_number(pos, hit_dmg, headshot)
                    end
                end
            end
            if DamageState.remove_ingame then
                return
            end
        end
        return old(self, _type, ...)
    end
    DamageState.raycast_hook_installed = true
end)

-- PORT 4: RADAR
local RadarState = {
    enabled = false,
    sample_grid = 32,
    range = 200,
    blip_size = 3,
    gui = nil,
    editable = nil,
    canvas = nil,
    pixel_frames = nil,
    last_sample = 0,
    sample_interval = 1.0,
    blips = {},
    blip_pool = 32,
    center_dot = nil,
    arrow = nil,
    mode = nil,
}

local function build_radar_gui()
    if RadarState.gui then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "\0ce_radar"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    RadarState.gui = gui

    local holder = Instance.new("Frame")
    holder.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    holder.BorderColor3 = Color3.fromRGB(60, 60, 70)
    holder.BorderSizePixel = 1
    holder.Size = UDim2.fromOffset(220, 250)
    holder.Position = UDim2.fromOffset(20, 60)
    holder.Active = true
    holder.Parent = gui
    RadarState.holder = holder

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 22)
    title.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
    title.BorderSizePixel = 0
    title.Text = "  Cool Enhancements — radar"
    title.Font = Enum.Font.Code
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(200, 200, 210)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = holder

    local map_frame = Instance.new("Frame")
    map_frame.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    map_frame.BorderColor3 = Color3.fromRGB(60, 60, 70)
    map_frame.BorderSizePixel = 1
    map_frame.Size = UDim2.new(1, -8, 1, -30)
    map_frame.Position = UDim2.fromOffset(4, 26)
    map_frame.ClipsDescendants = true
    map_frame.Parent = holder
    RadarState.map_frame = map_frame

    local try_ok, img = pcall(function()
        return AssetService:CreateEditableImage({ Size = Vector2.new(RadarState.sample_grid, RadarState.sample_grid) })
    end)
    if not try_ok or not img then
        try_ok, img = pcall(function()
            local i = Instance.new("EditableImage")
            i.Size = Vector2.new(RadarState.sample_grid, RadarState.sample_grid)
            return i
        end)
    end

    if try_ok and img then
        RadarState.editable = img
        local image_label = Instance.new("ImageLabel")
        image_label.Size = UDim2.fromScale(1, 1)
        image_label.BackgroundTransparency = 1
        image_label.Image = img
        image_label.ScaleType = Enum.ScaleType.Stretch
        image_label.Parent = map_frame
        RadarState.canvas = image_label
        RadarState.mode = "editable"
    else
        local grid_frame = Instance.new("Frame")
        grid_frame.BackgroundTransparency = 1
        grid_frame.Size = UDim2.fromScale(1, 1)
        grid_frame.Parent = map_frame
        RadarState.pixel_frames = {}
        for row = 0, RadarState.sample_grid - 1 do
            for col = 0, RadarState.sample_grid - 1 do
                local px = Instance.new("Frame")
                px.BorderSizePixel = 0
                px.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
                px.Position = UDim2.fromScale(col / RadarState.sample_grid, row / RadarState.sample_grid)
                px.Size = UDim2.fromScale(1 / RadarState.sample_grid, 1 / RadarState.sample_grid)
                px.Parent = grid_frame
                RadarState.pixel_frames[row * RadarState.sample_grid + col + 1] = px
            end
        end
        RadarState.mode = "frames"
    end

    local crossH = Instance.new("Frame")
    crossH.BackgroundColor3 = Color3.fromRGB(200, 200, 210)
    crossH.BackgroundTransparency = 0.7
    crossH.BorderSizePixel = 0
    crossH.Size = UDim2.new(1, 0, 0, 1)
    crossH.Position = UDim2.fromScale(0, 0.5)
    crossH.Parent = map_frame

    local crossV = Instance.new("Frame")
    crossV.BackgroundColor3 = Color3.fromRGB(200, 200, 210)
    crossV.BackgroundTransparency = 0.7
    crossV.BorderSizePixel = 0
    crossV.Size = UDim2.new(0, 1, 1, 0)
    crossV.Position = UDim2.fromScale(0.5, 0)
    crossV.Parent = map_frame

    local dot = Instance.new("Frame")
    dot.BackgroundColor3 = Color3.fromRGB(0, 186, 255)
    dot.BorderSizePixel = 0
    dot.Size = UDim2.fromOffset(4, 4)
    dot.Position = UDim2.fromScale(0.5, 0.5)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Parent = map_frame
    local dc = Instance.new("UICorner")
    dc.CornerRadius = UDim.new(1, 0)
    dc.Parent = dot
    RadarState.center_dot = dot

    local arrow = Instance.new("TextLabel")
    arrow.BackgroundTransparency = 1
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Position = UDim2.fromScale(0.5, 0.5)
    arrow.Size = UDim2.fromOffset(16, 16)
    arrow.Text = "▲"
    arrow.TextSize = 13
    arrow.TextColor3 = Color3.fromRGB(0, 186, 255)
    arrow.Font = Enum.Font.Code
    arrow.Parent = map_frame
    RadarState.arrow = arrow

    for i = 1, RadarState.blip_pool do
        local b = Instance.new("Frame")
        b.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
        b.BorderSizePixel = 0
        b.Size = UDim2.fromOffset(RadarState.blip_size, RadarState.blip_size)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Visible = false
        b.Parent = map_frame
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(1, 0)
        bc.Parent = b
        RadarState.blips[i] = b
    end
end

local function radar_sample_terrain()
    local char = my_char()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local origin = root.Position
    local grid = RadarState.sample_grid
    local half = grid / 2
    local step = (RadarState.range * 2) / grid
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { char }

    if RadarState.mode == "editable" and RadarState.editable then
        for row = 0, grid - 1 do
            for col = 0, grid - 1 do
                local offsetX = (col - half + 0.5) * step
                local offsetZ = (row - half + 0.5) * step
                local sample = origin + Vector3.new(offsetX, 0, offsetZ)
                local result = Workspace:Raycast(sample + Vector3.new(0, 512, 0), Vector3.new(0, -1024, 0), rp)
                local color = result and result.Instance:IsA("BasePart") and result.Instance.Color or Color3.fromRGB(10, 10, 12)
                if result and result.Instance == Workspace.Terrain then
                    local ok, c = pcall(function() return Workspace.Terrain:GetMaterialColor(result.Material) end)
                    if ok and c then color = c end
                end
                pcall(function() RadarState.editable:WritePixels(Vector2.new(col, row), Vector2.new(1, 1), { color }) end)
            end
        end
    else
        for row = 0, grid - 1 do
            for col = 0, grid - 1 do
                local offsetX = (col - half + 0.5) * step
                local offsetZ = (row - half + 0.5) * step
                local sample = origin + Vector3.new(offsetX, 0, offsetZ)
                local result = Workspace:Raycast(sample + Vector3.new(0, 512, 0), Vector3.new(0, -1024, 0), rp)
                local color = result and result.Instance:IsA("BasePart") and result.Instance.Color or Color3.fromRGB(10, 10, 12)
                if result and result.Instance == Workspace.Terrain then
                    local ok, c = pcall(function() return Workspace.Terrain:GetMaterialColor(result.Material) end)
                    if ok and c then color = c end
                end
                local px = RadarState.pixel_frames[row * grid + col + 1]
                if px then px.BackgroundColor3 = color end
            end
        end
    end
end

local function radar_update_blips()
    local char = my_char()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local origin = root.Position
    local rng = RadarState.range
    local idx = 0
    local myteam = LocalPlayer:GetAttribute("TeamID") or LocalPlayer.Team
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and alive(plr.Character) then
            local theirteam = plr:GetAttribute("TeamID") or plr.Team
            local same = myteam and theirteam and myteam == theirteam
            if not same then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    idx = idx + 1
                    if idx > RadarState.blip_pool then break end
                    local b = RadarState.blips[idx]
                    local offset = hrp.Position - origin
                    local nx = offset.X / rng
                    local nz = offset.Z / rng
                    if nx*nx + nz*nz > 1 then
                        local d = math.sqrt(nx*nx + nz*nz)
                        nx = nx / d
                        nz = nz / d
                    end
                    b.Position = UDim2.fromScale(nx * 0.5 + 0.5, nz * 0.5 + 0.5)
                    b.Visible = true
                end
            end
        end
    end
    for i = idx + 1, RadarState.blip_pool do
        if RadarState.blips[i] then RadarState.blips[i].Visible = false end
    end
    local look = Camera.CFrame.LookVector
    if RadarState.arrow then RadarState.arrow.Rotation = math.deg(math.atan2(look.X, -look.Z)) end
end

track(RunService.Heartbeat:Connect(function()
    if not RadarState.enabled then
        if RadarState.gui then RadarState.gui.Enabled = false end
        return
    end
    if not RadarState.gui then build_radar_gui() end
    RadarState.gui.Enabled = true
    local now = tick()
    if now - RadarState.last_sample >= RadarState.sample_interval then
        RadarState.last_sample = now
        pcall(radar_sample_terrain)
    end
    pcall(radar_update_blips)
end))

function RadarState.set_enabled(v)
    RadarState.enabled = v
    if not v and RadarState.gui then
        RadarState.gui.Enabled = false
    end
end

track(function()
    if RadarState.gui then pcall(function() RadarState.gui:Destroy() end) end
end)

-- GLUE
local GlueState = { enabled=false, distance=0, height=0, target_name="Closest", weld=nil }
local glue_conn
local function glue_destroy_weld()
    if GlueState.weld then pcall(function() GlueState.weld:Destroy() end) GlueState.weld = nil end
end
local function glue_step()
    if not GlueState.enabled then return end
    local hrp = my_hrp()
    if not hrp then glue_destroy_weld() return end
    local tgt_p
    if GlueState.target_name ~= "Closest" then tgt_p = Players:FindFirstChild(GlueState.target_name) end
    if not (tgt_p and tgt_p.Character and alive(tgt_p.Character)) then
        local best, best_d = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and alive(p.Character) then
                local th = p.Character:FindFirstChild("HumanoidRootPart")
                if th then
                    local d = (hrp.Position - th.Position).Magnitude
                    if d < best_d then best_d = d best = p end
                end
            end
        end
        tgt_p = best
    end
    if not tgt_p or not tgt_p.Character then glue_destroy_weld() return end
    local tgt = tgt_p.Character:FindFirstChild("Head") or tgt_p.Character:FindFirstChild("HumanoidRootPart")
    if not tgt then glue_destroy_weld() return end
    if GlueState.weld and GlueState.weld.Parent and GlueState.weld.Part0 == hrp and GlueState.weld.Part1 == tgt then return end
    glue_destroy_weld()
    hrp.CFrame = tgt.CFrame + Vector3.new(GlueState.distance, GlueState.height, 0)
    local w = Instance.new("WeldConstraint")
    w.Name = "__ce_glue"
    w.Part0 = hrp
    w.Part1 = tgt
    w.Parent = hrp
    GlueState.weld = w
end
function GlueState.set_enabled(v)
    GlueState.enabled = v
    if v then
        if glue_conn then glue_conn:Disconnect() end
        glue_conn = RunService.Heartbeat:Connect(glue_step)
        track(glue_conn)
    else
        if glue_conn then glue_conn:Disconnect() glue_conn = nil end
        glue_destroy_weld()
    end
end

-- TP WALK
local TPWalkState = { enabled = false, speed = 0.2, noclip = true, camera_lag = 0.15, _conn = nil, _nc_conn = nil }
local function tpwalk_set_noclip(on)
    local char = my_char()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then pcall(function() part.CanCollide = not on end) end
    end
end
local function tpwalk_camera_follow(target_pos, dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local current = cam.CFrame
    local look = current.LookVector
    local desired = CFrame.new(target_pos + Vector3.new(0, 2, 0), target_pos + Vector3.new(0, 2, 0) + look)
    local alpha = math.clamp(1 - math.exp(-(1 / math.max(TPWalkState.camera_lag, 0.01)) * dt), 0.01, 1)
    cam.CFrame = current:Lerp(desired, alpha)
end
function TPWalkState.set_enabled(v)
    TPWalkState.enabled = v
    if v then
        if TPWalkState.noclip then
            tpwalk_set_noclip(true)
            if not TPWalkState._nc_conn then
                TPWalkState._nc_conn = RunService.Stepped:Connect(function()
                    if not TPWalkState.enabled or not TPWalkState.noclip then return end
                    local char = my_char()
                    if char then
                        for _, part in ipairs(char:GetDescendants()) do
                            if part:IsA("BasePart") and part.CanCollide then
                                pcall(function() part.CanCollide = false end)
                            end
                        end
                    end
                end)
                track(TPWalkState._nc_conn)
            end
        end
        if not TPWalkState._conn then
            TPWalkState._conn = RunService.Heartbeat:Connect(function(dt)
                if not TPWalkState.enabled then return end
                local hrp = my_hrp()
                local hum = my_char() and my_char():FindFirstChildOfClass("Humanoid")
                if not hrp or not hum then return end
                local move = hum.MoveDirection
                if move.Magnitude < 0.01 then return end
                local dist = TPWalkState.speed * dt * 60
                local new_pos = hrp.Position + move.Unit * dist
                local new_cf = CFrame.new(new_pos, new_pos + move.Unit)
                if EX.has.getrawmeta then
                    local mt_ok, mt = pcall(getrawmetatable, hrp)
                    if mt_ok and mt then
                        local ni = rawget(mt, "__newindex")
                        if ni then
                            pcall(ni, hrp, "CFrame", new_cf)
                            pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
                        end
                    end
                else
                    pcall(function() hrp.CFrame = new_cf hrp.AssemblyLinearVelocity = Vector3.zero end)
                end
                if TPWalkState.camera_lag > 0 then tpwalk_camera_follow(new_pos, dt) end
            end)
            track(TPWalkState._conn)
        end
    else
        if TPWalkState._conn then TPWalkState._conn:Disconnect() TPWalkState._conn = nil end
        if TPWalkState._nc_conn then TPWalkState._nc_conn:Disconnect() TPWalkState._nc_conn = nil end
        tpwalk_set_noclip(false)
    end
end

-- STRETCH
local StretchedState = { enabled = false, resolution = 0.80 }
local stretch_conn
function StretchedState.set_enabled(v)
    StretchedState.enabled = v
    if v then
        if stretch_conn then stretch_conn:Disconnect() end
        stretch_conn = RunService.RenderStepped:Connect(function()
            if not StretchedState.enabled then return end
            local cam = workspace.CurrentCamera
            if cam then
                cam.CFrame = cam.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, StretchedState.resolution, 0, 0, 0, 1)
            end
        end)
        track(stretch_conn)
    else
        if stretch_conn then stretch_conn:Disconnect() stretch_conn = nil end
    end
end

-- ESP
local ESP = {
    enabled = false, box_color = Color3.fromRGB(216, 126, 157), box_transparency = 0,
    glow = false, glow_color = Color3.fromRGB(216, 126, 157), glow_transparency = 0.65,
    fill_enabled = false, fill_color = Color3.fromRGB(216, 126, 157), fill_transparency = 0.9,
    health_enabled = true,
    health_col_high = Color3.fromRGB(131, 245, 78),
    health_col_mid = Color3.fromRGB(255, 255, 0),
    health_col_low = Color3.fromRGB(252, 71, 77),
    chams_enabled = false, chams_fill = Color3.fromRGB(216, 126, 157), chams_fill_trans = 0.5,
    chams_outline = Color3.fromRGB(0, 0, 0), chams_outline_trans = 0.5,
    names_enabled = true, name_use_display = true, name_color = Color3.fromRGB(255, 255, 255),
    dist_enabled = true, dist_color = Color3.fromRGB(255, 255, 255), dist_ending = "st",
    weapon_enabled = true, weapon_color = Color3.fromRGB(255, 255, 255),
    flags_enabled = true, flags_color = Color3.fromRGB(255, 255, 255),
    font_size = 12, dynamic_box = true,
}

local ESPGui = Instance.new("ScreenGui")
ESPGui.Name = "\0ce_esp"
ESPGui.ResetOnSpawn = false
ESPGui.IgnoreGuiInset = true
ESPGui.DisplayOrder = 10000
ESPGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local ESPObjects = {}
local ESP_FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Medium)

local function esp_make(parent, class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function esp_create_holder(player)
    if ESPObjects[player] then return end
    local root = esp_make(ESPGui, "Frame", { BackgroundTransparency = 1, Visible = false, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(0, 0), BorderSizePixel = 0 })
    local o = { root = root }
    o.box_holder = esp_make(root, "Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(0, 0) })
    o.box_stroke = esp_make(o.box_holder, "UIStroke", { Thickness = 1 })
    o.box_fill = esp_make(o.box_holder, "Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1) })
    o.glow = esp_make(root, "ImageLabel", {
        Image = "rbxassetid://110204605000367", ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(Vector2.new(21, 21), Vector2.new(79, 79)),
        AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1,
        ImageTransparency = 0.65, ResampleMode = Enum.ResamplerMode.Pixelated,
        Visible = false, Position = UDim2.fromOffset(-21, -21),
        Size = UDim2.fromOffset(0, 0), BorderSizePixel = 0,
    })
    esp_make(o.glow, "UIPadding", { PaddingTop = UDim.new(0, 21), PaddingBottom = UDim.new(0, 20), PaddingLeft = UDim.new(0, 21), PaddingRight = UDim.new(0, 20) })
    o.health_outline = esp_make(root, "Frame", { BackgroundColor3 = Color3.new(0,0,0), BorderSizePixel = 0, Visible = false, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(2, 0) })
    o.health_bar = esp_make(o.health_outline, "Frame", { BorderSizePixel = 0, Visible = false, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1) })
    o.text_holders = {}
    for _, pos in ipairs({"Top","Bottom","Left","Right"}) do
        local holder = esp_make(root, "Frame", { BackgroundTransparency = 1, Visible = true, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) })
        esp_make(holder, "UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center })
        o.text_holders[pos] = holder
    end
    o.name = esp_make(o.text_holders.Top, "TextLabel", { FontFace = ESP_FONT, TextSize = ESP.font_size, AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0) })
    esp_make(o.name, "UIStroke", { Color = Color3.new(0,0,0), Thickness = 1 })
    o.dist = esp_make(o.text_holders.Bottom, "TextLabel", { FontFace = ESP_FONT, TextSize = ESP.font_size, AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0) })
    esp_make(o.dist, "UIStroke", { Color = Color3.new(0,0,0), Thickness = 1 })
    o.weapon = esp_make(o.text_holders.Bottom, "TextLabel", { FontFace = ESP_FONT, TextSize = ESP.font_size, Text = "none", AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0) })
    esp_make(o.weapon, "UIStroke", { Color = Color3.new(0,0,0), Thickness = 1 })
    o.flags = esp_make(o.text_holders.Right, "TextLabel", { FontFace = ESP_FONT, TextSize = ESP.font_size, AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0), TextXAlignment = Enum.TextXAlignment.Left })
    esp_make(o.flags, "UIStroke", { Color = Color3.new(0,0,0), Thickness = 1 })
    o.chams = esp_make(player.Character or ESPGui, "Highlight", { Enabled = false, Name = "\0ce_chams" })
    ESPObjects[player] = o
end

local function esp_remove_holder(player)
    local o = ESPObjects[player]
    if not o then return end
    if o.chams then pcall(function() o.chams:Destroy() end) end
    if o.root then pcall(function() o.root:Destroy() end) end
    ESPObjects[player] = nil
end

local function esp_calc_bounds(char, dynamic)
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    if not dynamic then
        local pos, on = cam:WorldToViewportPoint(hrp.Position)
        if not on or pos.Z <= 0 then return nil end
        local scale = (hrp.Size.Y * cam.ViewportSize.Y) / (pos.Z * 2)
        local w, h = 3 * scale, 4.5 * scale
        return w, h, pos.X - w/2, pos.Y - h/2
    end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local any = false
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
            local cf, sz = part.CFrame, part.Size
            local corners = {
                cf * Vector3.new( sz.X/2,  sz.Y/2,  sz.Z/2), cf * Vector3.new(-sz.X/2,  sz.Y/2,  sz.Z/2),
                cf * Vector3.new( sz.X/2, -sz.Y/2,  sz.Z/2), cf * Vector3.new(-sz.X/2, -sz.Y/2,  sz.Z/2),
                cf * Vector3.new( sz.X/2,  sz.Y/2, -sz.Z/2), cf * Vector3.new(-sz.X/2,  sz.Y/2, -sz.Z/2),
                cf * Vector3.new( sz.X/2, -sz.Y/2, -sz.Z/2), cf * Vector3.new(-sz.X/2, -sz.Y/2, -sz.Z/2),
            }
            for _, corner in ipairs(corners) do
                local v, on = cam:WorldToViewportPoint(corner)
                if on and v.Z > 0 then
                    any = true
                    if v.X < minX then minX = v.X end
                    if v.Y < minY then minY = v.Y end
                    if v.X > maxX then maxX = v.X end
                    if v.Y > maxY then maxY = v.Y end
                end
            end
        end
    end
    if not any then return nil end
    return (maxX - minX), (maxY - minY), minX, minY
end

local function esp_update_player(player)
    local o = ESPObjects[player]
    if not o then return end
    if player == LocalPlayer then o.root.Visible = false return end
    if not ESP.enabled then o.root.Visible = false return end
    local char = player.Character
    if not char or not alive(char) then o.root.Visible = false return end
    local myteam = LocalPlayer:GetAttribute("TeamID") or LocalPlayer.Team
    local theirteam = player:GetAttribute("TeamID") or player.Team
    if myteam and theirteam and myteam == theirteam then o.root.Visible = false return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then o.root.Visible = false return end
    local cam = Workspace.CurrentCamera
    if not cam then o.root.Visible = false return end
    local my_hrp_inst = my_hrp()
    local dist = my_hrp_inst and (my_hrp_inst.Position - hrp.Position).Magnitude or 0
    local w, h, x, y = esp_calc_bounds(char, ESP.dynamic_box)
    if not w or not h then o.root.Visible = false return end
    o.root.Visible = true
    o.root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    o.root.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
    o.box_holder.Visible = true
    o.box_holder.Size = UDim2.fromScale(1, 1)
    o.box_holder.Position = UDim2.fromOffset(0, 0)
    o.box_stroke.Color = ESP.box_color
    o.box_stroke.Transparency = ESP.box_transparency
    if ESP.fill_enabled then
        o.box_fill.Visible = true
        o.box_fill.BackgroundColor3 = ESP.fill_color
        o.box_fill.BackgroundTransparency = ESP.fill_transparency
    else o.box_fill.Visible = false end
    if ESP.glow then
        o.glow.Visible = true
        o.glow.ImageColor3 = ESP.glow_color
        o.glow.ImageTransparency = ESP.glow_transparency
        o.glow.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
        o.glow.Position = UDim2.fromOffset(-21, -21)
    else o.glow.Visible = false end
    if ESP.health_enabled then
        local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        o.health_outline.Visible = true
        o.health_outline.Size = UDim2.fromOffset(2, h)
        o.health_outline.Position = UDim2.fromOffset(-5, 0)
        o.health_bar.Visible = true
        o.health_bar.Size = UDim2.fromScale(1, pct)
        o.health_bar.Position = UDim2.fromScale(0, 1 - pct)
        o.health_bar.BackgroundColor3 = pct > 0.5 and ESP.health_col_high or (pct > 0.25 and ESP.health_col_mid or ESP.health_col_low)
    else o.health_outline.Visible = false end
    for pos, holder in pairs(o.text_holders) do
        if pos == "Top" then holder.AnchorPoint = Vector2.new(0.5, 1) holder.Position = UDim2.fromOffset(math.floor(w/2), -2)
        elseif pos == "Bottom" then holder.AnchorPoint = Vector2.new(0.5, 0) holder.Position = UDim2.fromOffset(math.floor(w/2), math.floor(h) + 4)
        elseif pos == "Left" then holder.AnchorPoint = Vector2.new(1, 0.5) holder.Position = UDim2.fromOffset(-8, math.floor(h/2))
        elseif pos == "Right" then holder.AnchorPoint = Vector2.new(0, 0.5) holder.Position = UDim2.fromOffset(math.floor(w) + 8, math.floor(h/2)) end
    end
    if ESP.names_enabled then
        o.name.Visible = true
        o.name.Text = ESP.name_use_display and (player.DisplayName or player.Name) or player.Name
        o.name.TextColor3 = ESP.name_color
        o.name.TextSize = ESP.font_size
        o.name.Parent = o.text_holders.Top
    else o.name.Visible = false end
    if ESP.dist_enabled then
        o.dist.Visible = true
        o.dist.Text = string.format("%d%s", math.floor(dist), ESP.dist_ending)
        o.dist.TextColor3 = ESP.dist_color
        o.dist.TextSize = ESP.font_size
        o.dist.Parent = o.text_holders.Bottom
    else o.dist.Visible = false end
    if ESP.weapon_enabled then
        local tool = char:FindFirstChildOfClass("Tool")
        o.weapon.Visible = true
        o.weapon.Text = tool and tool.Name or "none"
        o.weapon.TextColor3 = ESP.weapon_color
        o.weapon.TextSize = ESP.font_size
        o.weapon.Parent = o.text_holders.Bottom
    else o.weapon.Visible = false end
    if ESP.flags_enabled then
        local flags = {}
        if hum.MoveDirection.Magnitude > 0 then table.insert(flags, "moving") end
        if hum.Jump then table.insert(flags, "jumping") end
        o.flags.Visible = #flags > 0
        o.flags.Text = table.concat(flags, "\n")
        o.flags.TextColor3 = ESP.flags_color
        o.flags.TextSize = ESP.font_size
        o.flags.Parent = o.text_holders.Right
    else o.flags.Visible = false end
    if ESP.chams_enabled then
        if not o.chams or not o.chams.Parent then
            o.chams = esp_make(char, "Highlight", { Name = "\0ce_chams" })
        end
        o.chams.Adornee = char
        o.chams.Enabled = true
        o.chams.FillColor = ESP.chams_fill
        o.chams.FillTransparency = ESP.chams_fill_trans
        o.chams.OutlineColor = ESP.chams_outline
        o.chams.OutlineTransparency = ESP.chams_outline_trans
        o.chams.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    else
        if o.chams then o.chams.Enabled = false end
    end
end

local esp_conn
function ESP.set_enabled(v)
    ESP.enabled = v
    if v then
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then esp_create_holder(p) end end
        if not esp_conn then
            esp_conn = RunService.RenderStepped:Connect(function()
                for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then esp_update_player(p) end end
            end)
            track(esp_conn)
        end
    else
        if esp_conn then esp_conn:Disconnect() esp_conn = nil end
        for p in pairs(ESPObjects) do esp_remove_holder(p) end
    end
end
track(Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then
        p.CharacterAdded:Wait()
        if ESP.enabled then esp_create_holder(p) end
    end
end))
track(Players.PlayerRemoving:Connect(esp_remove_holder))

-- SKIN CHANGER
local SkinState = { equipped={}, favorites={}, hooked=false, originals={}, mods={} }
local SC = {}
local function sc_banned(n)
    if type(n) ~= "string" then return true end
    return n:find("MISSING_") or n:find("Bubblegum") or n:find("Ragdoll") or n:find("Fall Apart")
end
local function sc_clone(name, ctype)
    if sc_banned(name) then return nil end
    local cl = Mods.CosmeticLibrary
    if not cl or not cl.Cosmetics then return nil end
    local base = cl.Cosmetics[name]
    if not base then return nil end
    local d = table.clone(base)
    d.Name = name
    d.Type = d.Type or ctype
    d.Seed = d.Seed or math.random(1, 1000000)
    return d
end
function SC.hook()
    if SkinState.hooked then return end
    local cl = Mods.CosmeticLibrary
    local dc = nil
    pcall(function()
        local ctrls = LocalPlayer.PlayerScripts.Controllers
        local pdc = ctrls:WaitForChild("PlayerDataController", 10)
        if pdc then local ok, m = pcall(require, pdc) if ok then dc = m end end
    end)
    if not cl or not dc then notify(BRAND, "Libraries not ready.") return end
    SkinState.mods = { CosmeticLibrary = cl, DataController = dc }
    SkinState.originals = { OwnsCosmetic = cl.OwnsCosmetic, DCGet = dc.Get, DCGetWeaponData = dc.GetWeaponData }
    cl.OwnsCosmetic = function(self, inv, name, wep)
        if type(name) == "string" and name:find("MISSING_") then
            return SkinState.originals.OwnsCosmetic(self, inv, name, wep)
        end
        return true
    end
    if cl.OwnsCosmeticNormally then cl.OwnsCosmeticNormally = function() return true end end
    if cl.OwnsCosmeticUniversally then cl.OwnsCosmeticUniversally = function() return true end end
    if cl.OwnsCosmeticForWeapon then cl.OwnsCosmeticForWeapon = function() return true end end
    dc.Get = function(self, key)
        if key == "CosmeticInventory" then return setmetatable({}, { __index = function() return true end }) end
        return SkinState.originals.DCGet(self, key)
    end
    dc.GetWeaponData = function(self, wname)
        local data = SkinState.originals.DCGetWeaponData(self, wname)
        if not data then return nil end
        local m = table.clone(data)
        m.Name = wname
        if SkinState.equipped[wname] then
            for ct, cd in pairs(SkinState.equipped[wname]) do m[ct] = cd end
        end
        return m
    end
    SkinState.hooked = true
    notify(BRAND, "Unlock all active.")
end
function SC.unhook()
    if not SkinState.hooked then return end
    local cl = SkinState.mods.CosmeticLibrary
    local dc = SkinState.mods.DataController
    if cl then pcall(function() cl.OwnsCosmetic = SkinState.originals.OwnsCosmetic end) end
    if dc then
        pcall(function() dc.Get = SkinState.originals.DCGet end)
        pcall(function() dc.GetWeaponData = SkinState.originals.DCGetWeaponData end)
    end
    SkinState.hooked = false
    SkinState.equipped = {}
end
function SC.equip(weapon, ctype, cname)
    if not cname or cname == "" or cname == "None" then
        if SkinState.equipped[weapon] then
            SkinState.equipped[weapon][ctype] = nil
            if not next(SkinState.equipped[weapon]) then SkinState.equipped[weapon] = nil end
        end
    else
        local cl = sc_clone(cname, ctype)
        if cl then
            SkinState.equipped[weapon] = SkinState.equipped[weapon] or {}
            SkinState.equipped[weapon][ctype] = cl
        end
    end
end
local sc_weapons = {}
if Mods.ItemLibrary then
    pcall(function()
        local items = Mods.ItemLibrary.Items or Mods.ItemLibrary.Weapons or {}
        for name in pairs(items) do
            if not sc_banned(name) then sc_weapons[#sc_weapons+1] = name end
        end
        table.sort(sc_weapons)
    end)
end
if #sc_weapons == 0 then
    sc_weapons = { "Assault Rifle", "Handgun", "Shotgun", "Sniper", "Bow", "Knife", "Katana", "Riot Shield" }
end
function SC.get_skins()
    local list = {"None"}
    local cl = Mods.CosmeticLibrary
    if cl and cl.Cosmetics then
        for name, data in pairs(cl.Cosmetics) do
            if not sc_banned(name) and data.Type == "Skin" then list[#list+1] = name end
        end
    end
    table.sort(list)
    return list
end
function SC.get_wraps()
    local list = {"None"}
    local cl = Mods.CosmeticLibrary
    if cl and cl.Cosmetics then
        for name, data in pairs(cl.Cosmetics) do
            if not sc_banned(name) and data.Type == "Wrap" then list[#list+1] = name end
        end
    end
    table.sort(list)
    return list
end

-- UNLOAD
local function unload()
    pcall(function() AimState.set_enabled(false) end)
    pcall(function() GlueState.set_enabled(false) end)
    pcall(function() TPWalkState.set_enabled(false) end)
    pcall(function() StretchedState.set_enabled(false) end)
    pcall(function() ESP.set_enabled(false) end)
    pcall(function() RadarState.set_enabled(false) end)
    pcall(function() SC.unhook() end)
    disconnect_all()
    pcall(function() ESPGui:Destroy() end)
    pcall(function() DamageGui:Destroy() end)
    pcall(function()
        if getgenv().rivals and getgenv().rivals.library then
            getgenv().rivals.library:Unload()
        end
    end)
    getgenv().rivals.loaded = false
    notify(BRAND, "Unloaded.")
end

getgenv().rivals = {
    loaded = true,
    brand = BRAND,
    aimbot = AimState, aimbot_override = nil,
    silent = SilentState,
    hitsound = HitSoundState,
    damage = DamageState,
    radar = RadarState,
    glue = GlueState,
    tpwalk = TPWalkState,
    stretched = StretchedState,
    esp = ESP, skin = SC,
    tt = TT, combat = Combat, mods = Mods,
    anti_katana = is_deflecting, anti_riot = has_riot,
    unload = unload,
}

-- UI
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local ok_lib, Library = pcall(function()
    return loadstring(game:HttpGet(repo .. "Library.lua"))()
end)
if not ok_lib or not Library then
    notify(BRAND, "Obsidian failed. Features via getgenv().rivals.")
    return getgenv().rivals
end
getgenv().rivals.library = Library
local Options = Library.Options
local Toggles = Library.Toggles

local Window
do
    local ok, w = pcall(function() return Library:CreateWindow({ Title = BRAND, Center = true, AutoShow = true }) end)
    if not ok or not w then notify(BRAND, "CreateWindow failed.") return getgenv().rivals end
    Window = w
end
local Tabs = {}
for _, tname in ipairs({"Combat","Movement","Visuals","Radar","Skins","Settings"}) do
    local ok, tab = pcall(function() return Window:AddTab(tname) end)
    if ok and tab then Tabs[tname] = tab end
end
if not Tabs.Combat then notify(BRAND, "AddTab failed.") return getgenv().rivals end

-- COMBAT
do
    local gb = Tabs.Combat:AddLeftGroupbox("aimbot")
    pcall(function() gb:AddToggle("AimEnabled", { Text = "enable", Default = false }):OnChanged(function(v) AimState.set_enabled(v) end) end)
    pcall(function() gb:AddDropdown("AimMethod", { Text = "method", Values = {"Keybind", "Toggle", "Always"}, Default = 1 }):OnChanged(function(v) AimState.method = v AimState.is_held=false AimState.is_toggled=false end) end)
    pcall(function() gb:AddDropdown("AimKey", { Text = "key", Values = {"Q","E","R","F","G","C","V","X","Z","T","MB2","MB3"}, Default = 1 }):OnChanged(function(v)
        local map = { Q=Enum.KeyCode.Q, E=Enum.KeyCode.E, R=Enum.KeyCode.R, F=Enum.KeyCode.F, G=Enum.KeyCode.G, C=Enum.KeyCode.C, V=Enum.KeyCode.V, X=Enum.KeyCode.X, Z=Enum.KeyCode.Z, T=Enum.KeyCode.T, MB2=Enum.UserInputType.MouseButton2, MB3=Enum.UserInputType.MouseButton3 }
        AimState.keybind_key = map[v] or Enum.KeyCode.Q
    end) end)
    pcall(function() gb:AddDropdown("AimPriority", { Text = "priority", Values = {"Closest", "LowestHP", "ClosestToScreenCenter"}, Default = 1 }):OnChanged(function(v) AimState.priority = v end) end)
    pcall(function() gb:AddDropdown("AimPart", { Text = "hit part", Values = {"Head","HumanoidRootPart","UpperTorso"}, Default = 1 }):OnChanged(function(v) AimState.target_part = v end) end)
    pcall(function() gb:AddSlider("AimFOV", { Text = "fov", Default = 120, Min = 10, Max = 800, Rounding = 0 }):OnChanged(function(v) AimState.fov = v end) end)
    pcall(function() gb:AddSlider("AimSmooth", { Text = "smoothness (0.02 = snap)", Default = 0.15, Min = 0.02, Max = 15, Rounding = 2 }):OnChanged(function(v) AimState.smoothness = v end) end)
    pcall(function() gb:AddSlider("AimPredictive", { Text = "predictive % (0 = snap)", Default = 5, Min = 0, Max = 100, Rounding = 0 }):OnChanged(function(v) AimState.predictive = v end) end)
    pcall(function() gb:AddToggle("AimWall", { Text = "wall check (enforced)", Default = true }):OnChanged(function(v) AimState.wall_check = v end) end)
    pcall(function() gb:AddToggle("AimTeam", { Text = "team check", Default = true }):OnChanged(function(v) AimState.team_check = v end) end)
    pcall(function() gb:AddToggle("AimFOVCircle", { Text = "show fov circle", Default = true }):OnChanged(function(v) AimState.show_fov_circle = v end) end)
end
do
    local gb = Tabs.Combat:AddLeftGroupbox("silent aim")
    pcall(function() gb:AddToggle("SilEnabled", { Text = "enable (raycast hook)", Default = false }):OnChanged(function(v) SilentState.enabled = v end) end)
    pcall(function() gb:AddDropdown("SilPart", { Text = "hit part", Values = {"Head","HumanoidRootPart","UpperTorso"}, Default = 1 }):OnChanged(function(v) SilentState.hit_part = v end) end)
    pcall(function() gb:AddToggle("SilAuto", { Text = "auto fire", Default = false }):OnChanged(function(v) SilentState.auto_fire = v end) end)
    pcall(function() gb:AddToggle("SilWall", { Text = "wall check", Default = true }):OnChanged(function(v) SilentState.wall_check = v end) end)
    pcall(function() gb:AddToggle("SilThroughWall", { Text = "through wall", Default = false }):OnChanged(function(v) SilentState.through_wall = v end) end)
    pcall(function() gb:AddSlider("SilChance", { Text = "hit chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 }):OnChanged(function(v) SilentState.hit_chance = v end) end)
end

-- MOVEMENT
do
    local gb = Tabs.Movement:AddLeftGroupbox("glue")
    pcall(function() gb:AddToggle("GlueEnabled", { Text = "enable", Default = false }):OnChanged(function(v) GlueState.set_enabled(v) end) end)
    pcall(function() gb:AddSlider("GlueDist", { Text = "distance", Default = 0, Min = -50, Max = 50, Rounding = 1 }):OnChanged(function(v) GlueState.distance = v end) end)
    pcall(function() gb:AddSlider("GlueHeight", { Text = "height", Default = 0, Min = -50, Max = 50, Rounding = 1 }):OnChanged(function(v) GlueState.height = v end) end)
end
do
    local gb = Tabs.Movement:AddRightGroupbox("tp walk")
    pcall(function() gb:AddToggle("TPWalkEnabled", { Text = "enable (noclip auto)", Default = false }):OnChanged(function(v) TPWalkState.set_enabled(v) end) end)
    pcall(function() gb:AddSlider("TPWalkSpeed", { Text = "studs/sec", Default = 0.2, Min = 0.1, Max = 150, Rounding = 1 }):OnChanged(function(v) TPWalkState.speed = v end) end)
    pcall(function() gb:AddSlider("TPWalkCamLag", { Text = "camera smoothness", Default = 0.15, Min = 0, Max = 1, Rounding = 2 }):OnChanged(function(v) TPWalkState.camera_lag = v end) end)
end

-- VISUALS
do
    local gb = Tabs.Visuals:AddLeftGroupbox("esp")
    pcall(function() gb:AddToggle("ESPEnabled", { Text = "enable", Default = false }):OnChanged(function(v) ESP.set_enabled(v) end) end)
    pcall(function() gb:AddColorPicker("ESPBoxColor", { Default = ESP.box_color, Title = "box color" }):OnChanged(function(v) ESP.box_color = v end) end)
    pcall(function() gb:AddToggle("ESPGlow", { Text = "glow", Default = false }):OnChanged(function(v) ESP.glow = v end) end)
    pcall(function() gb:AddColorPicker("ESPGlowColor", { Default = ESP.glow_color, Title = "glow color" }):OnChanged(function(v) ESP.glow_color = v end) end)
    pcall(function() gb:AddToggle("ESPFill", { Text = "fill", Default = false }):OnChanged(function(v) ESP.fill_enabled = v end) end)
    pcall(function() gb:AddToggle("ESPHealth", { Text = "health bar", Default = true }):OnChanged(function(v) ESP.health_enabled = v end) end)
    pcall(function() gb:AddToggle("ESPChams", { Text = "chams", Default = false }):OnChanged(function(v) ESP.chams_enabled = v end) end)
    pcall(function() gb:AddColorPicker("ESPChamsColor", { Default = ESP.chams_fill, Title = "chams fill" }):OnChanged(function(v) ESP.chams_fill = v end) end)
    pcall(function() gb:AddToggle("ESPNames", { Text = "names", Default = true }):OnChanged(function(v) ESP.names_enabled = v end) end)
    pcall(function() gb:AddToggle("ESPDist", { Text = "distance", Default = true }):OnChanged(function(v) ESP.dist_enabled = v end) end)
    pcall(function() gb:AddToggle("ESPWeapon", { Text = "weapon", Default = true }):OnChanged(function(v) ESP.weapon_enabled = v end) end)
    pcall(function() gb:AddToggle("ESPFlags", { Text = "flags", Default = true }):OnChanged(function(v) ESP.flags_enabled = v end) end)
    pcall(function() gb:AddSlider("ESPFontSize", { Text = "font size", Default = 12, Min = 8, Max = 20, Rounding = 0 }):OnChanged(function(v) ESP.font_size = v end) end)
    pcall(function() gb:AddToggle("ESPDynamic", { Text = "dynamic box", Default = true }):OnChanged(function(v) ESP.dynamic_box = v end) end)
end
do
    local gb = Tabs.Visuals:AddRightGroupbox("hit sounds")
    pcall(function() gb:AddToggle("HitsoundEnabled", { Text = "enable", Default = false }):OnChanged(function(v) HitSoundState.enabled = v end) end)
    pcall(function() gb:AddDropdown("HitsoundSelect", { Text = "sound", Values = hitsound_names, Default = 1 }):OnChanged(function(v) HitSoundState.selected = v end) end)
    pcall(function() gb:AddSlider("HitsoundVolume", { Text = "volume", Default = 50, Min = 0, Max = 100, Rounding = 0 }):OnChanged(function(v) HitSoundState.volume = v / 100 end) end)
    pcall(function() gb:AddSlider("HitsoundPitch", { Text = "pitch", Default = 100, Min = 50, Max = 200, Rounding = 0 }):OnChanged(function(v) HitSoundState.pitch = v / 100 end) end)
    pcall(function() gb:AddToggle("HitsoundRemoveDefault", { Text = "mute default hitmarker", Default = false }):OnChanged(function(v) HitSoundState.remove_default = v end) end)
end
do
    local gb = Tabs.Visuals:AddRightGroupbox("damage numbers")
    pcall(function() gb:AddToggle("DamageEnabled", { Text = "enable", Default = false }):OnChanged(function(v) DamageState.enabled = v end) end)
    pcall(function() gb:AddToggle("DamageRemoveIngame", { Text = "remove in-game numbers", Default = false }):OnChanged(function(v) DamageState.remove_ingame = v end) end)
    pcall(function() gb:AddDropdown("DamageColorType", { Text = "color type", Values = {"Gradient", "Solid", "Rainbow"}, Default = 1 }):OnChanged(function(v) DamageState.color_type = v end) end)
    pcall(function() gb:AddColorPicker("DamageColor1", { Default = DamageState.color1, Title = "color 1" }):OnChanged(function(v) DamageState.color1 = v end) end)
    pcall(function() gb:AddColorPicker("DamageColor2", { Default = DamageState.color2, Title = "color 2" }):OnChanged(function(v) DamageState.color2 = v end) end)
    pcall(function() gb:AddSlider("DamageSize", { Text = "text size", Default = 18, Min = 10, Max = 40, Rounding = 0 }):OnChanged(function(v) DamageState.text_size = v end) end)
    pcall(function() gb:AddSlider("DamageDuration", { Text = "duration", Default = 0.8, Min = 0.2, Max = 3, Rounding = 2 }):OnChanged(function(v) DamageState.duration = v end) end)
    pcall(function() gb:AddSlider("DamageRise", { Text = "rise", Default = 42, Min = 0, Max = 120, Rounding = 0 }):OnChanged(function(v) DamageState.rise = v end) end)
end
do
    local gb = Tabs.Visuals:AddLeftGroupbox("stretched resolution")
    pcall(function() gb:AddToggle("StretchEnabled", { Text = "enable", Default = false }):OnChanged(function(v) StretchedState.set_enabled(v) end) end)
    pcall(function() gb:AddSlider("StretchRes", { Text = "y scale", Default = 0.80, Min = 0.3, Max = 1.0, Rounding = 2 }):OnChanged(function(v) StretchedState.resolution = v end) end)
end

-- RADAR
do
    local gb = Tabs.Radar:AddLeftGroupbox("radar")
    pcall(function() gb:AddToggle("RadarEnabled", { Text = "enable", Default = false }):OnChanged(function(v) RadarState.set_enabled(v) end) end)
    pcall(function() gb:AddSlider("RadarGrid", { Text = "grid size", Default = 32, Min = 16, Max = 44, Rounding = 0 }):OnChanged(function(v)
        RadarState.sample_grid = math.floor(v)
        if RadarState.gui then
            RadarState.gui:Destroy()
            RadarState.gui = nil
            RadarState.editable = nil
            RadarState.canvas = nil
            RadarState.pixel_frames = nil
            RadarState.blips = {}
            RadarState.mode = nil
        end
    end) end)
    pcall(function() gb:AddSlider("RadarRange", { Text = "range (studs)", Default = 200, Min = 50, Max = 500, Rounding = 0 }):OnChanged(function(v) RadarState.range = v end) end)
    pcall(function() gb:AddSlider("RadarBlipSize", { Text = "blip size", Default = 3, Min = 1, Max = 8, Rounding = 0 }):OnChanged(function(v) RadarState.blip_size = v end) end)
end

-- SKINS
do
    local gb = Tabs.Skins:AddLeftGroupbox("unlock")
    pcall(function() gb:AddButton({ Text = "unlock all cosmetics", Func = function() SC.hook() end }) end)
    pcall(function() gb:AddButton({ Text = "relock", Func = function() SC.unhook() end }) end)
end
do
    local gb = Tabs.Skins:AddRightGroupbox("equip")
    pcall(function() gb:AddDropdown("SkinWeapon", { Text = "weapon", Values = sc_weapons, Default = 1, Searchable = true }):OnChanged(function(v)
        if Library.Options.SkinPicker then
            Library.Options.SkinPicker:SetValues(SC.get_skins())
            pcall(function() Library.Options.SkinPicker:SetValue("None") end)
        end
    end) end)
    pcall(function() gb:AddDropdown("SkinPicker", { Text = "skin", Values = SC.get_skins(), Default = 1, Searchable = true }):OnChanged(function(v)
        local wpn = Library.Options.SkinWeapon.Value
        SC.equip(wpn, "Skin", v)
    end) end)
    pcall(function() gb:AddDropdown("WrapPicker", { Text = "wrap", Values = SC.get_wraps(), Default = 1, Searchable = true }):OnChanged(function(v)
        local wpn = Library.Options.SkinWeapon.Value
        SC.equip(wpn, "Wrap", v)
    end) end)
end

-- SETTINGS
do
    local gb = Tabs.Settings:AddLeftGroupbox("menu")
    pcall(function() gb:AddButton({ Text = "unload", Func = unload }) end)
    pcall(function() gb:AddButton({ Text = "rebuild modules", Func = function() refresh_modules() notify(BRAND,"Modules refreshed.") end }) end)
end

notify(BRAND, "v1.5 loaded. Wall check enforced. Radar + damage + hitsounds active.", 5)
print("[" .. BRAND .. "] port 1 (raycast):", SilentState.raycast_hook_installed)
print("[" .. BRAND .. "] port 3 (hitsound):", HitSoundState.raycast_hook_installed)
print("[" .. BRAND .. "] port 5 (damage):", DamageState.raycast_hook_installed)
print("[" .. BRAND .. "] radar mode:", RadarState.mode or "not built yet")
print("[" .. BRAND .. "] wall check:", AimState.wall_check)
return getgenv().rivals