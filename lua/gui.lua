--[[
todo:
- show stops per zone
later:
- custom trainstop gui
- show distance to destination
- remote train "map"
]]

require("mod-gui")

local alphanumcmp
do
    local function padnum(d) return ("%012d"):format(d) end
    alphanumcmp = function (a, b)
        return tostring(a):gsub("%d+",padnum) < tostring(b):gsub("%d+",padnum)
    end
end

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

local function gui_create(self)
    local root = mod_gui.get_frame_flow(self.player).add{
        type = "table",
        column_count = 1
    }

    local maintable = root.add{
        type = "table",
        caption = "Clusterio Trainstops",
        column_count = 3
    }
    maintable.vertical_centering = false
    maintable.style.horizontal_spacing = 0
    maintable.style.vertical_spacing = 0


    self.root = root
    root.style.horizontal_spacing = 0
    root.style.vertical_spacing = 0


    self.leftPane = root.add{type = 'frame', name = 'clusterio-trainteleport-serverstops', direction = 'vertical', caption = "Clusterio Trainstops"}
    self.rightPane = root.add{type = 'frame', name = 'clusterio-trainteleport-traintops', direction = 'vertical', caption = "Train-Schedule"}

    --[[
    self.toolPane = maintable.add{type = 'frame', name = 'clusterio-trainteleport-toolpane', direction = 'vertical', caption = ""}
    self.toolPane.style.width = 38
    self.toolPane.style.left_padding = 0
    self.toolPane.style.right_padding = 0

    local resetButton = self.toolPane.add{type="sprite-button", name="clusterio-trainteleport-reset", sprite="utility/reset"}
    resetButton.style.width = 32
    resetButton.style.height = 32

    local trashButton = self.toolPane.add{type="sprite-button", name="clusterio-trainteleport-remove", sprite="utility/remove"}
    trashButton.style.width = 32
    trashButton.style.height = 32

    local arrowUpButton = self.toolPane.add{type="sprite-button", name="clusterio-trainteleport-moveup", sprite="utility/hint_arrow_up"}
    arrowUpButton.style.width = 32
    arrowUpButton.style.height = 32

    local arrowDownButton = self.toolPane.add{type="sprite-button", name="clusterio-trainteleport-movedown", sprite="utility/hint_arrow_down"}
    arrowDownButton.style.width = 32
    arrowDownButton.style.height = 32
    ]]

    self.infoPane = root.add{type = 'frame', name = 'clusterio-trainteleport-infopane', direction = 'vertical', caption = "Info"}
    self.infoPane.visible = false
end
local function gui_destroy(self)
    if self == nil then
        return
    end

    if self.root and self.root.valid then
        self.root.destroy()
    end
    if self.rootTable and self.rootTable.valid then
        self.rootTable.destroy()
    end
end

local function gui_generic_dropdown(data, key, name, selectedIndex)
    local options = {
        type = "drop-down",
        name = name,
        style = "dropdown",
        items = {}
    }

    if data ~= nil and table_size(data) > 0 then
        for _, item in pairs(data) do
            table.insert(options.items, item[key])
        end
    end

    if #options.items > 0 then
        options.selected_index = selectedIndex or 1
    end

    return options
end


--todo?: allow own zone as reachable, but maybe not teleportable when not explicitly defined
local function collectReachables(serverName, stopName, onlyRestricted)
    local serverId = trainStopTrackingApi.lookupNameToId(serverName)
    local remoteStopZones = global.remoteStopZones[tostring(serverId)]
    local zones = stopName and remoteStopZones and remoteStopZones[stopName] or {}

    local reachableStops = {}
    reachableStops[serverName] = {}

    if zones and #zones > 0 then
        -- fetch all server zones
        local serverZones = global.zones[tostring(serverId)]
        if serverZones ~= nil then
            -- iterate all stop zones ...
            for _, stopZone in pairs(zones) do
                -- and get the zone definition ...
                for __, zone in pairs(serverZones) do

                    if zone.name~="" or serverId==global.worldID then
                        -- of any match or if this stop isn't in a teleport zone from all zones
                        if zone.name == stopZone or stopZone == "" then
                            -- if there are restrictions set ...
                            if zone.restrictions and #zone.restrictions > 0 then
                                -- collect the reachable stops per their definition
                                for ___, restriction in pairs(zone.restrictions) do
                                    if stopZone~="" or restriction.server == serverName then
                                        reachableStops[restriction.server] = reachableStops[restriction.server] or {}
                                        reachableStops[restriction.server][restriction.zone] = {}

                                        local serverZones = global.remoteZoneStops[tostring(trainStopTrackingApi.lookupNameToId(restriction.server))]
                                        if serverZones and serverZones[restriction.zone] then
                                            for ____, stopName in pairs(serverZones[restriction.zone]) do
                                                reachableStops[restriction.server][restriction.zone][stopName] = true
                                            end
                                        end
                                    end
                                end

                                reachableStops[serverName] = reachableStops[serverName] or {}
                                reachableStops[serverName][zone.name] = {}
                                local stops = global.remoteZoneStops[tostring(serverId)][zone.name]
                                if stops ~= nil then
                                    for stopId, stopName in pairs(stops) do
                                        reachableStops[serverName][zone.name][stopName] = true
                                    end
                                end

                            elseif not onlyRestricted then
                                -- allow any stop on the same server
                                reachableStops[serverName] = reachableStops[serverName] or {}
                                for zoneName, stops in pairs(global.remoteZoneStops[tostring(serverId)]) do
                                    reachableStops[serverName][zoneName] = {}
                                    for stopId, stopName in pairs(stops) do
                                        reachableStops[serverName][zoneName][stopName] = true
                                    end
                                end


                                -- and IF this is a teleport stop any teleport stop on other servers
                                if stopZone ~= "" then
                                    -- teleport stop

                                    for remoteServerId, zones in pairs(global.remoteZoneStops) do
                                        local remoteServerName = trainStopTrackingApi.lookupIdToServerName(remoteServerId)
                                        reachableStops[remoteServerName] = {}
                                        for zoneName, stops in pairs(zones) do
                                            reachableStops[remoteServerName][zoneName] = {}
                                            for stopId, stopName in pairs(stops) do
                                                reachableStops[remoteServerName][zoneName][stopName] = true
                                            end
                                        end
                                    end
                                end

                                -- since we got all possible stops stop iterating
                                goto gotthemall
                            end
                        end
                    end
                end
            end
        end

        ::gotthemall::

        if not onlyRestricted then
            -- add all stops from that server
            reachableStops[serverName] = reachableStops[serverName] or {}
            local zoneStops = global.remoteZoneStops[tostring(serverId)]
            if zoneStops ~= nil then
                for zoneName, stops in pairs(global.remoteZoneStops[tostring(serverId)]) do
                    reachableStops[serverName][zoneName] = {}
                    for stopId, stopName in pairs(stops) do
                        reachableStops[serverName][zoneName][stopName] = true
                    end
                end
            end


            -- add all non-teleporting stops from that server
            --[[
            if global.remoteZoneStops and global.remoteZoneStops[tostring(serverId)] and global.remoteZoneStops[tostring(serverId)][""] then
                reachableStops[serverName] = reachableStops[serverName] or {}
                reachableStops[serverName][""] = reachableStops[serverName][""] or {}
                for ____, stopName in pairs(global.remoteZoneStops[tostring(serverId)][""]) do
                    reachableStops[serverName][""][stopName] = true
                end
            end
            ]]
        end
    else
        -- most likely when no stop is added to the schedule yet, add all stops from this server
        reachableStops[serverName] = {}
        local zoneStops = global.remoteZoneStops[tostring(serverId)]
        if zoneStops ~= nil then
            for zoneName, stops in pairs(global.remoteZoneStops[tostring(serverId)]) do
                reachableStops[serverName][zoneName] = {}
                for stopId, stopName in pairs(stops) do
                    reachableStops[serverName][zoneName][stopName] = true
                end
            end
        end
    end
    return reachableStops
