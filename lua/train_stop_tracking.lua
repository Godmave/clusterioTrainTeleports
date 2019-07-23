CAN_SPAWN_RESULT = {
    ok = 0,
    blocked = 2,
    no_adjacent_rail = -1,
    not_enough_track = -2,
    no_station = -4,
}

local function undrawZoneBorders(zoneId)
    local zone = global.config.zones[tonumber(zoneId)]

    if zone == nil then
        return
    end
    local surface = game.surfaces[zone.surface or 'nauvis']

    -- top
    surface.destroy_decoratives{area={left_top = {zone.topleft[1], zone.topleft[2]}, right_bottom = {zone.bottomright[1], zone.topleft[2]}}}
    -- bottom
    surface.destroy_decoratives{area={left_top = {zone.topleft[1], zone.bottomright[2]}, right_bottom = {zone.bottomright[1], zone.bottomright[2]}}}
    -- left
    surface.destroy_decoratives{area={left_top = {zone.topleft[1], zone.topleft[2]}, right_bottom = {zone.topleft[1], zone.bottomright[2]}}}
    -- right
    surface.destroy_decoratives{area={left_top = {zone.bottomright[1], zone.topleft[2]}, right_bottom = {zone.bottomright[1], zone.bottomright[2]}}}
end

local function drawZoneBorders(zoneId)
    local zone = global.config.zones[tonumber(zoneId)]
    local surface = game.surfaces[zone.surface or 'nauvis']

    local decoratives = {}

    local x
    local y = zone.topleft[2]
    for x = zone.topleft[1], zone.bottomright[1], 1 do
        table.insert(decoratives, {name = "rock-medium", position={x=x, y=y}, amount=1})
    end

    x = zone.bottomright[1]
    for y = zone.topleft[2], zone.bottomright[2], 1 do
        table.insert(decoratives, {name = "rock-medium", position={x=x, y=y}, amount=1})
    end

    y = zone.bottomright[2]
    for x = zone.bottomright[1], zone.topleft[1], -1 do
        table.insert(decoratives, {name = "rock-medium", position={x=x, y=y}, amount=1})
    end

    x = zone.topleft[1]
    for y = zone.bottomright[2], zone.topleft[2], -1 do
        table.insert(decoratives, {name = "rock-medium", position={x=x, y=y}, amount=1})
    end

    surface.create_decoratives{decoratives = decoratives}
end

local function is_teleport_station(entity)
    if not entity.valid
            or entity.type ~= "train-stop"
            or entity.force ~= game.forces.player then
        return false
    end

    local entity_position = entity.position
    local entity_surface = entity.surface.name

    local in_zone = {}
    if global.config.zones ~= nil then
        for _, zone in pairs(global.config.zones) do
            zone.surface = zone.surface or "nauvis"
            if entity_surface == zone.surface and entity_position.x >= zone.topleft[1] and entity_position.x <= zone.bottomright[1] then
                if entity_position.y >= zone.topleft[2] and entity_position.y <= zone.bottomright[2] then
                    table.insert(in_zone, _)
                end
            end
        end
    end

    if #in_zone > 0 then
        global.zoneStops = global.zoneStops or {}
        global.stopZones = global.stopZones or {}
        global.stopZones[entity.unit_number] = global.stopZones[entity.unit_number] or {}

        -- remove stop from old zone(s)
        for zone_old in pairs(global.stopZones[entity.unit_number]) do
            if global.zoneStops[tonumber(zone_old)] ~= nil then
                global.zoneStops[tonumber(zone_old)][entity.unit_number] = nil
            end
        end
        global.stopZones[entity.unit_number] = {}

        for _, zone in ipairs(in_zone) do
            global.zoneStops[zone] = global.zoneStops[zone] or {}

            table.insert(global.stopZones[entity.unit_number], zone)
            global.zoneStops[zone][entity.unit_number] = entity
        end

        return true
    end

    return false
end

local function sanitize_stop_name(entity)
    local prefix = '<C>'
    local name = entity.backer_name

    if is_teleport_station(entity) then
        prefix = '<CT'..table.concat(global.stopZones[entity.unit_number], "+")..'>'
    end

    name = name:match'^()%s*$' and '' or name:match'^%s*(.*%S)'
    name = string.gsub(name, '@', " at ")
    name = string.gsub(name, '^<CT[0-9%+]*>', "")
    name = string.gsub(name, '^<C>', "")
    name = name:match'^()%s*$' and '' or name:match'^%s*(.*%S)'

    entity.backer_name = prefix .. " " .. name
