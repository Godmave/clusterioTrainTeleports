-- how many ticks between checks for work
TELEPORT_WORK_INTERVAL = 15
-- minimum time between teleports for one train
TELEPORT_COOLDOWN_TICKS = 120

fileName = "trainTeleports.txt"
-- json = require("json")

trainTrackingApi = require("train_tracking")
trainStopTrackingApi = require("train_stop_tracking")
guiApi = require("gui")

local function initialize()
    global.config = global.config or {}
    global.blockedStations = global.blockedStations or {}
    global.canSendTrain = global.canSendTrain or {}
    global.trainsToSend = global.trainsToSend  or {}
    global.trainsToSendRemote = global.trainsToSendRemote  or {}
    global.trainsToDestroy = global.trainsToDestroy  or {}
    global.trainsToSpawn = global.trainsToSpawn or {}
    global.trainLastSpawnTick = global.trainLastSpawnTick or {}
    global.zones = global.zones or {}
    global.stationQueue = global.stationQueue or {}
    global.servers = global.servers or {}
    global.trainsToResend = global.trainsToResend or {}
end

script.on_load(function()
    -- initialize()
end)

script.on_init(function()
    initialize()
end)



-- all events that are required in more than one place are handled here
script.on_event(defines.events.on_built_entity, trainStopTrackingApi.on_entity_built_event)
script.on_event(defines.events.on_robot_built_entity, trainStopTrackingApi.on_entity_built_event)
script.on_event(defines.events.script_raised_built, trainStopTrackingApi.script_raised_built)
script.on_event(defines.events.on_player_mined_entity, function(event)
    guiApi.checkForTrainStillValid(event)
    trainStopTrackingApi.on_entity_mined_event(event)
end)
script.on_event(defines.events.on_robot_mined_entity, function(event)
    guiApi.checkForTrainStillValid(event)
    trainStopTrackingApi.on_entity_mined_event(event)
end)
script.on_event(defines.events.script_raised_destroy, function(event)
    guiApi.checkForTrainStillValid(event)
    trainStopTrackingApi.script_raised_destroy(event)
end)
script.on_event(defines.events.on_entity_renamed, trainStopTrackingApi.on_entity_renamed)

script.on_event(defines.events.on_train_changed_state, trainTrackingApi.on_train_changed_state)
script.on_event(defines.events.on_train_schedule_changed, function(event)
    guiApi.on_train_schedule_changed(event)
    trainTrackingApi.on_train_schedule_changed(event)
end)
script.on_event(defines.events.on_entity_settings_pasted, trainTrackingApi.on_entity_settings_pasted)
script.on_event(defines.events.on_train_created, function(event)
    guiApi.checkForTrainIdChange(event)
    trainTrackingApi.on_train_created(event)
end)



remote.remove_interface("trainTeleportsTrainStopTracking")
remote.add_interface("trainTeleportsTrainStopTracking", {
    -- see if there is a station with that name here that could receive at least that many carriages
    checkByName = function(stationName, number_of_carriages)
        if number_of_carriages < 1 then
            number_of_carriages = 1
        end

        local foundFreeStation = false
        local currentStationStatus
        local station

        -- break on the first free station
        -- return free status or the fail status of the last checked station
        for i,v in pairs(global.shared_train_stops) do
            if v.name == stationName then
                station = v.entity
                currentStationStatus = trainStopTrackingApi.can_spawn_train(station, number_of_carriages)
                if currentStationStatus >= CAN_SPAWN_RESULT.ok then
                    foundFreeStation = true
                    break
                end
            end
        end

        return {stationId = station.unit_number, status=currentStationStatus }
    end
})

