-- BloxStrike: No Spread + No Recoil loaders and game-controller hold-Space bhop.
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

-- Re-execution replaces our jump listener; weapon hooks stay single-load.
if state.jumpConnection then state.jumpConnection:Disconnect() end
if state.characterConnection then state.characterConnection:Disconnect() end
state.generation = (state.generation or 0) + 1
local generation = state.generation
state.autoJumpEnabled = true

local function startBhop()
-- BloxStrike: повторный прыжок при удержании физического Space.
-- Остановить: getgenv().BloxStrikeBhop.Stop()
-- Состояние: getgenv().BloxStrikeBhop.Status()

local G = getgenv()
if G.BloxStrikeBhop and type(G.BloxStrikeBhop.Stop) == "function" then
    G.BloxStrikeBhop.Stop()
end

if game.GameId ~= 7633926880 then
    warn("[BloxStrikeBhop] Этот скрипт предназначен для BloxStrike")
    return
end

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local ok, action = pcall(function()
    return require(RS.Controllers.InputController.Actions.Jump)
end)
if not ok or type(action) ~= "table" or type(action.Callback) ~= "function" then
    warn("[BloxStrikeBhop] Не найден обработчик прыжка игры")
    return
end

local controller
for i = 1, 12 do
    local value = debug.getupvalue(action.Callback, i)
    if type(value) == "table" and
       type(value.jump) == "function" and
       type(value.getCurrentCharacter) == "function" then
        controller = value
        break
    end
end
if not controller then
    warn("[BloxStrikeBhop] Не найден контроллер персонажа")
    return
end

local state = {
    running = true,
    attempts = 0,
    jumpsObserved = 0,
    spaceDown = false,
    onGround = false,
    lastError = nil,
}
local connection
local character
local lastPulse = -math.huge
local pulseHeld = false
local awaitingAir = false
local pendingPressAt = nil
local wasDown = false
local initialPhase = false
local initialAt = 0
local nativeReleaseAt = nil

local function setJump(down)
    local success, err = pcall(controller.jump, down)
    if not success then
        state.lastError = tostring(err)
        warn("[BloxStrikeBhop] " .. state.lastError)
        state.Stop()
        return false
    end
    return true
end

function state.Stop()
    if not state.running then return end
    state.running = false
    if connection then connection:Disconnect() end
    if pulseHeld then
        pcall(controller.jump, false)
        pulseHeld = false
    end
    print("[BloxStrikeBhop] stopped", state.attempts, state.jumpsObserved)
end

function state.Status()
    return {
        running = state.running,
        attempts = state.attempts,
        jumpsObserved = state.jumpsObserved,
        spaceDown = state.spaceDown,
        onGround = state.onGround,
        lastError = state.lastError,
    }
end

G.BloxStrikeBhop = state

connection = RunService.Heartbeat:Connect(function()
    local current = controller.getCurrentCharacter()
    local down = UIS:IsKeyDown(Enum.KeyCode.Space)
    local grounded = current ~= nil and current.OnGround == true
    state.spaceDown = down
    state.onGround = grounded

    if current ~= character then
        character = current
        awaitingAir = false
        pulseHeld = false
        pendingPressAt = nil
        wasDown = false
        initialPhase = false
        nativeReleaseAt = nil
        lastPulse = -math.huge
    end

    if not down or not current then
        pendingPressAt = nil
        nativeReleaseAt = nil
        initialPhase = false
        wasDown = false
        if pulseHeld then
            setJump(false)
            pulseHeld = false
        end
        awaitingAir = false
        return
    end

    local now = os.clock()
    if not wasDown then
        -- Первый физический Space обрабатывает сама игра. Не гасим его.
        wasDown = true
        initialPhase = true
        initialAt = now
        lastPulse = now
        return
    end

    if initialPhase then
        if not grounded or current.IsJumping then
            initialPhase = false
            -- После отрыва отпускаем внутренний флаг, чтобы подготовить следующий прыжок.
            nativeReleaseAt = now + 0.18
        elseif now - initialAt < 0.18 then
            return
        else
            -- Запасной путь, если обычный первый прыжок не зарегистрирован.
            initialPhase = false
        end
    end

    if nativeReleaseAt and now >= nativeReleaseAt then
        if not setJump(false) then return end
        nativeReleaseAt = nil
    end

    if awaitingAir and not grounded then
        state.jumpsObserved = state.jumpsObserved + 1
        awaitingAir = false
    end

    -- Отпускаем только внутренний флаг прыжка игры, не физическую клавишу.
    if pulseHeld and now - lastPulse >= 0.13 then
        if not setJump(false) then return end
        pulseHeld = false
    end

    -- SetJumpInput должен увидеть отпускание отдельным кадром до нового импульса.
    if pendingPressAt and now >= pendingPressAt then
        pendingPressAt = nil
        if not grounded then return end
        if not setJump(true) then return end
        lastPulse = now
        pulseHeld = true
        awaitingAir = true
        state.attempts = state.attempts + 1
    end

    -- Повтор после приземления; ограничение частоты не даёт зациклиться на земле.
    if grounded and not initialPhase and not pulseHeld and not pendingPressAt
        and now - lastPulse >= 0.25 then
        if current.JumpInputDown then
            if not setJump(false) then return end
            pendingPressAt = now + 0.03
        else
            if not setJump(true) then return end
            lastPulse = now
            pulseHeld = true
            awaitingAir = true
            state.attempts = state.attempts + 1
        end
    end
end)

print("[BloxStrikeBhop] controller-v3 running; hold Space; Stop()/Status() via getgenv().BloxStrikeBhop")

end
startBhop()
function state.StopAutoJump()
    state.autoJumpEnabled = false
    local bhopState = environment.BloxStrikeBhop
    if bhopState and type(bhopState.Stop) == 'function' then bhopState.Stop() end
end

function state.Status()
    local bhopState = environment.BloxStrikeBhop
    local jumpStatus = bhopState and bhopState.Status and bhopState.Status() or {}
    return {
        noSpread = state.noSpreadLoaded,
        noRecoil = state.noRecoilLoaded,
        autoJump = state.autoJumpEnabled and jumpStatus.running == true,
        jumpMode = 'game controller',
        jumpAttempts = jumpStatus.attempts or 0,
        jumpsObserved = jumpStatus.jumpsObserved or 0,
        spaceDown = jumpStatus.spaceDown or false,
        onGround = jumpStatus.onGround or false,
        jumpError = jumpStatus.lastError,
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

print("[BloxStrike Combo] Hold Space for bhop; first jump uses the normal game input.")
