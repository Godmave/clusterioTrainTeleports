utils = {}

--[[
    Direction is based on which direction a train stopped at
    the station would be travelling towards.
]]
local STATION_DIRECTIONS = {
    east = 2,  --[[ +X ]]
    west = 6,  --[[ -X ]]
    south = 4, --[[ +Y ]]
    north = 0, --[[ -Y ]]
}

local RAIL_CONNECTION_DIRECTIONS = {
    left     = defines.rail_connection_direction.left,
    straight = defines.rail_connection_direction.straight,
    right    = defines.rail_connection_direction.right,
}
local SIGNAL_DATA = {
    ['straight-rail'] = {
        --[[ Straight ]]
        [0] = {
            [defines.rail_direction.front] = {
                direction = 0,
                incoming = { x = -1.5, y = -0.5 },
                outgoing = { x =  1.5, y = -0.5 },
            },
            [defines.rail_direction.back] = {
                direction = 4,
                incoming = { x =  1.5, y =  0.5 },
                outgoing = { x = -1.5, y =  0.5 },
            },
        },
        [2] = {
            [defines.rail_direction.front] = {
                direction = 2,
                incoming = { x =  0.5, y = -1.5 },
                outgoing = { x =  0.5, y =  1.5 },
            },
            [defines.rail_direction.back] = {
                direction = 6,
                incoming = { x = -0.5, y =  1.5 },
                outgoing = { x = -0.5, y = -1.5 },
            },
        },
        --[[ Diagonals ]]
        [1] = {
            [defines.rail_direction.back] = {
                direction = 3,
                incoming = { x =  1.5, y = -1.5 },
                outgoing = { x = -0.5, y =  0.5 },
            },
        },
        [3] = {
            [defines.rail_direction.back] = {
                direction = 5,
                incoming = { x =  1.5, y = -1.5 },
                outgoing = { x = -0.5, y = -0.5 },
            },
        },
        [5] = {
            [defines.rail_direction.back] = {
                direction = 7,
                incoming = { x = -1.5, y =  1.5 },
                outgoing = { x =  0.5, y = -0.5 },
            },
        },
        [7] = {
            [defines.rail_direction.back] = {
                direction = 1,
                incoming = { x = -1.5, y = -1.5 },
                outgoing = { x =  0.5, y =  0.5 },
            },
        },
    },
    ['curved-rail'] = {
        [0] = {
            [defines.rail_direction.front] = {
                direction = 4,
                incoming = { x =  2.5, y =  3.5 },
                outgoing = { x = -0.5, y =  3.5 },
            },
            [defines.rail_direction.back] = {
                direction = 7,
                incoming = { x = -2.5, y = -1.5 },
                outgoing = { x = -0.5, y = -3.5 },
            },
        },
        [1] = {
            [defines.rail_direction.front] = {
                direction = 4,
                incoming = { x =  0.5, y =  3.5 },
                outgoing = { x = -2.5, y =  3.5 },
            },
            [defines.rail_direction.back] = {
                direction = 1,
                incoming = { x =  0.5, y = -3.5 },
                outgoing = { x =  2.5, y = -1.5 },
            },
        },
        [2] = {
            [defines.rail_direction.front] = {
                direction = 6,
                incoming = { x = -3.5, y =  2.5 },
                outgoing = { x = -3.5, y = -0.5 },
            },
            [defines.rail_direction.back] = {
                direction = 1,
                incoming = { x =  1.5, y = -2.5 },
                outgoing = { x =  3.5, y = -0.5 },
            },
        },
        [3] = {
            [defines.rail_direction.front] = {
                direction = 6,
                incoming = { x = -3.5, y =  0.5 },
                outgoing = { x = -3.5, y = -2.5 },
            },
            [defines.rail_direction.back] = {
                direction = 3,
                incoming = { x =  3.5, y =  0.5 },
                outgoing = { x =  1.5, y =  2.5 },
            },
        },
        [4] = {
            [defines.rail_direction.front] = {
                direction = 0,
                incoming = { x = -2.5, y = -3.5 },
                outgoing = { x =  0.5, y = -3.5 },
            },
            [defines.rail_direction.back] = {
                direction = 3,
                incoming = { x =  2.5, y =  1.5 },
                outgoing = { x =  0.5, y =  3.5 },
            },
        },
        [5] = {
            [defines.rail_direction.front] = {
                direction = 0,
                incoming = { x = -0.5, y = -3.5 },
                outgoing = { x =  2.5, y = -3.5 },
            },
            [defines.rail_direction.back] = {
                direction = 5,
                incoming = { x = -0.5, y =  3.5 },
                outgoing = { x = -2.5, y =  1.5 },
            },
        },
        [6] = {
            [defines.rail_direction.front] = {
                direction = 2,
                incoming = { x =  3.5, y = -2.5 },
                outgoing = { x =  3.5, y =  0.5 },
            },
            [defines.rail_direction.back] = {
                direction = 5,
                incoming = { x = -1.5, y =  2.5 },
                outgoing = { x = -3.5, y =  0.5 },
            },
        },
        [7] = {
            [defines.rail_direction.front] = {
                direction = 2,
                incoming = { x =  3.5, y = -0.5 },
                outgoing = { x =  3.5, y =  2.5 },
            },
            [defines.rail_direction.back] = {
                direction = 7,
                incoming = { x = -3.5, y = -0.5 },
                outgoing = { x = -1.5, y = -2.5 },
            },
        },
    },
}