end

local function updateTrainstop(entity)
    if not global.shared_train_stops then
        global.shared_train_stops = {}
    end
    if not global.stationQueue then
        global.stationQueue = {}
    end
    if not entity.valid then
        return
    end

    if global.stationQueue[entity.unit_number] then
        global.stationQueue[entity.unit_number] = nil
    end

    sanitize_stop_name(entity)

    if not global.stationQueue[entity.unit_number] then
        global.stationQueue[entity.unit_number] = 0
    end


    local entity_position = entity.position
    local registration = global.shared_train_stops[entity.unit_number]
    if not registration then
        registration = {
            name = entity.backer_name,
            entity = entity,
            x = entity_position.x,
            y = entity_position.y,
            surface = entity.surface.name,
            zones = {}
        }

        if global.stopZones and global.stopZones[entity.unit_number] then
            for _, zone in pairs(global.stopZones[entity.unit_number]) do
                table.insert(registration.zones, global.config.zones[zone].name)
            end
        end

        global.shared_train_stops[entity.unit_number] = registration

        local package = {
            event = "addStop",
            stop = {
                name = registration.name,
                x = registration.x,
                y = registration.y,
                surface = registration.surface,
                zones = registration.zones
            }
        }
        game.write_file(fileName, game.table_to_json(package) .. "\n", true, 0)

        -- game.write_file(fileName, "event:trainstop_added|name:"..entity.backer_name.."|x:"..entity_position.x.."|y:"..entity_position.y.."|s:"..entity.surface.name.."\n", true, 0)
    elseif registration.name ~= entity.backer_name then
        local oldName = registration.name
        registration.name = entity.backer_name
        registration.zones = {}

        if global.stopZones[entity.unit_number] then
            for _, zone in pairs(global.stopZones[entity.unit_number]) do
                if global.config.zones[zone] ~= nil then
                    table.insert(registration.zones, global.config.zones[zone].name)
                end
            end
        end

        local package = {
            event = "updateStop",
            stop = {
                oldName = oldName,
                name = registration.name,
                x = registration.x,
                y = registration.y,
                surface = registration.surface,
                zones = registration.zones
            }
        }
        game.write_file(fileName, game.table_to_json(package) .. "\n", true, 0)

        -- game.write_file(fileName, "event:trainstop_edited|name:"..entity.backer_name.."|oldName:"..registration.name.."|x:"..entity_position.x.."|y:"..entity_position.y.."|s:"..registration.surface.."\n", true, 0)
    end
end
local function remove_train_stop(entity)
    global.shared_train_stops[entity.unit_number] = nil

    local entity_position = entity.position
    game.write_file(fileName, "event:trainstop_removed|name:"..entity.backer_name.."|x:"..entity_position.x.."|y:"..entity_position.y.."|surface:"..entity.surface.name.."\n", true, 0)
end


local function rebuildInstanceLookup()
    local lookUpTableIdToServer = {}
    local lookUpTableNameToId = {}
    local lookUpTableServerStations = {}
    for _, s in ipairs(global.trainstopsData) do
        lookUpTableIdToServer[s.id] = s
        lookUpTableNameToId[s.name] = s.id

        lookUpTableServerStations[s.id] = {}
        for __, stop in ipairs(s.stations) do
            table.insert(lookUpTableServerStations[s.id], {stationName = stop})
        end
    end

    global.lookUpTableIdToServer = lookUpTableIdToServer
    global.lookUpTableNameToId = lookUpTableNameToId
    global.lookUpTableServerStations = lookUpTableServerStations
end


local function rebuildRemoteZonestops()
    global.remoteZoneStops = {}
    -- log(serpent.block(global.remoteStopZones))
    for _, stops in pairs(global.remoteStopZones) do
        local instanceId = _
        global.remoteZoneStops[instanceId] = {}
        for __, stopZones in pairs(stops) do
            local stopName = __
            for ___, zone in pairs(stopZones) do
                global.remoteZoneStops[instanceId][zone] = global.remoteZoneStops[instanceId][zone] or {}
                table.insert(global.remoteZoneStops[instanceId][zone], stopName)
            end
        end
    end
end


local function initAllTrainstopsAndZones()
    global.shared_train_stops = {}
    global.zoneStops = {}
    global.stopZones = {}