end


local function gui_serverdropdown(parent, self, selectedServer)
    local reachableServers = {}
    local selectedServerIndex = 1

    for _, server in pairs(self.remote_data) do
        for __ in pairs(self.reachableStops) do
            if __ == server.name then
                table.insert(reachableServers, server)
                if server.name == selectedServer then
                    selectedServerIndex = #reachableServers
                end
            end
        end
    end

    self.reachableServers = reachableServers


    local options = gui_generic_dropdown(reachableServers, "name", "clusterio-trainteleport-server", selectedServerIndex)

    local flow = parent.add{type="flow", direction="horizontal"}
    flow.add{type="label", caption="Server:"}
    self.serverdropdown = flow.add(options)
end

local function gui_serverstops(parent, self, selectedServer)
    local options = {
        type = "table",
        column_count = 1,
        name = "clusterio-trainteleport-serverstops",
        style = "table"
    }

    if self.serverstops == nil or self.serverstops.valid == false then
        local scroll = parent.add{type = "scroll-pane"}
        scroll.style.maximal_height = 500
        self.serverstops = scroll.add(options)
    else
        self.serverstops.clear()
    end
    self.serverstopdata = {}
    self.serverstop_selected = nil


    if table_size(self.reachableServers) == 0 then
        return
    end


    selectedServer = selectedServer or self.reachableServers[1].name

    for _, server in ipairs(self.remote_data) do
        if server.name == selectedServer then
            for _, station in ipairs(server.stations) do
                local reachable = false
                for zone, zoneStops in pairs(self.reachableStops[selectedServer]) do
                    for zoneStop in pairs(zoneStops) do
                        if zoneStop == station then
                            reachable = true
                            break
                        end
                    end
                end

                if reachable then
                    self.serverstops.add{type="label", name="clusterio-trainteleport-serverstop-".._, caption = station, style="hoverable_bold_label"}
                    self.serverstopdata[tonumber(_)] = station
                end
            end
        end
    end
end

local function gui_getstopcolor(station)
    if not trainStopTrackingApi.isStopAvailable(station) then
        -- not currently in the database (server down, not yet synced, or trainstop removed)
        return {r=1,b=0,g=0,a=1}
    elseif string.find(station, '<CT[0-9%+]*> ',1) then
        -- can teleport
        return {r=0,b=0,g=1,a=1}
    else
        return {r=1,b=1,g=1,a=1}
    end

end

local function gui_update_infopanel(state, server, stop)
    local fullStopname = stop.." @ "..server

    local stopType = "normal"
    if string.find(stop, '<CT',1,true) then
        stopType = "teleport"
    end

    local status = "online"
    if not trainStopTrackingApi.isStopAvailable(fullStopname) then
        status = "offline"
    end

    state.infoPane.clear()
    local infoTable = state.infoPane.add{type="table", column_count=2}
    infoTable.style.vertical_align = "top"

    infoTable.add{type="label", caption = "Stop:"}
    local stopLabel = infoTable.add{type="label", caption = fullStopname}
    stopLabel.style.font_color = gui_getstopcolor(fullStopname)

    infoTable.add{type="label", caption = "Type:"}
    infoTable.add{type="label", caption = stopType}

    infoTable.add{type="label", caption = "Status:"}
    infoTable.add{type="label", caption = status}

    if stopType == "teleport" then

        local reachableStops = collectReachables(server, stop, true)

        local t = infoTable.add{type="flow", direction="vertical"}
        t.style.vertical_align = "top"
        t.add{type="label", caption = "Restriction:"}

        local restrictionTable = infoTable.add{type="table", column_count=2}
        local anyRestrictions = false
        for server, zones in pairs(reachableStops) do
            if table_size(zones) > 0 then
                anyRestrictions = true
                local t = restrictionTable.add{type="flow", direction="vertical"}
                t.style.vertical_align = "top"
                t.add{type="label", caption=server}

                local zoneFlow = restrictionTable.add{type="flow", direction="vertical"}
                for zone, stops in pairs(zones) do
                    zoneFlow.add{type="label", caption=zone}
                end
            end
        end

        if not anyRestrictions then
            restrictionTable.add{type="label", caption="none"}
        end

    end

end

