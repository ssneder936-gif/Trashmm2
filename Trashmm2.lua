-- language: Lua, file: mm2_full.lua, target: Roblox executor (Krnl/Delta/Synapse)
-- MERD = Murderer, Sheriff, Innocent. Raycast hook bends client-side casts only.
-- Server-side damage ray is not reachable from the client — flagged inline.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local cfg = {
    esp = {merd=false, sheriff=false, innocent=false},
    god = false,
    aimbot = false,
    silent = false,
    wallbang = false,
    raycastHook = true,   -- bends client-side raycasts toward target
    fov = 120,
    teamCheck = false,    -- MM2 has no teams, left here for reuse
    bendOnlyOnMiss = true, -- false = rage mode, will get flagged
}

-- ============ DRAW ============
local Draw = Drawing.new
local espCache = {}

local function roleOf(plr)
    local char = plr.Character
    if not char then return nil end
    for _, v in ipairs(plr:GetChildren()) do
        if v:IsA("StringValue") and v.Name == "Role" then return v.Value end
    end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("StringValue") and v.Name == "Role" then return v.Value end
    end
    return nil
end

local function mkESP(plr)
    local t = {
        box = Draw.new("Square"),
        name = Draw.new("Text"),
        role = Draw.new("Text"),
    }
    t.box.Thickness = 1
    t.box.Filled = false
    t.box.Color = Color3.fromRGB(255,255,255)
    t.box.Transparency = 1
    t.name.Size = 14
    t.name.Center = true
    t.name.Outline = true
    t.name.Transparency = 1
    t.role.Size = 14
    t.role.Center = true
    t.role.Outline = true
    t.role.Transparency = 1
    espCache[plr] = t
    return t
end

local function worldToScreen(pos)
    local cam = Workspace.CurrentCamera
    local sp, onScreen = cam:WorldToViewportPoint(pos)
    if sp.Z <= 0 then return nil, false end
    return Vector2.new(sp.X, sp.Y), onScreen
end

RunService.RenderStepped:Connect(function()
    for plr, t in pairs(espCache) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hrp and hum and hum.Health > 0) or plr == LP then
            t.box.Transparency = 0; t.name.Transparency = 0; t.role.Transparency = 0
            continue
        end
        local role = roleOf(plr)
        local show = (role == "Murderer" and cfg.esp.merd)
                  or (role == "Sheriff" and cfg.esp.sheriff)
                  or (role == "Innocent" and cfg.esp.innocent)
        if not show then
            t.box.Transparency = 0; t.name.Transparency = 0; t.role.Transparency = 0
            continue
        end
        local headPos = hrp.Position + Vector3.new(0, 1.5, 0)
        local footPos = hrp.Position - Vector3.new(0, 3, 0)
        local top, topOn = worldToScreen(headPos)
        local bot, botOn = worldToScreen(footPos)
        if top and bot and topOn and botOn then
            local h = bot.Y - top.Y
            local w = h * 0.5
            t.box.Size = Vector2.new(w, h)
            t.box.Position = Vector2.new(top.X - w/2, top.Y)
            t.box.Color = role == "Murderer" and Color3.fromRGB(255,60,60)
                        or role == "Sheriff" and Color3.fromRGB(80,140,255)
                        or Color3.fromRGB(80,255,120)
            t.box.Transparency = 1

            t.name.Text = plr.Name
            t.name.Position = Vector2.new(top.X, top.Y - 32)
            t.name.Color = t.box.Color
            t.name.Transparency = 1

            t.role.Text = role or "?"
            t.role.Position = Vector2.new(top.X, top.Y - 16)
            t.role.Color = t.box.Color
            t.role.Transparency = 1
        else
            t.box.Transparency = 0; t.name.Transparency = 0; t.role.Transparency = 0
        end
    end
end)

for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then mkESP(p) end end
Players.PlayerAdded:Connect(function(p) if p ~= LP then mkESP(p) end end)
Players.PlayerRemoving:Connect(function(p)
    local t = espCache[p]
    if t then for _, d in pairs(t) do d:Remove() end espCache[p] = nil end
end)

-- ============ TARGET SELECTION ============
local function getTarget()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local best, bestD = nil, cfg.fov
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if head and hum and hum.Health > 0 then
            local sp, on = cam:WorldToViewportPoint(head.Position)
            if on then
                local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                if d < bestD then bestD, best = d, head end
            end
        end
    end
    return best
end

-- ============ RAYCAST HOOK ============
-- Bends client-side Raycast calls toward the target. MM2's knife and gun
-- fire direction are built client-side in most builds; the SERVER re-casts
-- for actual damage, so this redirects the visible tracer and any
-- client-side hit prediction, not the server's damage ray.
if cfg.raycastHook and hookmetamethod and newcclosure and getnamecallmethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if cfg.raycastHook and method == "Raycast"
            and (self == Workspace or (typeof(self) == "Instance" and self:IsA("WorldRoot"))) then
            local args = {...}
            local origin, direction = args[1], args[2]
            if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                local t = getTarget()
                if t then
                    local aimed = (t.Position - origin).Unit * direction.Magnitude
                    if cfg.bendOnlyOnMiss then
                        -- only bend if the original ray wouldn't already hit the target
                        local params = args[3]
                        local check = Workspace:Raycast(origin, aimed, params)
                        if check and check.Instance
                            and t.Parent
                            and check.Instance:IsDescendantOf(t.Parent) then
                            args[2] = aimed
                        end
                    else
                        args[2] = aimed
                    end
                end
            end
            return oldNamecall(self, table.unpack(args))
        end
        -- legacy fallback: FindPartOnRay / FindPartOnRayWithIgnoreList
        if cfg.raycastHook and (method == "FindPartOnRay"
            or method == "FindPartOnRayWithIgnoreList"
            or method == "FindPartOnRayWithWhitelist") then
            local args = {...}
            local ray = args[1]
            if typeof(ray) == "Ray" then
                local t = getTarget()
                if t then
                    local aimed = (t.Position - ray.Origin).Unit * ray.Direction.Magnitude
                    args[1] = Ray.new(ray.Origin, aimed)
                end
            end
            return oldNamecall(self, table.unpack(args))
        end
        return oldNamecall(self, ...)
    end))