-- todo: iterate all surfaces here
    local all_stops = game.surfaces[1].find_entities_filtered{type = "train-stop"};
    for _, trainstop in ipairs(all_stops) do
        updateTrainstop(trainstop)
    end

    -- report configured zones
    local package = {
        event = "zones",
        worldId = global.worldID,
        zones = {}
    }
    if global.config.zones then
        for _, z  in pairs(global.config.zones) do
            package.zones[tostring(_)] = z
        end
    end

    game.write_file(fileName, game.table_to_json(package) .. "\n", true, 0)
end

local function lookupNameToId(serverName)
    return global.lookUpTableNameToId[serverName]
end


local function lookupIdToServer(id)
    return global.lookUpTableIdToServer[tonumber(id)]
end

local function lookupIdToServerName(id)
    if id ~= nil and id ~= 0 then
        return global.lookUpTableIdToServer[tonumber(id)].name
    elseif global.worldID ~= nil and global.lookUpTableIdToServer[tonumber(global.worldID)] ~= nil then
        -- if no id is given return my own
        return global.lookUpTableIdToServer[tonumber(global.worldID)].name
    end
end

local function on_entity_built(entity, player_index)
    if entity and entity.valid and entity.type == "train-stop" then

        if player_index ~= nil then
            if is_teleport_station(entity) then
                game.players[player_index].print("[Clusterio] Train station built in teleportation range")
            else
                game.players[player_index].print("[Clusterio] Train station built outside teleportation range")
            end
        end
        updateTrainstop(entity)

    end
end


