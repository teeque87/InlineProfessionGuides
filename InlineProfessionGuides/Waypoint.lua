local addonName, ns = ...
local L = ns.L

-- Map waypoints for trainers and vendors: TomTom if installed, else Blizzard's map pin (super-tracked),
-- and the world map opens on the NPC's zone.

local Waypoint = {}
ns.Waypoint = Waypoint

local mapByAreaName

-- uiMapID for a zone/area ID (Wowhead locations use area IDs), matched by name once and cached
local function mapForArea(area)
    local name = area and C_Map.GetAreaInfo(area)
    if not name then return end
    if not mapByAreaName then
        mapByAreaName = {}
        for id = 1, 3000 do
            local info = C_Map.GetMapInfo(id)
            if info and info.name and info.mapType and info.mapType >= Enum.UIMapType.Zone then
                -- prefer zone maps over sub-zones/dungeons with the same name
                local existing = mapByAreaName[info.name]
                if not existing or (info.mapType == Enum.UIMapType.Zone and existing.mapType ~= Enum.UIMapType.Zone) then
                    mapByAreaName[info.name] = { id = id, mapType = info.mapType }
                end
            end
        end
    end
    local found = mapByAreaName[name]
    return found and found.id
end

-- npc: { name, map = uiMapID } or { name, area = areaID } plus x, y in 0-100
function Waypoint.CanShow(npc)
    return npc and npc.x and npc.y and (npc.map or npc.area) and true or false
end

-- straight-line distance in yards from the player, or nil when not on the same continent / unknown.
-- Both points go through C_Map.GetWorldPosFromMapPos so their axes match.
function Waypoint.Distance(npc)
    if not Waypoint.CanShow(npc) or not C_Map.GetWorldPosFromMapPos then return end
    local map = npc.map or mapForArea(npc.area)
    local playerMap = C_Map.GetBestMapForUnit("player")
    local playerPos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
    if not map or not playerPos then return end
    local npcContinent, npcWorld = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(npc.x / 100, npc.y / 100))
    local playerContinent, playerWorld = C_Map.GetWorldPosFromMapPos(playerMap, playerPos)
    if not npcWorld or not playerWorld or npcContinent ~= playerContinent then return end
    local dx, dy = npcWorld.x - playerWorld.x, npcWorld.y - playerWorld.y
    return math.sqrt(dx * dx + dy * dy)
end

function Waypoint.Show(npc)
    local map = npc.map or mapForArea(npc.area)
    if not map then
        ns.Print(L.WAYPOINT_NO_MAP:format(npc.name or "?"))
        return
    end
    local x, y = npc.x / 100, npc.y / 100
    local tomtom = _G.TomTom
    if tomtom and tomtom.AddWaypoint then
        tomtom:AddWaypoint(map, x, y, { title = npc.name, from = addonName, persistent = false,
            minimap = true, world = true, crazy = true })
    elseif C_Map.SetUserWaypoint and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(map)) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end
    if not InCombatLockdown() then
        if OpenWorldMap then
            OpenWorldMap(map)
        else
            ShowUIPanel(WorldMapFrame)
            WorldMapFrame:SetMapID(map)
        end
    end
    local mapInfo = C_Map.GetMapInfo(map)
    ns.Print(L.WAYPOINT_SET:format(npc.name or "?", mapInfo and mapInfo.name or map, npc.x, npc.y))
end