end

-- ============ AIMBOT / SILENT ============
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 and cfg.aimbot then
        local cam = Workspace.CurrentCamera
        local t = getTarget()
        if t and cam then
            cam.CFrame = CFrame.new(cam.CFrame.Position, t.Position)
        end
    end
    if input.KeyCode == Enum.KeyCode.E and cfg.wallbang then
        local char = LP.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        local t = getTarget()
        if tool and t then
            for _, v in ipairs(tool:GetDescendants()) do
                if v:IsA("RemoteEvent")
                    and (v.Name:lower():find("fire") or v.Name:lower():find("attack")) then
                    pcall(function() v:FireServer(t) end)
                end
            end
        end
    end
end)

-- silent aim: hook camera CFrame reads so the engine's shot vector goes to
-- the target while the crosshair stays put. Complements the raycast hook —
-- either one alone may miss depending on where the game builds the ray.
if cfg.silent and hookmetamethod and newcclosure then
    local cam = Workspace.CurrentCamera
    local oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, k)
        if cfg.silent and self == Workspace.CurrentCamera and k == "CFrame" then
            local t = getTarget()
            if t then
                return CFrame.new(self.CFrame.Position, t.Position)
            end
        end
        return oldIndex(self, k)
    end))
end

-- ============ GOD MODE (local only, server overrides) ============
RunService.Heartbeat:Connect(function()
    if cfg.god then
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health < hum.MaxHealth then
            hum.Health = hum.MaxHealth
        end
    end
end)

-- ============ KILL ALL ============
-- Only meaningful if LP is Murderer. Remote name varies per MM2 build.
local function killAll()
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local h = plr.Character and plr.Character:FindFirstChild("Head")
        if h then
            tool:Activate()
            pcall(function() tool:FindFirstChild("Kill"):FireServer(plr.Character) end)
        end
    end
end

-- ============ MENU ============
local gui = Instance.new("ScreenGui")
gui.Name = "qx_menu"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 250, 0, 360)
frame.Position = UDim2.new(0.02, 0, 0.2, 0)
frame.BackgroundColor3 = Color3.fromRGB(18,18,22)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,28)
title.BackgroundColor3 = Color3.fromRGB(28,28,34)
title.BorderSizePixel = 0
title.Text = "qx · mm2"
title.TextColor3 = Color3.fromRGB(230,230,235)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = frame

local list = Instance.new("Frame")
list.Size = UDim2.new(1,-16,1,-44)
list.Position = UDim2.new(0,8,0,36)
list.BackgroundTransparency = 1
list.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0,4)
layout.Parent = list

local function mkToggle(label, get, set)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,26)
    btn.BackgroundColor3 = get() and Color3.fromRGB(50,90,60) or Color3.fromRGB(30,30,36)
    btn.BorderSizePixel = 0
    btn.Text = "  " .. label .. ": " .. (get() and "on" or "off")
    btn.TextColor3 = Color3.fromRGB(200,200,210)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = list
    btn.MouseButton1Click:Connect(function()
        set(not get())
        btn.Text = "  " .. label .. ": " .. (get() and "on" or "off")
        btn.BackgroundColor3 = get() and Color3.fromRGB(50,90,60) or Color3.fromRGB(30,30,36)
    end)
    return btn
end

mkToggle("Murderer ESP", function() return cfg.esp.merd end,
    function(v) cfg.esp.merd = v end)
mkToggle("Sheriff ESP", function() return cfg.esp.sheriff end,
    function(v) cfg.esp.sheriff = v end)
mkToggle("Innocent ESP", function() return cfg.esp.innocent end,
    function(v) cfg.esp.innocent = v end)
mkToggle("Aimbot (RMB)", function() return cfg.aimbot end,
    function(v) cfg.aimbot = v end)
mkToggle("Silent Aim", function() return cfg.silent end,
    function(v) cfg.silent = v end)
mkToggle("Raycast Bend", function() return cfg.raycastHook end,
    function(v) cfg.raycastHook = v end)
mkToggle("Bend Only On Miss", function() return cfg.bendOnlyOnMiss end,
    function(v) cfg.bendOnlyOnMiss = v end)
mkToggle("Wallbang (E)", function() return cfg.wallbang end,
    function(v) cfg.wallbang = v end)
mkToggle("God Mode", function() return cfg.god end,
    function(v) cfg.god = v end)

local killBtn = Instance.new("TextButton")
killBtn.Size = UDim2.new(1,0,0,26)
killBtn.BackgroundColor3 = Color3.fromRGB(90,30,30)
killBtn.BorderSizePixel = 0
killBtn.Text = "  Kill All"
killBtn.TextColor3 = Color3.fromRGB(240,220,220)
killBtn.Font = Enum.Font.Gotham
killBtn.TextSize = 12
killBtn.TextXAlignment = Enum.TextXAlignment.Left
killBtn.Parent = list
killBtn.MouseButton1Click:Connect(killAll)