--[[
    Checks whether a station's direction is vertical
]]
function utils.is_vertical(station_direction)
    return (station_direction % 4) == 0
end

--[[
    Reverses a defines.rail_direction.
]]
function utils.reverse_rail_direction(rail_direction)
    return rail_direction == defines.rail_direction.front
            and defines.rail_direction.back
            or defines.rail_direction.front
end

--[[
    Checks whether a query from rail into rail_direction and rail_connection_direction
    would result in a reversal of the rail_direction for continued queries.
]]
function utils.is_reversing_rail_direction(rail, rail_direction, rail_connection_direction)
    if rail.type == 'straight-rail' then
        if rail.direction % 2 == 0 then --[[ Straight ]]
            return not (rail_direction == defines.rail_direction.back
                    or rail_connection_direction == defines.rail_connection_direction.straight)
        else --[[ Diagonal ]]
            return rail_direction ~= defines.rail_direction.front
                    or rail_connection_direction ~= defines.rail_connection_direction.left
        end
    else --[[ Curved ]]
        if rail_connection_direction ~= defines.rail_connection_direction.straight then
            return true
        elseif rail_direction == defines.rail_direction.front then
            return rail.direction < 4
        else
            return rail.direction % 2 == 0
        end
    end
end

function utils.find_station_track(station)
    assert(station ~= nil and station.type == 'train-stop', 'invalid type, station :: train-stop')
    local position = station.position
    local direction = station.direction

    local rail_position
    if utils.is_vertical(direction) then
        if direction == STATION_DIRECTIONS.south then
            rail_position = { 2, 0 }
        else
            rail_position = { -2, 0 }
        end
    else
        if direction == STATION_DIRECTIONS.east then
            rail_position = { 0, -2 }
        else
            rail_position = { 0, 2 }
        end
    end

    rail_position[1], rail_position[2] = rail_position[1] + position.x, rail_position[2] + position.y
    return station.surface.find_entities_filtered({
        position = rail_position,
        type = 'straight-rail',
        limit = 1,
    })[1]
end

