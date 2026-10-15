-- BloxStrike: two original remote loaders plus hold-Space auto jump.
-- Run in a client executor after joining BloxStrike.

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- GameId is the universe ID, so this also covers BloxStrike match places.
if game.GameId ~= 7633926880 then
    warn("[BloxStrike Combo] This script is for BloxStrike only.")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then
    warn("[BloxStrike Combo] LocalPlayer is unavailable.")
    return
end

local environment = type(getgenv) == "function" and getgenv() or _G
local state = environment.BloxStrikeComboState
if type(state) ~= "table" then
    state = { noSpreadLoaded = false, noRecoilLoaded = false, generation = 0 }
    environment.BloxStrikeComboState = state
end
if state.jobId ~= game.JobId then
    state.noSpreadLoaded = false
    state.noRecoilLoaded = false
    state.jobId = game.JobId
end

-- Re-execution replaces only our listeners. The two remote scripts change
-- functions in place, so loading them a second time would stack wrappers.
if state.jumpConnection then state.jumpConnection:Disconnect() end
if state.characterConnection then state.characterConnection:Disconnect() end
state.generation = (state.generation or 0) + 1
local generation = state.generation
state.autoJumpEnabled = true
state.humanoid = nil

local function bindCharacter(character)
    state.humanoid = nil
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 10)
        if state.generation == generation and player.Character == character then
            state.humanoid = humanoid
        end
    end)
end

state.characterConnection = player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

state.jumpConnection = RunService.Heartbeat:Connect(function()
    if not state.autoJumpEnabled
        or not UserInputService:IsKeyDown(Enum.KeyCode.Space)
        or UserInputService:GetFocusedTextBox() then
        return
    end

    local humanoid = state.humanoid
    if not humanoid or humanoid.Health <= 0 then return end
    local currentState = humanoid:GetState()
    if currentState == Enum.HumanoidStateType.Seated
        or currentState == Enum.HumanoidStateType.Dead
        or currentState == Enum.HumanoidStateType.Swimming then
        return
    end
    if humanoid.FloorMaterial ~= Enum.Material.Air then
        humanoid.Jump = true
    end
end)

function state.StopAutoJump()
    state.autoJumpEnabled = false
    if state.jumpConnection then state.jumpConnection:Disconnect() end
    if state.characterConnection then state.characterConnection:Disconnect() end
    state.jumpConnection = nil
    state.characterConnection = nil
    state.humanoid = nil
    print("[BloxStrike Combo] Auto jump stopped; weapon hooks remain loaded.")
end

function state.Status()
    return {
        noSpread = state.noSpreadLoaded,
        noRecoil = state.noRecoilLoaded,
        autoJump = state.autoJumpEnabled,
    }
end

local loaders = {
    {
        flag = "noSpreadLoaded",
        name = "No Spread",
        attempts = 0,
        url = "https://scriptblox.com/raw/NEW-MAP-BloxStrike-No-Spread-Open-Source-232179",
        matches = function(module)
            return type(module._performRaycast) == "function"
                and type(module.getTrueSpread) == "function"
        end,
    },
    {
        flag = "noRecoilLoaded",
        name = "No Recoil",
        attempts = 0,
        url = "https://scriptblox.com/raw/UPDATE-BloxStrike-No-Recoil-(Open-Source)-231784",
        matches = function(module)
            return type(module.setWeaponRecoil) == "function"
                and type(module.weaponKick) == "function"
        end,
    },
}

local function runLoadstring(loader)
    loader.attempts = loader.attempts + 1
    local ok, err = pcall(function()
        loadstring(game:HttpGet(loader.url))()
    end)
    if ok then
        state[loader.flag] = true
        print("[BloxStrike Combo] " .. loader.name .. " loaded.")
    else
        warn("[BloxStrike Combo] " .. loader.name .. " failed: " .. tostring(err))
    end
end

task.spawn(function()
    if type(getloadedmodules) ~= "function" or type(loadstring) ~= "function" then
        warn("[BloxStrike Combo] Executor needs getloadedmodules and loadstring.")
        return
    end

    -- The weapon modules can load after the character. Wait at most 30 seconds.
    for _ = 1, 30 do
        if state.generation ~= generation then return end
        if state.noSpreadLoaded and state.noRecoilLoaded then return end

        local ok, modules = pcall(getloadedmodules)
        if ok and type(modules) == "table" then
            local found = { noSpreadLoaded = false, noRecoilLoaded = false }
            for _, moduleScript in ipairs(modules) do
                local required, module = pcall(require, moduleScript)
                if required and type(module) == "table" then
                    for _, loader in ipairs(loaders) do
                        if not state[loader.flag] and not found[loader.flag]
                            and loader.matches(module) then
                            found[loader.flag] = true
                        end
                    end
                end
                if (found.noSpreadLoaded or state.noSpreadLoaded)
                    and (found.noRecoilLoaded or state.noRecoilLoaded) then
                    break
                end
            end
            for _, loader in ipairs(loaders) do
                if found[loader.flag] and not state[loader.flag]
                    and loader.attempts < 3 then
                    runLoadstring(loader)
                end
            end
        end
        task.wait(1)
    end
    if not state.noSpreadLoaded or not state.noRecoilLoaded then
        warn("[BloxStrike Combo] Weapon module not ready; run again after entering a match.")
    end
end)

print("[BloxStrike Combo] Hold Space to jump after each landing.")