local function gui_markServerStop(state, station)
    state.lastSelectedStop = station
    state.infoPane.visible = true

    if state.lastSelectedScheduleStop ~= nil then
        for _, element in ipairs(state.trainstops.children) do
            if _ == state.lastSelectedScheduleStop then
                element.style.font_color = {r=1,b=0,g=1,a=1}
            else
                element.style.font_color = gui_getstopcolor(element.caption)
            end
        end
    end

    for _, element in ipairs(state.serverstops.children) do
        if element.caption == station then
            element.style.font_color = {r=0.7,b=0.7,g=0,a=1}

            local selectedServer = state.serverdropdown.items[state.serverdropdown.selected_index]
            local stopName = element.caption

            gui_update_infopanel(state, selectedServer, stopName)
        else
            element.style.font_color = {r=1,b=1,g=1,a=1}
        end
    end
end



local function gui_markScheduleStop(state, key)
    state.infoPane.visible = true
    state.lastSelectedScheduleStop = key

    -- unmark any server stops
    if state.lastSelectedStop ~= nil then
        state.lastSelectedStop = nil
        for _, element in ipairs(state.serverstops.children) do
            element.style.font_color = {r=1,b=1,g=1,a=1}
        end

    end

    local reachableStops = {}
    local stopName, serverName
    

    if #state.trainstops.children > 0 then
        for _, element in ipairs(state.trainstops.children) do
            if _ == key then
                element.style.font_color = {r=0.7,b=0.7,g=0,a=1}

                stopName, serverName = trainStopTrackingApi.resolveStop(element.caption)
                gui_update_infopanel(state, serverName, stopName)
                reachableStops = collectReachables(serverName, stopName)
            else
                element.style.font_color = gui_getstopcolor(element.caption)
            end
        end
    else
        -- show only this server
        serverName = trainStopTrackingApi.lookupIdToServerName()
        reachableStops = collectReachables(serverName)
    end

    state.reachableStops = reachableStops

    state.leftPane.clear()
    gui_serverdropdown(state.leftPane, state, serverName)
    gui_serverstops(state.leftPane, state, serverName)
end

local function gui_trainstops_add(self, station, _, current)
    local label = self.trainstops.add{type="label", name="clusterio-trainteleport-trainstop-".._, caption = station, style="hoverable_bold_label"}
    self.trainstopdata[tonumber(_)] = station

    if not current then
        label.style.font_color = gui_getstopcolor(station)
    else
        label.style.font_color = {r=1,b=0,g=1,a=1}
    end
end

local function gui_trainstops(parent, self)
    parent.clear()

    local options = {
        type = "table",
        column_count = 1,
        name = "clusterio-trainteleport-trainstops",
        style = "table"
    }

    local wrapper = parent.add{type="scroll-pane"}
    wrapper.style.maximal_height = 300

    self.trainstops = wrapper.add(options)
    self.trainstopdata = {}
    self.trainstop_selected = nil

    if self.train and self.train.valid and self.train.schedule and #self.train.schedule.records > 0 then
        if self.lastSelectedScheduleStop == nil then
            self.lastSelectedScheduleStop = self.train.schedule.current
        elseif self.lastSelectedScheduleStop > #self.train.schedule.records then
            self.lastSelectedScheduleStop = #self.train.schedule.records
        end

        for _, stop in ipairs(self.train.schedule.records) do
            if stop.station then
                gui_trainstops_add(self, stop.station, _)
            end
        end

    end
    gui_markScheduleStop(self, self.lastSelectedScheduleStop)
end

local function gui_populate(self, remote_data)
    table.sort(remote_data, function (a, b) return alphanumcmp(a.name, b.name) end)
    for _, server in ipairs(remote_data) do
        table.sort(server.stations, alphanumcmp)
    end
    self.remote_data = remote_data

    -- this one decides what to show on the leftPane, so needs to go first
    gui_trainstops(self.rightPane, self)
end

-- todo: support surface selection if there are more than nauvis available
local function gui_zonemanager_zone(zone_table, _, zone, lastZone )
    local name, tlx, tly, w, h = "Zone ".._, "", "", "", ""
    if zone ~= nil then
        name = zone.name or name
        tlx = zone.topleft[1]
        tly = zone.topleft[2]
        w = tonumber(zone.bottomright[1] - zone.topleft[1])
        h = tonumber(zone.bottomright[2] - zone.topleft[2])
    end

    zone_table.add{type="textfield", name='clusterio-trainteleport-zonemanager-zone-'.._.."-name", text = name}
    zone_table.add{type="textfield", name='clusterio-trainteleport-zonemanager-zone-'.._.."-tlx", text = tlx}
    zone_table.add{type="textfield", name='clusterio-trainteleport-zonemanager-zone-'.._.."-tly", text = tly}
    zone_table.add{type="textfield", name='clusterio-trainteleport-zonemanager-zone-'.._.."-w", text = w}
    zone_table.add{type="textfield", name='clusterio-trainteleport-zonemanager-zone-'.._.."-h", text = h}

    local button_flow = zone_table.add{name="clusterio-trainteleport-zonemanager-zone-".._.."-buttons", type="flow", direction="horizontal"}

    button_flow.add{type="sprite-button", name='clusterio-trainteleport-zonemanager-zone-'.._.."-save", sprite="utility/confirm_slot"}
    if zone ~= nil and lastZone then
        button_flow.add{type="sprite-button", name='clusterio-trainteleport-zonemanager-zone-'.._.."-remove", sprite="utility/remove"}
    end
end

local function addTabAndPanel(state, name, caption, selected)
    local container = state.container
    local tabContainer = state.tabContainer

    state.tabNames = state.tabNames or {}

    state.tabNames[name] = name

    local tab
    tab = tabContainer.add{type="button", name="clusterio-trainteleport-zonemanager-tab-"..name, style="image_tab_slot", caption=caption}
    if selected then
        tab.visible = false
    end
    tab.style.height = 30
    tab.style.width = 120

    tab = tabContainer.add{type="button", name="clusterio-trainteleport-zonemanager-tab-"..name.."-selected", style="image_tab_selected_slot", caption=caption}
    if not selected then
        tab.visible = false
    end
    tab.style.height = 30
    tab.style.width = 120

    local tabPanel = container.add{type="frame", name="clusterio-trainteleport-zonemanager-"..name.."-frame", direction="vertical"}
    if not selected then
        tabPanel.visible = false
    end

    return tabPanel
end