remote.remove_interface("trainTeleports");
remote.add_interface("trainTeleports", {
    setWorldId = function(newid)
        game.print("World-ID: "..newid)
        global.worldID = newid
    end,
    init = function()
        trainStopTrackingApi.initAllTrainstopsAndZones()
    end,
    json = function(jsonString)
        local data = game.json_to_table(jsonString)

        if data.event == "teleportTrain" then
            local train = data.train
            local targetStation = trainStopTrackingApi.find_station(data.destinationStationName, #train)
            local trainSchedule = data.train_schedule
            local sendingStationDirection = data.sendingStationDirection

            if not targetStation.valid then
                targetStation = trainStopTrackingApi.find_station(data.destinationStationName, 1)
            end

            if targetStation.valid then
                table.insert(global.trainsToSpawn, {targetStation = targetStation, train = train, schedule = trainSchedule, sendingStationDirection = sendingStationDirection })
                if global.stationQueue[targetStation.backer_name] == nil then
                    global.stationQueue[targetStation.backer_name] = 1
                else
                    global.stationQueue[targetStation.backer_name] = global.stationQueue[targetStation.backer_name] + 1
                end
            else
                log("can not spawn train, unavailable station: "..data.destinationStationName .. ". putting it in the queue, good luck!")
                game.print("can not spawn train, unavailable station: "..data.destinationStationName .. ". putting it in the queue, good luck!")
                table.insert(global.trainsToSpawn, {targetStation = nil, train = train, schedule = trainSchedule, sendingStationDirection = sendingStationDirection })
            end
        elseif data.event == "zones" then
            global.zones = data.zones or {}
            trainTrackingApi.initAllTrains()
            return true
        elseif data.event == "instances" then
            global.servers = data.data
        elseif data.event == "trains" then
            global.trainsKnownToInstances = data.trainsKnownToInstances
            global.trainStopTrains = data.trainStopTrains
        elseif data.event == "addRemoteTrain" then
            global.trainsKnownToInstances[tostring(data.instanceId)] = global.trainsKnownToInstances[tostring(data.instanceId)] or {}
            global.trainsKnownToInstances[tostring(data.instanceId)][tostring(data.trainId)] = data.train
            for _, stop in pairs(data.stops) do
                global.trainStopTrains[stop] = global.trainStopTrains[stop] or {}
                global.trainStopTrains[stop][tostring(data.instanceId)] = global.trainStopTrains[stop][tostring(data.instanceId)] or {}
                global.trainStopTrains[stop][tostring(data.instanceId)][tostring(data.trainId)] = 1
                guiApi.updateTrainstops(stop)
            end
            -- game.print("addTrain: " .. data.trainId)
        elseif data.event == "updateRemoteTrain" then
            global.trainsKnownToInstances[tostring(data.instanceId)][tostring(data.trainId)] = data.train
            guiApi.gui_trainstop_updatetrain(data.trainId, data.train)
            -- game.print("updateTrain:" .. data.trainId)
        elseif data.event == "removeRemoteTrain" then
            global.trainsKnownToInstances[tostring(data.instanceId)][tostring(data.trainId)] = nil
            for _, stop in pairs(data.stops) do
                if global.trainStopTrains and global.trainStopTrains[stop] and global.trainStopTrains[stop][tostring(data.instanceId)] and global.trainStopTrains[stop][tostring(data.instanceId)][tostring(data.trainId)] then
                    global.trainStopTrains[stop][tostring(data.instanceId)][tostring(data.trainId)] = nil
                end
                guiApi.updateTrainstops(stop)
            end
            -- game.print("removeTrain")
        elseif data.event == "trainReceived" then
            -- game.print("Destination received train with trainID: " .. data.trainId)
            if global.trainsToResend[tonumber(data.trainId)] then
                -- game.print("Removed from to resend list")
                global.trainsToResend[tonumber(data.trainId)] = nil
            end
        end

        rcon.print(1)
    end,
    updateStopInSchedules = function(instanceId, oldName, name)
        if tostring(instanceId) ~= tostring(global.worldID) then
            local instanceName = trainStopTrackingApi.lookupIdToServerName(instanceId)
            oldName = oldName .. " @ " .. instanceName
            name = name .. " @ " .. instanceName
        end

        for _, surface in pairs(game.surfaces) do
            local surfaceTrains = surface.get_trains()
            for _, train in pairs(surfaceTrains) do
                local schedule = train.schedule
                local isChanged = false
                if schedule ~= nil then
                    for _, record in pairs(schedule.records) do
                        if record.station == oldName then
                            record.station = name
                            isChanged = true
                        end
                    end
                end

                if isChanged then
                    train.schedule = schedule
                end
            end
        end
    end,
    runCode = function(code)
        --log("start running code:")
        --log(code);
        load(code, "trainTeleports code injection failed!", "t", _ENV)()
        --log("done running code")

    end
})