local function can_spawn_train(station, carriage_count)
    if not (station and station.valid) then
        return CAN_SPAWN_RESULT.no_station
    end

    local cb = station.get_control_behavior()
    if cb and cb ~= nil and cb.disabled then
        return CAN_SPAWN_RESULT.no_station
    end

    local expected_direction, expected_rail_direction
    local rotation

    if bit32.band(station.direction, 2) == 0 then
        rotation =  { 1, 0, 0, 1 }
        expected_direction = defines.direction.north
    else
        rotation = { 0, -1, 1, 0 }
        expected_direction = defines.direction.east
    end
    if bit32.band(station.direction, 4) == 4 then
        for i = 1, 4 do rotation[i] = -rotation[i] end
    end
    expected_rail_direction = 1 - bit32.rshift(station.direction, 2)

    local rail = station.connected_rail
    if not rail then
        return CAN_SPAWN_RESULT.no_adjacent_rail
    end

    if rail.trains_in_block > 0 then
        return CAN_SPAWN_RESULT.blocked
    end

    --[[ math.ceil((count * 7 - 1) / 2) ]]
    local rail_sections_count = bit32.rshift(carriage_count * 7, 1)

    --[[ Figure out if there's enough rails to spawn the train ]]
    local connection_table = {
        rail_direction = expected_rail_direction,
        rail_connection_direction = defines.rail_connection_direction.straight,
    }
    local connected_rail = rail
    for i = 2, rail_sections_count do
        connected_rail = connected_rail.get_connected_rail(connection_table)
        if not connected_rail then
            return CAN_SPAWN_RESULT.not_enough_track
        end
    end


    return CAN_SPAWN_RESULT.ok
end

local function resolveStop(stopName)
    local serverName = ''
    if not string.find(stopName,"@", 1, true) then
        serverName = lookupIdToServerName()
    else
        serverName = stopName:match("@ (.*)$")
        stopName = stopName:match("^(<CT?[0-9%+]*> .*) @")
    end

    return stopName, serverName
end

local function isStopAvailable(stopName)
    local stopName, serverName = resolveStop(stopName)
    local serverId = lookupNameToId(serverName)

    if not lookupIdToServer(serverId) then
        return false
    end

    local found = false
    for _, s in ipairs(global.lookUpTableServerStations[tonumber(serverId)]) do
        if s.stationName == stopName then
            found = true
        end
    end

    return found
end

-- if there is no free station take the one with no queued trains
-- if all stations have queued trains report to the cluster that this stationname @ instance is full atm
local function find_station(stationName, trainSize, ignoreThisStationEntity)
    local laststation,station = {},{}
    local nextBestStation, bestStation = nil, nil

    -- local lookup
    if not string.find(stationName,"@", 1, true) then
        local fullName = stationName.." @ "..lookupIdToServerName()

        if global.shared_train_stops then -- and global.blockedStations[fullName] ~= true then
            for i,v in pairs(global.shared_train_stops) do
                if v.name == stationName and v.entity ~= ignoreThisStationEntity and v.entity.valid then
                    laststation = v.entity

                    if global.stationQueue[laststation.unit_number] == nil then
                        global.stationQueue[laststation.unit_number] = 0
                    end

                    if global.stationQueue[laststation.unit_number] == 0 then
                        local spawnStatus = can_spawn_train(laststation, trainSize)
                        if spawnStatus == CAN_SPAWN_RESULT.ok then
                            bestStation = laststation
                            break
                        elseif nextBestStation == nil and spawnStatus > CAN_SPAWN_RESULT.ok then
                            nextBestStation = laststation
                        end
                    end
                end
            end

            if bestStation ~= nil then
                station = bestStation
            elseif nextBestStation ~= nil then
                station = nextBestStation
            elseif laststation then
                -- try this, just so we have any station to pin a message on?
                station = laststation
            end

            -- this should only ever not be true if the train in question is too long for any of the stations or no station is valid at all
            if station and station.valid and station.unit_number then
                global.stationQueue[station.unit_number] = global.stationQueue[station.unit_number] + 1
                if global.stationQueue[station.unit_number] > 1 and global.blockedStations[fullName] ~= true then
                    -- message cluster that this station is full atm
                    game.print("block station "..fullName)
                    global.blockedStations[fullName] = true
                    game.write_file(fileName, "event:trainstop_blocked|name:"..fullName.."\n", true, 0)
                end
            end
        end
        -- remote
    else
        if not global.blockedStations[stationName] then
            local remoteStationName = stationName:match("^(<CT?[0-9%+]*> .*) @")
            local instanceName = stationName:match("@ (.*)$")
            local instanceId = lookupNameToId(instanceName)
            station = {
                remote = true,
                stationName = remoteStationName,
                instanceName = instanceName,
                instanceId = instanceId
            }
        end
    end

    return station
end




















local function on_entity_removed(entity)
    if entity and entity.valid and entity.type == "train-stop" then
        remove_train_stop(entity)
    end
end

local function on_entity_built_event(event)
    if not event then return end
    local entity = event.created_entity or event.entity
    if entity and entity.valid and entity.type == "train-stop" then
        on_entity_built(event.created_entity, event.player_index)
    end
end
local function on_entity_mined_event(event)
    if not event then return end
    local entity = event.entity
    if entity and entity.valid and entity.type == "train-stop" then
        on_entity_removed(event.entity)
    end
end

script.on_event(defines.events.on_built_entity, on_entity_built_event)
script.on_event(defines.events.on_robot_built_entity, on_entity_built_event)
script.on_event(defines.events.script_raised_built, function (event)
    if not event then return end
    local entity = event.created_entity or event.entity
    if type(entity) ~= "table" or type(entity.__self) ~= "userdata" or not entity.valid then return end
    on_entity_built(entity)
end)
script.on_event(defines.events.on_player_mined_entity, on_entity_mined_event)
script.on_event(defines.events.on_robot_mined_entity, on_entity_mined_event)
script.on_event(defines.events.script_raised_destroy, function (event)
    if not event then return end
    local entity = event.entity
    if type(entity) ~= "table" or type(entity.__self) ~= "userdata" or not entity.valid then return end
    on_entity_removed(entity)
end)
script.on_event(defines.events.on_entity_renamed, function (event)
    if not event then return end
    local entity = event.entity

    if entity and entity.valid and entity.type == "train-stop" then
        if not event.by_script then
            updateTrainstop(event.entity)
        end
    end
end)


local trainStopTrackingApi = setmetatable({
    rebuildInstanceLookup = rebuildInstanceLookup,
    initAllTrainstopsAndZones = initAllTrainstopsAndZones,
    lookupNameToId = lookupNameToId,
    lookupIdToServer = lookupIdToServer,
    lookupIdToServerName = lookupIdToServerName,
    isStopAvailable = isStopAvailable,
    find_station = find_station,
    can_spawn_train = can_spawn_train,
    undrawZoneBorders = undrawZoneBorders,
    drawZoneBorders = drawZoneBorders,
    updateTrainstop = updateTrainstop,
    resolveStop = resolveStop,
    rebuildRemoteZonestops = rebuildRemoteZonestops
},{
    __index = function(t, k)
    end,
    __newindex = function(t, k, v)
        -- do nothing, read-only table
    end,
    -- Don't let mods muck around
    __metatable = false,
})


return trainStopTrackingApi