-- drops and recreates the global zonetable for the current player using global.config.zones
local function gui_zonemanager_zones(player_index)
    global.zonemanager[player_index].zonesFrame.clear()
    global.zonemanager[player_index].zoneTable = global.zonemanager[player_index].zonesFrame.add{type="table", name = 'clusterio-trainteleport-zonemanager-zone', column_count=6, draw_horizontal_line_after_headers = false}
    local zone_table = global.zonemanager[player_index].zoneTable
    zone_table.add{type="label", caption="Zone-Name"}
    zone_table.add{type="label", caption="Top-Left-X"}
    zone_table.add{type="label", caption="Top-Left-Y"}
    zone_table.add{type="label", caption="Width"}
    zone_table.add{type="label", caption="Height"}
    zone_table.add{type="label", caption=""}
    if not global.config.zones then
        global.config.zones = {}
    end
    if #global.config.zones > 0 then
        local numberOfZones = table_size(global.config.zones)
        local currentZoneIndex = 1
        for _, zone in pairs(global.config.zones) do
            gui_zonemanager_zone(zone_table, _, zone, currentZoneIndex == numberOfZones)
            currentZoneIndex = currentZoneIndex + 1
        end
    end
    gui_zonemanager_zone(zone_table, #global.config.zones + 1, nil)

end

local function zoneAvailable(serverName, zoneName)
    local serverId = trainStopTrackingApi.lookupNameToId(serverName)
    local serverZones = global.zones[tostring(serverId)]

    for __, zone in pairs(serverZones) do
        if zone.name == zoneName then
            return true
        end
    end

    return false
end

local function gui_zonemanager_zonerestriction(parent, _, restrictions, removeOnly)
    local server, zone = 1, 1
    local serverId
    local serverZones

    if not removeOnly then

        if restrictions[_] ~= nil then
            server = restrictions[_].server
            zone = restrictions[_].zone

            local found = false

            for _, s in pairs(global.trainstopsData) do
                if s.name == server then
                    server = _
                    serverId = tostring(s.id)
                    found = true
                    break;
                end
            end
            if not found then
                server = 1
            end

            serverZones = global.zones[serverId] or global.zones[tonumber(serverId)] or {}
            found = false
            for _, z in pairs(serverZones) do
                if z.name == zone then
                    zone = _
                    found = true
                    break;
                end
            end

            if not found then
                zone = 1
            end

        else
            serverId = tostring(global.trainstopsData[server].id)
            serverZones = global.zones[serverId] or global.zones[tonumber(serverId)]
        end

        local ddname = "clusterio-trainteleport-restriction-".._.."-server"
        local options = gui_generic_dropdown(global.trainstopsData, "name", ddname, server)
        parent.add(options)

        ddname = "clusterio-trainteleport-restriction-".._.."-zone"
        options = gui_generic_dropdown(serverZones, "name", ddname, zone)

        if options.selected_index then
            parent.add(options)
        else
            parent.add({type="label", caption = "no zones"})
        end
    else
        local server = parent.add{type="label", caption=restrictions[_].server}
        local zone = parent.add{type="label", caption=restrictions[_].zone}

        if not trainStopTrackingApi.lookupNameToId(restrictions[_].server) then
            server.style.font_color = {r=1,g=0,b=0}
            zone.style.font_color = {r=1,g=0,b=0}
        else
            if not zoneAvailable(restrictions[_].server, restrictions[_].zone) then
                zone.style.font_color = {r=1,g=0,b=0}
            end
        end

    end


    local button_flow = parent.add{name="clusterio-trainteleport-restriction-".._.."-buttons", type="flow", direction="horizontal"}

    if not removeOnly then
        button_flow.add{type="sprite-button", name='clusterio-trainteleport-restriction-'.._.."-save", sprite="utility/confirm_slot"}
    end
    if restrictions[_] ~= nil then
        button_flow.add{type="sprite-button", name='clusterio-trainteleport-restriction-'.._.."-remove", sprite="utility/remove"}
    end
end


local function gui_zonemanager_restrictions(player_index)
    local state = global.zonemanager[player_index]
    local frame = global.zonemanager[player_index].restrictionsFrame
    frame.clear()

    if table_size(global.config.zones) == 0 then
        return
    end

    state.selectedZone = state.selectedZone or 1

    if not global.config.zones[state.selectedZone] then
        state.selectedZone = 1
    end
    if not global.config.zones[state.selectedZone] then
        return
    end

    local options = gui_generic_dropdown(global.config.zones, "name", "clusterio-trainteleport-restriction-zone", state.selectedZone)

    local flow = frame.add{type="flow", direction="horizontal"}
    flow.add{type="label", caption="Zone:"}
    global.zonemanager[player_index].zonedropdown = flow.add(options)


    global.zonemanager[player_index].restrictionsTable = global.zonemanager[player_index].restrictionsFrame.add{type="table", name = 'clusterio-trainteleport-zonemanager-restriction', column_count=3, draw_horizontal_line_after_headers = false}
    local table = global.zonemanager[player_index].restrictionsTable
    table.add{type="label", caption="Server"}
    table.add{type="label", caption="Zone"}
    table.add{type="label", caption=""}

    global.config.zones[state.selectedZone].restrictions = global.config.zones[state.selectedZone].restrictions or {}

    for _, restriction in pairs(global.config.zones[state.selectedZone].restrictions) do
        gui_zonemanager_zonerestriction(table, _, global.config.zones[state.selectedZone].restrictions, true)
    end

    gui_zonemanager_zonerestriction(table, #global.config.zones[state.selectedZone].restrictions + 1, global.config.zones[state.selectedZone].restrictions)

end

--todo: show stops of selected zone if any
local function gui_zonemanager_stops(player_index)
    local frame = global.zonemanager[player_index].stopsFrame
    frame.clear()

    local options = {
        type = "drop-down",
        name = "clusterio-trainteleport-stops-zone",
        style = "dropdown",
        items = {}
    }

    if #global.config.zones > 0 then
        for _, zone in pairs(global.config.zones) do
            table.insert(options.items, zone.name)
        end
    end

    if #options.items > 0 then
        options.selected_index = 1
    end

    local flow = frame.add{type="flow", direction="horizontal"}
    flow.add{type="label", caption="Zone:"}
    global.zonemanager[player_index].zonedropdown = flow.add(options)

end

local function gui_serverconnect(player_index)
    if table_size(global.servers) == 0 then
        return
    end

    if global.serverconnect == nil then
        global.serverconnect = {}
    end

    local player = game.players[player_index]

    if global.serverconnect[player_index] then
        global.serverconnect[player_index].gui.destroy()
        global.serverconnect[player_index] = nil
        player.opened = nil
        return
    end

    if not (global.worldID and global.servers[tostring(global.worldID)] and global.servers[tostring(global.worldID)].instanceName) then
        return
    end

    global.serverconnect[player_index] = {}
    global.serverconnect[player_index].gui = player.gui.top.add{type = 'frame', name = 'clusterio-serverconnect', direction = 'vertical', caption = 'You are on "' .. (global.servers and global.servers[tostring(global.worldID)] and global.servers[tostring(global.worldID)].instanceName) .. '". Where to go now?'}
    local gui = global.serverconnect[player_index].gui
    player.opened = gui

    global.serverconnect[player_index].servermap = {}
    local servercolumcount = math.ceil(table_size(global.servers) / 10)

    local columnServers = {}
    local serverIndex = 1
    for _, server in pairs(global.servers) do
        if tostring(_) == tostring(global.worldID) then
        else
            local column = 1 + (serverIndex % servercolumcount)
            local row = math.ceil(serverIndex / servercolumcount)

            if not global.serverconnect[player_index].servermap[column] then
                global.serverconnect[player_index].servermap[column] = {}
            end
            if not columnServers[column] then
                columnServers[column] = {}
            end

            global.serverconnect[player_index].servermap[column][row] = server
            columnServers[column][row] = {"", server.instanceName}
            serverIndex = serverIndex + 1
        end
    end

    local table = gui.add{type="table", column_count=servercolumcount}
    for i=1, servercolumcount, 1 do
        table.add{type="list-box", name="clusterio-servers-" .. i, items=columnServers[i]};
    end
end


local function gui_zonemanager(player_index)
    if global.zones == nil then
        global.zones = {}
    end

    if tonumber(global.worldID) == 0 or global.lookUpTableIdToServer == nil or global.lookUpTableIdToServer[tonumber(global.worldID)] == nil then
        return
    end

    if global.zonemanager == nil then
        global.zonemanager = {}
    end

    local player = game.players[player_index]


    if global.zonemanager[player_index] then
        global.zonemanager[player_index].gui.destroy()
        global.zonemanager[player_index] = nil
        player.opened = nil
        return
    end


    global.zonemanager[player_index] = {}
    global.zonemanager[player_index].gui = player.gui.center.add{type = 'frame', name = 'clusterio-trainteleport-zonemanager', direction = 'vertical', caption = 'Zone-Manager'}
    local gui = global.zonemanager[player_index].gui
    player.opened = gui

    global.zonemanager[player_index].container = gui.add{type="table", column_count=1}
    local tightFrame = global.zonemanager[player_index].container
    tightFrame.style.horizontal_spacing = 0
    tightFrame.style.vertical_spacing = 0


    global.zonemanager[player_index].tabContainer = tightFrame.add{type="table", column_count=3}
    local tabContainer = global.zonemanager[player_index].tabContainer
    tabContainer.style.horizontal_spacing = 0
    tabContainer.style.vertical_spacing = 0
    tabContainer.style.left_padding = 2

    global.zonemanager[player_index].zonesFrame = addTabAndPanel(global.zonemanager[player_index], "zones", "Zones", true)
    gui_zonemanager_zones(player_index)

    global.zonemanager[player_index].restrictionsFrame = addTabAndPanel(global.zonemanager[player_index], "restrictions", "Restrictions")
    global.zonemanager[player_index].stopsFrame = addTabAndPanel(global.zonemanager[player_index], "stops", "Stops")
end


script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local player_index = event.player_index
    local element = event.element
    local element_name = element.name

    if string.find(element_name, 'clusterio-servers-',1,true) then
        local selected_index = element.selected_index

        local column = string.gsub(element_name, '^clusterio%-servers%-', "")

        local server = global.serverconnect[player_index]
                    and global.serverconnect[player_index].servermap
                    and global.serverconnect[player_index].servermap[tonumber(column)]
                    and global.serverconnect[player_index].servermap[tonumber(column)][selected_index]

        if server then
            game.players[player_index].connect_to_server({address = server.publicIP .. ":" .. server.serverPort, name = server.instanceName})
        end

        gui_serverconnect(player_index)
        return
    end



    element_name = string.gsub(element_name, '^clusterio%-trainteleport%-', "")

    if element_name == "server" then
        local state = global.custom_locomotive_gui and global.custom_locomotive_gui[event.player_index]
        if not state then
            return
        end

        local selectedServer = state.serverdropdown.items[state.serverdropdown.selected_index]
        gui_serverstops(state.leftPane, state, selectedServer)

        return
    end

    if string.find(element_name, 'restriction-',1,true) then
        local state = global.zonemanager[event.player_index]
        if state == nil then global.zonemanager[event.player_index] = {} end
        element_name = string.gsub(element_name, '^restriction%-', "")

        if element_name == "zone" then
            -- restrictions zone selector
            state.selectedZone = event.element.selected_index
            gui_zonemanager_restrictions(event.player_index)
        else
            local fields = element_name:split('-')
            local _ = fields[1] or ""
            local what = fields[2] or ""

            if what == "server" then
                -- changed server, load that servers zones in the zone dropdown of this restriction row

                local server = event.element.items[event.element.selected_index]
                local serverId
                for __, s in pairs(global.trainstopsData) do
                    if s.name == server then
                        server = __
                        serverId = tostring(s.id)
                        break;
                    end
                end

                local serverZones = global.zones[serverId] or global.zones[tonumber(serverId)] or {}

                global.zonemanager[event.player_index].restrictionsTable["clusterio-trainteleport-restriction-".._.."-zone"].clear_items()
                if table_size(serverZones) > 0 then
                    for __, z in pairs(serverZones) do
                        global.zonemanager[event.player_index].restrictionsTable["clusterio-trainteleport-restriction-".._.."-zone"].add_item(z.name, __)
                    end
                    global.zonemanager[event.player_index].restrictionsTable["clusterio-trainteleport-restriction-".._.."-zone"].selected_index = 1
                end
            end
        end

    end

end)
script.on_event(defines.events.on_gui_elem_changed, function(event)
    game.print("on_gui_elem_changed")
    log(serpent.block(event))
end)
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    game.print("on_gui_checked_state_changed")
    log(serpent.block(event))
end)
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    game.print("on_gui_checked_state_changed")
    log(serpent.block(event))
