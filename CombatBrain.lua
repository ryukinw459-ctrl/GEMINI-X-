local CombatBrain = {}
CombatBrain.__index = CombatBrain

-- Configurações de Atitude (Necessário para a função ler os valores)
local ATTITUDES = {
    LEGIT = {BaseSpeed = 0.11, AttentionImpact = 0.15, MaxFatigue = 2.0, JitterScale = 1.2},
    TRYHARD = {BaseSpeed = 0.085, AttentionImpact = 0.08, MaxFatigue = 1.0, JitterScale = 0.8},
    RAGE = {BaseSpeed = 0.07, AttentionImpact = 0.04, MaxFatigue = 0.4, JitterScale = 0.6}
}

-- Coloque aqui a sua função que você postou:
function CombatBrain:SelectAttitude(dt)
    local now = time()
    local isCritical = self:IsFightingBoss()
    
    -- [1] METABOLISMO ESTABILIZADO
    self._fatigueSeed = (self._fatigueSeed or math.random()) * 0.98 + (math.random() * 0.02)
    local decayRate = dt * (0.015 + self._fatigueSeed * 0.02)
    self._rageCount = math.max((self._rageCount or 0) - decayRate, 0)

    -- [2] GESTÃO DE RUÍDO
    self._noiseLock = self._noiseLock or 0
    if self._noiseLock > 0 and (now - self._noiseLock > 5) then self._noiseLock = 0 end 

    if now < self._noiseLock then
        if not (isCritical and math.random() < 0.7) then
            return ATTITUDES.LEGIT
        end
    end

    local noiseChance = 0.005 + (1 - (self.Session.Attention or 1)) * 0.02
    if math.random() < noiseChance then
        self._noiseLock = now + math.random(0.5, 2.0)
        return ATTITUDES.LEGIT
    end

    -- [3] VETO SOCIAL
    if self:IsPlayerNearby() then
        self:ResetTemporaryStates()
        return ATTITUDES.LEGIT
    end

    -- [4] LÓGICA DE FOCO
    if isCritical then
        if not self._rageStart and not self._isBurningOut and now > (self._postBurnoutLock or 0) then
            local fatigueFactor = math.clamp(self._rageCount / 8, 0, 1)
            local focusChance = 0.75 - (fatigueFactor * 0.45)
            
            if math.random() < focusChance then
                self._rageStart = now
                self._warmupTime = math.random(1.5, 3.5)
                self._rageLimit = math.random(12, 28)
                self._rageCount = self._rageCount + 1
            else
                return ATTITUDES.TRYHARD 
            end
        end

        if self._rageStart then
            local rageElapsed = now - self._rageStart
            if rageElapsed <= self._rageLimit then
                local warmupProgress = math.clamp(rageElapsed / (self._warmupTime or 2), 0, 1)
                if warmupProgress < 0.8 then return ATTITUDES.TRYHARD end

                local instability = math.clamp(rageElapsed / self._rageLimit, 0, 1)
                local fatigueBoost = math.clamp(self._rageCount / 8, 0, 0.25)
                
                if math.random() < (0.1 + (instability * 0.25) + fatigueBoost) then
                    return ATTITUDES.TRYHARD 
                end
                return ATTITUDES.RAGE
            else
                self:EnterBurnout(now)
            end
        end
    end

    -- [5] RECUPERAÇÃO BIFÁSICA
    if self._isBurningOut then
        if now < (self._burnoutEnd or 0) then
            return (math.random() < 0.5) and ATTITUDES.TRYHARD or ATTITUDES.LEGIT
        elseif now < (self._burnoutFade or 0) then
            return (math.random() < 0.8) and ATTITUDES.TRYHARD or ATTITUDES.LEGIT
        else
            if math.random() < 0.2 then
                self._burnoutEnd = now + math.random(3, 6)
                return ATTITUDES.LEGIT
            end
            self._isBurningOut = false
        end
    end

    return ATTITUDES.TRYHARD
end

-- HELPERS
function CombatBrain:ResetTemporaryStates()
    self._rageStart = nil
    self._warmupTime = nil
    self._isBurningOut = false
    self._noiseLock = 0
    self._burnoutEnd = nil
    self._burnoutFade = nil
end

function CombatBrain:EnterBurnout(now)
    self._rageStart = nil
    self._warmupTime = nil
    self._isBurningOut = true
    self._burnoutEnd = now + math.random(6, 12)
    self._burnoutFade = self._burnoutEnd + math.random(6, 10)
    self._postBurnoutLock = self._burnoutFade + math.random(5, 12)
end

return CombatBrain