do
    local sqrt_2, pi = 1.41421356237, math.pi

    local gauge, projection_constant = 0.546875, 0.7071067811865

    local straight_length = 2
    local diagonal_length = sqrt_2

    local curve_length
    do
        local a = sqrt_2 * gauge * projection_constant
        local b = a / 2
        local r = (3 - b) / (1 - math.sin(45 * pi / 180))
        local sy = r * math.sin(45 * pi / 180) + 1 + b
        local straight_part_length = 8 - sy
        local diagonal_part_length = gauge * projection_constant
        local turn_part_length = 2 * r * pi / 8
        curve_length = straight_part_length + diagonal_part_length + turn_part_length
    end
    utils.straight_length, utils.diagonal_length, utils.curve_length =
    straight_length, diagonal_length, curve_length

    local turns
    do
        local a = sqrt_2 * gauge * projection_constant
        local b = a / 2
        local r = (3 - b) / (1 - math.sin(45 * pi / 180))
        local tsx = r + 1
        local tsy = r * math.sin(45 * pi / 180) + 1 + b

        turns = {
            { sx = -tsx + 2, sy =  tsy - 4, starting_angle = 0 / 4 * pi, rotation_direction =  1, starting_x_shift =  1, starting_y_shift =  4 },
            { sx =  tsx - 2, sy =  tsy - 4, starting_angle = 4 / 4 * pi, rotation_direction = -1, starting_x_shift = -1, starting_y_shift =  4 },
            { sx = -tsy + 4, sy = -tsx + 2, starting_angle = 6 / 4 * pi, rotation_direction =  1, starting_x_shift = -4, starting_y_shift =  1 },
            { sx = -tsy + 4, sy =  tsx - 2, starting_angle = 2 / 4 * pi, rotation_direction = -1, starting_x_shift = -4, starting_y_shift = -1 },
            { sx =  tsx - 2, sy = -tsy + 4, starting_angle = 4 / 4 * pi, rotation_direction =  1, starting_x_shift = -1, starting_y_shift = -4 },
            { sx = -tsx + 2, sy = -tsy + 4, starting_angle = 0 / 4 * pi, rotation_direction = -1, starting_x_shift =  1, starting_y_shift = -4 },
            { sx =  tsy - 4, sy =  tsx - 2, starting_angle = 2 / 4 * pi, rotation_direction =  1, starting_x_shift =  4, starting_y_shift = -1 },
            { sx =  tsy - 4, sy = -tsx + 2, starting_angle = 6 / 4 * pi, rotation_direction = -1, starting_x_shift =  4, starting_y_shift =  1 },
        }
    end

    local direction_multiplicators = {
        {  0       , -1        },
        {  0.707106, -0.707106 },
        {  1       ,  0        },
        {  0.707106,  0.707106 },
        {  0       ,  1        },
        { -0.707106,  0.707106 },
        { -1       ,  0        },
        { -0.707106, -0.707106 },
    }

    function utils.rail_length(rail)
        if rail.type == 'straight-rail' then
            if rail.direction % 2 == 0 then
                return straight_length
            end
            return diagonal_length
        end
        return curve_length
    end

    function utils.distance_along_straight(rail, distance)
        local position = rail.position
        local direction = rail.direction
        if direction == 0 then
            return position.x, position.y - 1 + distance
        end
        return position.x + 1 - distance, position.y
    end

    function utils.distance_along_diagonal(rail, distance)
        local direction = rail.direction
        local position = rail.position

        local direction_multiplicator = direction_multiplicators[direction]

        local position_x, position_y =
        position.x + direction_multiplicator[1],
        position.y + direction_multiplicator[2]

        direction_multiplicator = direction_multiplicators[(direction + 2) % 8 + 1]
        return position_x + distance * direction_multiplicator[1],
        position_y + distance * direction_multiplicator[2]
    end

    function utils.distance_along_curved(rail, distance)
        local position_x, position_y
        do
            local temp = rail.position
            position_x, position_y = temp.x, temp.y
        end

        local a = sqrt_2 * gauge * projection_constant
        local b = a / 2
        local r = (3 - b) / (1 - math.sin(45 * pi / 180))
        local sy = r * math.sin(45 * pi / 180) + 1 + b
        local straight_part_length = 8 - sy
        local turn_part_length = 2 * r * pi / 8
        local turn_specification = turns[rail.direction + 1]
        local result_x, result_y = position_x + turn_specification.starting_x_shift, position_y + turn_specification.starting_y_shift

        if distance < straight_part_length then
            local straight_direction = bit32.band(0xfffffffe, rail.direction)
            local direction_multiplicator = direction_multiplicators[straight_direction + 1]
            return result_x + distance * direction_multiplicator[1], result_y + distance * direction_multiplicator[2]
        end
        if distance < straight_part_length + turn_part_length then
            local angle_traveled = (distance - straight_part_length) / turn_part_length * (1 / 8) * 2 * pi
            local current_sx = position_x + turn_specification.sx
            local current_sy = position_y + turn_specification.sy
            local current_angle = turn_specification.starting_angle + turn_specification.rotation_direction * angle_traveled
            return current_sx + math.cos(current_angle) * r,
            current_sy - math.sin(current_angle) * r
        end
        do
            local angle_traveled = (distance - straight_part_length) / turn_part_length * (1 / 8) * 2 * pi
            local current_sx = position_x + turn_specification.sx
            local current_sy = position_y + turn_specification.sy
            local current_angle = turn_specification.starting_angle + turn_specification.rotation_direction * angle_traveled
            return current_sx + math.cos(current_angle) * r,
            current_sy - math.sin(current_angle) * r
        end
    end

    function utils.distance_along_rail(rail, distance)
        if rail.type == 'straight-rail' then
            if rail.direction % 2 == 0 then
                return utils.distance_along_straight(rail, distance)
            end
            return utils.distance_along_diagonal(rail, distance)
        end
        return utils.distance_along_curved(rail, distance)
    end