end)
script.on_event(defines.events.on_gui_value_changed, function(event)
    game.print("on_gui_value_changed")
    log(serpent.block(event))
end)



script.on_event(defines.events.on_gui_opened, function(event)
    local player = game.players[event.player_index]
    local entity = event.entity
    if not entity or entity.type ~= "locomotive" then
        return
    end
    if tonumber(global.worldID) == 0 or global.lookUpTableIdToServer == nil or global.lookUpTableIdToServer[tonumber(global.worldID)] == nil or global.zones == nil then
        return
    end

    local train = entity.train

    if global.custom_locomotive_gui == nil then
        global.custom_locomotive_gui = {}
    end

    local state = global.custom_locomotive_gui[player.index]
    if state ~= nil then
        gui_destroy(state)
    end
    state = {}
    global.custom_locomotive_gui[player.index] = state

    state.player = player
    state.train = train
    state.trainId = train.id
    state.entity = entity

    gui_create(state)
    gui_populate(state, global.trainstopsData)
end)

script.__on_configuration_changed = function()
    return
end


-- refresh the trainstop list when a player changes the schedule
script.on_event(defines.events.on_train_schedule_changed, function(event)
    local train = event.train
    local player_index = event.player_index
    if player_index then
        if global.custom_locomotive_gui then
            for _, state in pairs(global.custom_locomotive_gui) do
                if state.train and state.train.valid and state.train.id == train.id then
                    gui_trainstops(state.rightPane, state)
                end
            end
        end

    end

end)


