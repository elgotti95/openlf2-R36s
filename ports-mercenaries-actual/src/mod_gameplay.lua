-- Optional mod API. All game API calls below use the retail script interface.
local config = RecompModConfig
local handled = nil
local followers = {}

function Recomp_ContractCanFailPermanently()
    if type(sMissionAssetID) ~= 'string' or not config.contracts[sMissionAssetID] then return false end
    if type(util_IsAceMission) ~= 'function' or type(util_IsPlayableIntro) ~= 'function' then return false end
    if util_IsAceMission(sQuadrant, sFaction, iMission) or util_IsPlayableIntro(sQuadrant, sFaction, iMission) then return false end
    return (sFaction == 'allies' or sFaction == 'china' or sFaction == 'mafia' or sFaction == 'sk')
        and type(iMission) == 'number' and iMission >= 1 and type(sMemoryKey_ArcBookmark) == 'string'
end

function Recomp_FailContractPermanently()
    if config.permadeath and bDeathSequencePending then return true end
    if not Recomp_ContractCanFailPermanently() then return false end
    if handled == sMissionAssetID then return true end
    handled = sMissionAssetID
    local key = 'recomp_failed_' .. sMissionAssetID
    -- Mark failure separately: no reward, intel, success flag, or completion tally.
    if pre_MissionFailure then pre_MissionFailure() end
    Utility_WriteNumberToScribbleMemory(key, 1)
    Utility_WriteNumberToScribbleMemory(sMemoryKey_ArcBookmark, iMission + 1)
    Retry(false)
    if post_MissionFailure then post_MissionFailure() end
    -- Authors can supply unlocks/cleanup for a changed story or custom arc.
    if Recomp_OnPermanentContractFailure then Recomp_OnPermanentContractFailure(sMissionAssetID) end
    Utility_SavePlayerData()
    mission_MissionCleanup()
    return true
end

function Recomp_InstallMissionHooks()
    if type(mission_MissionFailure2) ~= 'function' or type(mission_HeroKilled2) ~= 'function' then return end
    if RecompMissionHooksInstalled then return end
    RecompMissionHooksInstalled = true
    local fail, death = mission_MissionFailure2, mission_HeroKilled2
    mission_MissionFailure2 = function()
        if not Recomp_FailContractPermanently() then return fail() end
    end
    mission_HeroKilled2 = function()
        if not Recomp_FailContractPermanently() then return death() end
    end
end

function Recomp_EnableFollower(actor)
    if not config.followers or not Actor_IsAlive(actor) then return false end
    local handle = actor
    if type(handle) ~= 'userdata' then handle = Utility_GetActor(actor) end
    if not handle or tostring(handle) == tostring(Utility_GetActor('player0')) then return false end
    if Ai_GetFaction(actor) ~= Ai_GetFaction('player0') then return false end
    Utility_LoadUtilityScript('util_misc')
    Utility_LoadUtilityScript('follow')
    if type(follow_Set) ~= 'function' then return false end
    local id = tostring(actor)
    if not followers[id] then
        -- Leave mission-owned follower registrations alone.
        if not follow_ActorData(actor) then
            follow_Set(actor, false)
            followers[id] = actor
        end
    end
    return true
end

function Recomp_UpdateFollowers()
    if not config.followers or not Actor_IsAlive('player0') then return end
    local x,y,z = Actor_GetPosition('player0')
    local actors = Utility_GetActorsInRange('TYPE_VEHICLE_HUMAN_GENERAL',x,y,z,40)
    if actors then for _,actor in ipairs(actors) do Recomp_EnableFollower(actor) end end
    for id,actor in pairs(followers) do
        if not Actor_IsAlive(actor) then followers[id] = nil
        elseif Ai_GetFaction(actor) ~= Ai_GetFaction('player0') then
            follow_Disable(actor)
            followers[id] = nil
        end
    end
end