end

--[[
    Traverses a rail section to get information about the train block.

    Returns: {
        incoming_signals :: LuaEntity[]
        outgoing_signals :: LuaEntity[]
        longest_path :: {
            x :: float
            y :: float
            orientation :: float
        }[]
        chunks :: { uint32 => true }
    }

    Incoming/outgoing:
        The direction parameter determines which signals are considered
        are directed towards the block, and which ones move away from it.
        Flipping the direction will swap these around.
        Junctions may cause incoming/outgoing signals.

    Longest path:
        The longest path is an array of positions at which wagons can be
        spawned. This will start spawning directly at the head of the rail
        that's been provided, and moves in the opposite of the specified
        direction. If there are junctions in the path, it'll take the longest
        branch.

    Chunk numbers:
        Chunk numbers are represented by a concatenation of 2 16-bit
        numbers, representing the x and y coordinate. Because the map
        size is limited to 2 000 000 tiles, or 62 500 chunks, there is
        no concern for overflow, and lookup is made easier. The integer
        chunk coordinates are transformed from signed to unsigned integers via:
        f(x) = 0x10000 - x
        This is an involutory function, and any number greater than 32767,
        was originally negative, and should be converted back.
    
    Limitations:
        - Block contains more than 1000 rail sections.
        - Block contains a loop.

        Either of these conditions will exit the function with an error.
        
    Performance:
        Probably not great ;).
    
    Known issues:
        It's possible for curved rails to be in multiple chunks at one time,
        Currently this is not accounted for, and it is unlikely to be required
        for the caching to work efficiently.

        There is no check for signals on the rail section passed into the function.
        #todo Add this check to fix this bug.
]]
function utils.get_train_block_data(rail, rail_direction)
    assert(rail ~= nil and (rail.type == 'straight-rail' or rail.type == 'curved-rail'), 'expected rail')
    assert(rail_direction == defines.rail_direction.front or rail_direction == defines.rail_direction.back, 'expected defines.rail_direction')

    local surface = rail.surface

    local chunks = {}
    local incoming_signals = {}
    local outgoing_signals = {}

    local visited_count = 0
    local visited_rails = { [rail.unit_number] = true }
    local initial_rail_length = utils.rail_length(rail)
    local paths = {
        {
            backwards = true,
            tail_direction = utils.reverse_rail_direction(rail_direction),
            length = initial_rail_length,
            segments = { rail },
            is_segment_reversed = { rail_direction ~= defines.rail_direction.front },
        },
        {
            backwards = false,
            tail_direction = rail_direction,
            length = initial_rail_length,
            segments = { rail },
            is_segment_reversed = { rail_direction == defines.rail_direction.front },
        }
    }
    local path_index = 1

    while path_index <= #paths do
        local active_path = paths[path_index]
        local active_rail_direction = active_path.tail_direction
        local rail = active_path.segments[#active_path.segments]

        local connections = {}
        for _, rail_connection_direction in pairs(RAIL_CONNECTION_DIRECTIONS) do
            local connected = rail.get_connected_rail({
                rail_direction = active_rail_direction,
                rail_connection_direction = rail_connection_direction
            })
            if connected then
                connections[#connections + 1] = connected
                connections[#connections + 1] = utils.is_reversing_rail_direction(rail, active_rail_direction, rail_connection_direction)
            end
        end

        for i = 1, #connections, 2 do
            --[[
                It's important to clone the part for all but the last connections,
                otherwise clones that would be made would include the added path
                nodes.
            --]]
            local path
            local did_create_path = i ~= #connections - 1
            if did_create_path then
                path = table.deepcopy(active_path)
                paths[#paths + 1] = path
            else
                path = active_path
            end
            local is_reversing_rail_direction = connections[i + 1]
            if is_reversing_rail_direction then
                path.tail_direction = utils.reverse_rail_direction(path.tail_direction)
            end

            visited_count = visited_count + 1
            if visited_count > 1000 then
                error('block too large')
            end
            local connection = connections[i]
            local connection_position = connection.position
            local chunk_x = math.floor(connection_position.x / 32)
            local chunk_y = math.floor(connection_position.y / 32)
            if chunk_x < 0 then
                chunk_x = 0x10000 - chunk_x
            end
            if chunk_y < 0 then
                chunk_Y = 0x10000 - chunk_y
            end
            local chunk_nr = bit32.bor(chunk_x, bit32.lshift(chunk_y, 16))
            print(connection_position.x, connection_position.y, chunk_x, chunk_y, chunk_nr)
            chunks[chunk_nr] = true

            local signals = SIGNAL_DATA[connection.type][connection.direction]
            local signal_position = { x = 0, y = 0 }

            local signals_before = signals[utils.reverse_rail_direction(path.tail_direction)]
            local signals_after = signals[path.tail_direction]

            local incoming_signal, outgoing_signal
            if signals_before then
                signal_position.x = connection_position.x + signals_before.incoming.x
                signal_position.y = connection_position.y + signals_before.incoming.y
                incoming_signal = surface.find_entity('rail-signal', signal_position)
                        or surface.find_entity('rail-chain-signal', signal_position)
                if not incoming_signal or incoming_signal.direction ~= signals_before.direction then
                    incoming_signal = nil
                end
                signal_position.x = connection_position.x + signals_before.outgoing.x
                signal_position.y = connection_position.y + signals_before.outgoing.y
                outgoing_signal = surface.find_entity('rail-signal', signal_position)
                        or surface.find_entity('rail-chain-signal', signal_position)
                if not outgoing_signal or outgoing_signal.direction ~= (signals_before.direction + 4) % 8 then
                    outgoing_signal = nil
                end
            end
            if incoming_signal == nil and outgoing_signal == nil then
                local unit_number = connection.unit_number
                if visited_rails[unit_number] then
                    error('block has loop')
                end
                visited_rails[unit_number] = true

                path.segments[#path.segments + 1] = connection
                path.is_segment_reversed[#path.is_segment_reversed + 1] = is_reversing_rail_direction
                path.length = path.length + utils.rail_length(connection)

                if signals_after then
                    signal_position.x = connection_position.x + signals_after.incoming.x
                    signal_position.y = connection_position.y + signals_after.incoming.y
                    incoming_signal = surface.find_entity('rail-signal', signal_position)
                            or surface.find_entity('rail-chain-signal', signal_position)
                    if not incoming_signal or incoming_signal.direction ~= signals_after.direction then
                        incoming_signal = nil
                    end
                    signal_position.x = connection_position.x + signals_after.outgoing.x
                    signal_position.y = connection_position.y + signals_after.outgoing.y
                    outgoing_signal = surface.find_entity('rail-signal', signal_position)
                            or surface.find_entity('rail-chain-signal', signal_position)
                    if not outgoing_signal or outgoing_signal.direction ~= (signals_after.direction + 4) % 8 then
                        outgoing_signal = nil
                    end
                end

                if incoming_signal ~= nil then
                    incoming_signals[#incoming_signals + 1] = incoming_signal
                end
                if outgoing_signal ~= nil then
                    outgoing_signals[#outgoing_signals + 1] = outgoing_signal
                end

                if incoming_signal ~= nil or outgoing_signal ~= nil then
                    path_index = path_index + 1
                end
            else
                if incoming_signal ~= nil then
                    incoming_signals[#incoming_signals + 1] = incoming_signal
                end
                if outgoing_signal ~= nil then
                    outgoing_signals[#outgoing_signals + 1] = outgoing_signal
                end

                if did_create_path then
                    paths[#paths] = nil
                end

                path_index = path_index + 1
            end
        end

        if #connections == 0 then
            path_index = path_index + 1
        end
    end

    --[[ Select the longest path to pick carriage spawn points along ]]
    local longest_path_idx = 1
    for i = 2, #paths do
        if paths[i].backwards and paths[longest_path_idx].length < paths[i].length then
            longest_path_idx = i
        end
    end

    --[[ Iterate the longest path to find spawn points ]]
    local longest_path = {}
    do
        local path = paths[longest_path_idx]
        local remaining_length = path.length
        local rail_index = 1
        local rail = path.segments[rail_index]
        local rail_length = utils.rail_length(rail)
        local distance_in_rail = 0
        local is_reversed_direction = path.is_segment_reversed[1]
        local function advance(distance)
            --[[ Move to next rail segments ]]
            remaining_length = remaining_length + distance_in_rail
            distance = distance + distance_in_rail
            while distance > rail_length do
                rail_index = rail_index + 1
                --[[ Trying to advance beyond the path length ]]
                if rail_index > #path.segments then
                    remaining_length = 0
                    return utils.distance_along_rail(rail, is_reversed_direction and rail_length or 0)
                end
                remaining_length = remaining_length - rail_length
                distance = distance - rail_length
                rail = path.segments[rail_index]
                rail_length = utils.rail_length(rail)
                if path.is_segment_reversed[rail_index] then
                    is_reversed_direction = not is_reversed_direction
                end
            end

            remaining_length = remaining_length - distance
            distance_in_rail = distance
            if is_reversed_direction then
                return utils.distance_along_rail(rail, rail_length - distance_in_rail)
            end
            return utils.distance_along_rail(rail, distance_in_rail)
        end

        local extra_distance = 0
        while remaining_length > 3.99999999 + extra_distance do
            local start_x, start_y = advance(extra_distance)
            local position_x, position_y = advance(2)
            local end_x, end_y = advance(2)
            extra_distance = 3

            longest_path[#longest_path + 1] = {
                x = position_x,
                y = position_y,
                orientation = math.atan2(end_x - start_x, start_y - end_y) / math.pi * 0.5 + 0.5,
            }
        end
    end

    return {
        incoming_signals = incoming_signals,
        outgoing_signals = outgoing_signals,
        longest_path = longest_path,
        chunks = chunks,
    }
end