local function checkForTrainStillValid(event)
    if event.entity then
        if event.entity.type == "locomotive" then
        elseif event.entity.type == "cargo-wagon" then
        elseif event.entity.type == "fluid-wagon" then
        elseif event.entity.type == "artillery-wagon" then
        else
            return
        end
    end
    if global.custom_locomotive_gui then
        for k, state in pairs(global.custom_locomotive_gui) do
            if state then
                if state.entity ~= nil then
                    if not state.entity.valid then
                        global.custom_locomotive_gui[k] = nil
                        gui_destroy(state)
                    end
                end
            end
        end
    end
end

local function checkForTrainIdChange(event)
    if global.custom_locomotive_gui then
        for k, state in pairs(global.custom_locomotive_gui) do
            if event.old_train_id_1 ~= nil and state.trainId and state.trainId == event.old_train_id_1 then
                state.train = event.train
                state.trainId = event.train.id
            end
            if event.old_train_id_2 ~= nil and state.trainId and state.trainId == event.old_train_id_2 then
                state.train = event.train
                state.trainId = event.train.id
            end
        end
    end
end

script.on_event(defines.events.on_train_created, checkForTrainIdChange)
script.on_event(defines.events.script_raised_destroy, checkForTrainStillValid)
script.on_event(defines.events.on_player_mined_entity, checkForTrainStillValid)
script.on_event(defines.events.on_robot_mined_entity, checkForTrainStillValid)

script.on_event(defines.events.on_gui_closed, function (event)
    local player_index = event.player_index
    local entity = event.entity

    if global.zonemanager and global.zonemanager[player_index] and global.zonemanager[player_index].gui and event.element == global.zonemanager[player_index].gui then
        game.players[player_index].play_sound{path = "utility/gui_click"}
        gui_zonemanager(player_index)
        return
    end

    if not entity or entity.type ~= "locomotive" then
        return
    end

    if global.custom_locomotive_gui then
        local state = global.custom_locomotive_gui[player_index]
        global.custom_locomotive_gui[player_index] = nil
        gui_destroy(state)
    end
end)

