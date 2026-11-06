local _, addon = ...
-- 3.3.5 Feral tree indices, cross-checked against Talented's DRUID tree
-- (Data.lua) and its GetTalentInfo(tab,index) template representation.
-- Shared talents such as Thick Hide/Primal Fury do not establish Cat identity.
function addon.ClassifyFeralRanks(rank)
    if rank(16) > 0 or rank(22) > 0 then return "BEAR" end -- Natural Reaction / Protector of the Pack
    if rank(9) > 0 or rank(18) > 0 or rank(21) > 0 then return "CAT" end -- Shredding Attacks / Primal Tenacity / Nurturing Instinct
end

function addon.ApplyFeralIdentity(data, assignedTank)
    if data.class ~= "DRUID" or data.spec ~= "FERAL" then return end
    data.isTank = assignedTank == true
    data.isHealer = false
    if data.feralKind == "BEAR" then
        data.specTexture = "Interface\\Icons\\Ability_Racial_BearForm"
    elseif data.feralKind == "CAT" then
        data.specTexture = "Interface\\Icons\\Ability_Druid_CatForm"
    end
end

function addon.IsAssignedGroupTank(unit)
    if not unit or not (UnitInParty(unit) or UnitInRaid(unit)) then return false end
    if UnitGroupRolesAssigned then
        local tank = UnitGroupRolesAssigned(unit)
        if tank == true or tank == "TANK" then return true end
    end
    -- 3.3.5a returns 1/nil here, so the old "== true" never matched.
    return GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) and true or false
end
