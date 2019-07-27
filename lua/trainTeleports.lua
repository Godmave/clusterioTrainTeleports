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
end

script.on_load(function()
    -- initialize()
end)

script.on_init(function()
    initialize()
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


local function averageOfDifference( t )
    local count, sum, lastValue = 0,0,0

    for k,v in pairs(t) do
        if type(v) == 'number' then
            if lastValue > 0 then
                count = count + 1
                sum = sum + (v - lastValue)
            end
            lastValue = v
        end
    end

    if count == 0 then
        return 0
    end

    return math.floor((sum/count) + 0.5)
end


remote.remove_interface("trainTeleports");
remote.add_interface("trainTeleports", {
    setWorldId = function(newid)
        game.print("World-ID: "..newid)
        global.worldID = newid
    end,
    init = function()
        trainStopTrackingApi.initAllTrainstopsAndZones()
    end,
    reportPassedSecond = function()
        global.lastSecondTicks = global.lastSecondTicks or {}
        table.insert(global.lastSecondTicks, game.tick)
        if #global.lastSecondTicks > 5 then
            table.remove(global.lastSecondTicks, 1)
        end

        if #global.lastSecondTicks > 1 then
            guiApi.updateServerUPS(averageOfDifference(global.lastSecondTicks))
        end
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
        elseif data.event == "instances" then
            global.servers = data.data
        end

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