script.on_event(defines.events.on_gui_click, function (event)
    local element_name = event.element.name

    -- serverconnect top-button
    if element_name == "clusterio-serverconnect" then
        gui_serverconnect(event.player_index)
        return
    end

    -- zonemanager top-button
    if element_name == "clusterio-trainteleport" then
        gui_zonemanager(event.player_index)
        return
    end

    if string.find(element_name, 'clusterio-server-',1,true) then
        element_name = string.gsub(element_name, '^clusterio%-server%-', "")
        local server = global.servers[element_name]

        if server then
            game.players[event.player_index].connect_to_server({address = server.publicIP .. ":" .. server.serverPort, name = server.instanceName})
            gui_serverconnect(event.player_index)
        end

        return
    end

    -- zonemanager gui clicks
    element_name = string.gsub(element_name, '^clusterio%-trainteleport%-', "")
    if string.find(element_name, 'zonemanager-zone-',1,true) then
        local key = string.gsub(element_name, 'zonemanager%-zone%-', "")
        local fields = key:split('-')
        local _ = fields[1] or "" --zoneIndex
        local what = fields[2] or "" --guiClickType

        if _ == "" or what == "" then
            return
        end

        local zone = global.zonemanager[event.player_index].zoneTable
        local zoneConfig = global.config.zones[tonumber(_)] or {}

        local allAffectedStops = {}
        if global.zoneStops[tonumber(_)] ~= nil then
            for unit_number, stop in pairs(global.zoneStops[tonumber(_)]) do
                allAffectedStops[unit_number] = stop
            end
        end

        if what == "save" then
            trainStopTrackingApi.undrawZoneBorders(_)
            local prefix = 'clusterio-trainteleport-zonemanager-zone-'.._
            local x,y,w,h
            x = tonumber(zone[prefix.."-tlx"].text) or 0
            y = tonumber(zone[prefix.."-tly"].text) or 0
            w = tonumber(zone[prefix.."-w"].text) or 0
            h = tonumber(zone[prefix.."-h"].text) or 0
            local zoneName = zone[prefix.."-name"].text
            -- create zone
            CreateZone(zoneName, x, y, w, h, tonumber(_), true)
            -- refresh gui
            gui_zonemanager_zones(event.player_index)
        elseif what == "remove" and global.config.zones[tonumber(_)] ~= nil then
            trainStopTrackingApi.undrawZoneBorders(_)
            global.config.zones[tonumber(_)] = nil

            local package = {
                event = "removezone",
                worldId = global.worldID,
                zoneId = _
            }
            game.write_file(fileName, game.table_to_json(package) .. "\n", true, 0)

            gui_zonemanager_zones(event.player_index)
        else
            -- no stop update needed
            allAffectedStops = {}
        end

        for _, trainstop in pairs(allAffectedStops) do
            trainStopTrackingApi.updateTrainstop(trainstop)
        end


        return
    end

    if string.find(element_name, 'zonemanager-tab-',1,true) then
        local tab = string.gsub(element_name, 'zonemanager%-tab%-', "")

        if global.trainstopsData == nil or #global.trainstopsData == 0 or string.find(tab, "-selected", 1, true) then
            return -- ignore clicks on already active tabs (for now)
        else
            local state = global.zonemanager[event.player_index]
            for _ in pairs(state.tabNames) do
                if _ == tab then
                    state.tabContainer['clusterio-trainteleport-zonemanager-tab-'.._].visible = false
                    state.tabContainer['clusterio-trainteleport-zonemanager-tab-'.._..'-selected'].visible = true
                    state.container['clusterio-trainteleport-zonemanager-'.._..'-frame'].visible = true
                else
                    state.tabContainer['clusterio-trainteleport-zonemanager-tab-'.._].visible = true
                    state.tabContainer['clusterio-trainteleport-zonemanager-tab-'.._..'-selected'].visible = false
                    state.container['clusterio-trainteleport-zonemanager-'.._..'-frame'].visible = false
                end
            end

            if tab == "zones" then
                gui_zonemanager_zones(event.player_index)
            elseif tab == "restrictions" then
                state.selectedZone = 1
                gui_zonemanager_restrictions(event.player_index)
            elseif tab == "stops" then
                state.selectedZone = 1
                gui_zonemanager_stops(event.player_index)
            end
        end

        return
    end

    if string.find(element_name, 'restriction-',1,true) then
        local key = string.gsub(element_name, '^restriction%-', "")
        local fields = key:split('-')
        local _ = fields[1] or 1
        local what = fields[2] or ""

        local zoneIndex = global.zonemanager[event.player_index].selectedZone


        if what == "save" then

            local serverToSaveIndex = "clusterio-trainteleport-restriction-".._.."-server"
            local restrictionsTable = global.zonemanager[event.player_index].restrictionsTable
            local restrictionsTableItem = restrictionsTable[serverToSaveIndex]
            local serverToSave = restrictionsTableItem.get_item(restrictionsTableItem.selected_index)
            --game.write_file("trainTeleports.log", "Saving Zone Restriction: serverToSaveIndex = "..serverToSaveIndex.."\n", true, 0)
            --game.write_file("trainTeleports.log", "Saving Zone Restriction: serverToSave = "..serverToSave.."\n", true, 0)


            local zoneToSaveIndex = "clusterio-trainteleport-restriction-".._.."-zone"
            --game.write_file("trainTeleports.log", "Saving Zone Restriction: zoneToSaveIndex = "..zoneToSaveIndex.."\n", true, 0)

            -- save or add this restriction to the currently selected zone
            global.config.zones[zoneIndex].restrictions[tonumber(_)] = {
                server = serverToSave,
                zone = nil
            }
            if restrictionsTable[zoneToSaveIndex].selected_index then
                global.config.zones[zoneIndex].restrictions[tonumber(_)]["zone"] = restrictionsTable[zoneToSaveIndex].get_item(restrictionsTable[zoneToSaveIndex].selected_index)
            end
        elseif what == "remove" then
            -- remove this restriction from the currently selected zone
            global.config.zones[zoneIndex].restrictions[tonumber(_)] = nil
        else
            return
        end

        local package = {
            event = "savezone",
            worldId = global.worldID,
            zoneId = zoneIndex,
            zone = global.config.zones[zoneIndex]
        }
        game.write_file(fileName, game.table_to_json(package) .. "\n", true, 0)
        gui_zonemanager_restrictions(event.player_index)
    end



    -- custom loco gui checks
    local state = global.custom_locomotive_gui and global.custom_locomotive_gui[event.player_index]
    if state then
        if string.find(element_name, 'serverstop-',1,true) then
            local key = string.gsub(element_name, 'serverstop%-', "")
            local station = state.serverstopdata[tonumber(key)] or "unknown"

            -- only copy if already selected, simulating a double click
            if state.lastSelectedStop and station == state.lastSelectedStop then
                local selectedServer = state.serverdropdown.items[state.serverdropdown.selected_index]
                local currentServer = trainStopTrackingApi.lookupIdToServerName()

                if selectedServer ~= currentServer then
                    station = station .. " @ " .. selectedServer
                end

                gui_trainstops_add(state, station, #state.trainstopdata + 1)

                local schedule = state.train and state.train.valid and state.train.schedule
                if schedule == nil then
                    schedule = {
                        current = 1,
                        records = {}
                    }
                end

                -- only add if both stops are teleport stops and reachable
                local override_wait_condition
                if schedule.records and state.lastSelectedScheduleStop and schedule.records[state.lastSelectedScheduleStop] then
                    local lastStop = schedule.records[state.lastSelectedScheduleStop].station
                    -- log("going from: " .. lastStop .. " to: " .. station)

                    local lastStopServerName
                    if not string.find(lastStop,"@", 1, true) then
                        lastStopServerName = currentServer
                    else
                        lastStopServerName = lastStop:match("@ (.*)$")
                    end

                    if string.find(lastStop, '<CT',1,true)
                            and string.find(station, '<CT',1,true)
                            and lastStopServerName ~= selectedServer
                    then
                        override_wait_condition = true
                    end
                end

                if override_wait_condition then
                    override_wait_condition = {
                        type = "circuit",
                        compare_type = "or",
                        condition = {
                            comparator = "=",
                            first_signal = {type="virtual", name="signal-T"},
                            second_signal = {type="virtual", name="signal-T"}
                        }
                    }
                end

                if state.lastSelectedScheduleStop and state.lastSelectedScheduleStop < #schedule.records then

                    local records = {}
                    for _, record in pairs(schedule.records) do
                        records[#records+1] = record

                        if _ == state.lastSelectedScheduleStop then
                            if override_wait_condition then
                                records[#records]['wait_conditions'] = { override_wait_condition }
                            end

                            records[#records+1] = {
                                station = station,
                                wait_conditions = {}
                            }
                        end
                    end

                    state.lastSelectedScheduleStop = state.lastSelectedScheduleStop + 1

                    schedule.records = records
                else
                    if #schedule.records > 0 and override_wait_condition then
                        schedule.records[#schedule.records]['wait_conditions'] = { override_wait_condition }
                    end

                    schedule.records[#schedule.records + 1] = {
                        station = station,
                        wait_conditions = {}
                    }

                    state.lastSelectedScheduleStop = #schedule.records
                end
                if state.train and state.train.valid then
                    state.train.schedule = schedule
                    gui_trainstops(state.rightPane, state)
                end
            else
                gui_markServerStop(state, station)
            end

        elseif string.find(element_name, 'trainstop-',1,true) then
            local key = string.gsub(element_name, 'trainstop%-', "")
            key = tonumber(key)

            if key == state.lastSelectedScheduleStop then
                local schedule = state.train and state.train.valid and state.train.schedule
                if schedule ~= nil then
                    schedule.current = key
                    state.train.schedule = schedule
                else
                    gui_trainstops(state.rightPane, state)
                end
            end
            gui_markScheduleStop(state, key)
        else
            -- game.print("clicked: " .. element_name)
            if element_name == "reset" then
                gui_trainstops(state.rightPane, state)
            end
        end
    end
end)


local function checkbutton(e)
    local player = game.players[e.player_index]

    -- todo: maybe integrate with clusterio-mod after a rewrite of that ones gui
    -- clusterio-main-config-gui-toggle-button

    local anchorpoint = mod_gui.get_button_flow(player)
    local button = anchorpoint["clusterio-trainteleport"]

    if button then
        button.destroy()
        button = nil
    end

    -- for now only show this button to admins
    if player.admin then
        if not button then
            button = anchorpoint.add{
                type = "sprite-button",
                name = "clusterio-trainteleport",
                sprite = "utility/show_train_station_names_in_map_view",
                style = mod_gui.button_style
            }
        end
    end




    button = anchorpoint["clusterio-serverconnect"]

    if button then
        button.destroy()
        button = nil
    end

    if not button then
        button = anchorpoint.add{
            type = "sprite-button",
            name = "clusterio-serverconnect",
            sprite = "utility/surface_editor_icon",
            style = mod_gui.button_style
        }
    end
end

script.on_event(defines.events.on_player_joined_game, checkbutton)
script.on_event(defines.events.on_player_promoted, checkbutton)
script.on_event(defines.events.on_player_demoted, checkbutton)


script.on_event(defines.events.on_player_removed, function (event)
    local player_index = event.player_index

    if global.custom_locomotive_gui and global.custom_locomotive_gui[player_index] then
        local state = global.custom_locomotive_gui[player_index]
        global.custom_locomotive_gui[player_index] = nil
        gui_destroy(state)
    end
end)

script.on_event(defines.events.on_player_left_game, function (event)
    local player_index = event.player_index

    if global.custom_locomotive_gui and global.custom_locomotive_gui[player_index] then
        local state = global.custom_locomotive_gui[player_index]
        global.custom_locomotive_gui[player_index] = nil
        gui_destroy(state)
    end
end)


local guiApi = setmetatable({
    -- nothing so far
},{
    __index = function(t, k)
    end,
    __newindex = function(t, k, v)
        -- do nothing, read-only table
    end,
    -- Don't let mods muck around
    __metatable = false,
})


-- creates a new trainTeleport zone
function CreateZone(name, topLeftX, topLeftY, width, height, zoneIndex, drawZoneBorders)

    if global.config == nil then global.config = {} end
    if global.config.zones == nil then global.config.zones = {} end

    local zoneConfig = {}
    zoneConfig.topleft = {}
    zoneConfig.bottomright = {}
    zoneConfig.name = name
    zoneConfig.surface = "nauvis"
    zoneConfig.topleft[1] = topLeftX
    zoneConfig.topleft[2] = topLeftY
    zoneConfig.bottomright[1] = topLeftX + width
    zoneConfig.bottomright[2] = topLeftY + height

    local allAffectedStops = {}
    if width * height > 0 then
        local newStops = game.surfaces[1].find_entities_filtered{area={left_top = {zoneConfig.topleft[1], zoneConfig.topleft[2]}, right_bottom = {zoneConfig.bottomright[1], zoneConfig.bottomright[2]}}, type = "train-stop"};
        for _, trainstop in ipairs(newStops) do
            allAffectedStops[trainstop.unit_number] = trainstop
        end
    end

    if(zoneIndex == nil or zoneIndex <= 0 or zoneIndex > #global.config.zones) then
        zoneIndex = #global.config.zones + 1
    else
        zoneConfig.restrictions = global.config.zones and global.config.zones[zoneIndex] and global.config.zones[zoneIndex].restrictions or nil
    end


    global.config.zones[zoneIndex] = zoneConfig

    if(drawZoneBorders) then
        trainStopTrackingApi.drawZoneBorders(zoneIndex)
    end

    local package = {
        event = "savezone",
        worldId = global.worldID,
        zoneId = zoneIndex,
        zone = zoneConfig
    }

    local encodedPackage = game.table_to_json(package)

    log("Creating zone: ".. encodedPackage)
    game.write_file("zoneApi.log", "Creating zone: ".. encodedPackage .. "\n", true)

    -- send to master
    game.write_file(fileName, encodedPackage .. "\n", true, 0)

    return zoneConfig
end

-- e.g. CreateZoneRestriction('FromZoneOnLocalServer','TargetServer','TargetZone')
function CreateZoneRestriction(zoneIndex, toZoneServerName, toZoneName)
    local fromZone = global.config.zones and global.config.zones[zoneIndex] or nil
    if not fromZone then
        return
    end
    if fromZone.restrictions == nil then fromZone.restrictions = {} end
    -- add this restriction to the currently selected zone
    table.insert(fromZone.restrictions, {
        server = toZoneServerName,
        zone = toZoneName
    })
    local package = {
        event = "savezone",
        worldId = global.worldID,
        zoneId = zoneIndex,
        zone = fromZone
    }
    -- send to master
    game.write_file(fileName, game.table_to_json(package) .. "\n", true, 0)
end

return guiApi