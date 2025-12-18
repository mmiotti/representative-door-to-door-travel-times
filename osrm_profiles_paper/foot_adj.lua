-- Foot profile

api_version = 2

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
find_access_tag = require("lib/access").find_access_tag

function setup()
  local raster_path_impedance = "/data/impedance_walk_none.asc"
  local raster_path_elev = "/data/elev_raster_dhm25.asc"
  local walking_speed = 5
  return {
    properties = {
      force_split_edges             = true, -- UMA (added): important for segment adjustments (process_segment), which don't work properly otherwise, especially for elev gain/loss
      weight_name                   = 'duration',
      max_speed_for_map_matching    = 40/3.6, -- kmph -> m/s
      call_tagless_node_function    = false,
      traffic_signal_penalty        = 8, -- heuristic, not informed by model (note: right turns should often not incur penalty)
      u_turn_penalty                = 2,
      continue_straight_at_waypoint = false,
      use_turn_restrictions         = false,
      uma_base_speed_multiplier     = 1.12,
      uma_impedance_multiplier      = 1.0,  -- use 0.0 to turn off impedance map
      uma_elev_penalty_gain         = 2.41,
      uma_elev_penalty_loss         = 0.06,
    },

	raster_source_elev = raster:load(
      raster_path_elev,
      5.83477,     -- lon_min
      10.97745,    -- lon_max
      45.76566,    -- lat_min
      47.85720,    -- lat_max
      9121,  -- nrows
      15401  -- ncols
    ),

    -- These are taken from the file that generates the raster maps (create_raster_maps.py)
  	raster_source_impedance = raster:load(
      raster_path_impedance,
      5.95590,   -- lon_min
      10.49206,  -- lon_max
      45.81798,  -- lat_min
      47.80845,  -- lat_max
      4413,      -- nrows
      6969       -- ncols
    ),

    default_mode            = mode.walking,
    default_speed           = walking_speed,
    oneway_handling         = 'specific',     -- respect 'oneway:foot' but not 'oneway'

    barrier_blacklist = Set {
      'yes',
      'wall',
      'fence'
    },

    access_tag_whitelist = Set {
      'yes',
      'foot',
      'permissive',
      'designated'
    },

    access_tag_blacklist = Set {
      'no',
      'agricultural',
      'forestry',
      'private',
      'delivery',
    },

    restricted_access_tag_list = Set { },

    restricted_highway_whitelist = Set { },

    construction_whitelist = Set {},

    access_tags_hierarchy = Sequence {
      'foot',
      'access'
    },

    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set { },

    restrictions = Sequence {
      'foot'
    },

    -- list of suffixes to suppress in name change instructions
    suffix_list = Set {
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'North', 'South', 'West', 'East'
    },

    avoid = Set {
      'impassable',
      'proposed'
    },

    speeds = Sequence {
      highway = {
        primary         = walking_speed,
        primary_link    = walking_speed,
        secondary       = walking_speed,
        secondary_link  = walking_speed,
        tertiary        = walking_speed,
        tertiary_link   = walking_speed,
        unclassified    = walking_speed,
        residential     = walking_speed,
        road            = walking_speed,
        living_street   = walking_speed,
        service         = walking_speed,
        track           = walking_speed,
        path            = walking_speed,
        steps           = walking_speed,
        pedestrian      = walking_speed,
        platform        = walking_speed,
        footway         = walking_speed,
        pier            = walking_speed,
      },

      railway = {
        platform        = walking_speed
      },

      amenity = {
        parking         = walking_speed,
        parking_entrance= walking_speed
      },

      man_made = {
        pier            = walking_speed
      },

      leisure = {
        track           = walking_speed
      }
    },

    route_speeds = {
      ferry = 5
    },

    bridge_speeds = {
    },

    surface_speeds = {
      fine_gravel =   walking_speed*0.75,
      gravel =        walking_speed*0.75,
      pebblestone =   walking_speed*0.75,
      mud =           walking_speed*0.5,
      sand =          walking_speed*0.5
    },

    tracktype_speeds = {
    },

    smoothness_speeds = {
    }
  }
end

function process_segment(profile, segment)

  local elevPenaltyGain = profile.properties.uma_elev_penalty_gain
  local elevPenaltyLoss = profile.properties.uma_elev_penalty_loss
  local sourceElev = raster:interpolate(profile.raster_source_elev, segment.source.lon, segment.source.lat)
  local targetElev = raster:interpolate(profile.raster_source_elev, segment.target.lon, segment.target.lat)

  local sourceImpedance = raster:interpolate(profile.raster_source_impedance, segment.source.lon, segment.source.lat)
  local targetImpedance = raster:interpolate(profile.raster_source_impedance, segment.target.lon, segment.target.lat)

  local invalid = sourceImpedance.invalid_data()
  local invalidElev = sourceElev.invalid_data()
  local scaled_weight = segment.weight
  local scaled_duration = segment.duration
  local baseSpeedMultiplier = profile.properties.uma_base_speed_multiplier
  local impedanceMultiplier = profile.properties.uma_impedance_multiplier
  local segmentImpedance = 0
  local elevationPenalty = 0

  if sourceImpedance.datum ~= invalid and targetImpedance.datum ~= invalid and segment.distance > 0 then
    segmentImpedance = (sourceImpedance.datum + targetImpedance.datum) / 2000 -- divide by 1000 since data is stored that way (and by 2, for average)
  end

  if sourceElev.datum ~= invalidElev and targetElev.datum ~= invalidElev and sourceElev.datum > -10 and targetElev.datum > -10 then
    if targetElev.datum > sourceElev.datum then
      elevationPenalty = (targetElev.datum - sourceElev.datum) * elevPenaltyGain
    else
      elevationPenalty = (sourceElev.datum - targetElev.datum) * elevPenaltyLoss
    end
  end

  scaled_weight = segment.weight * (baseSpeedMultiplier + segmentImpedance * impedanceMultiplier) + elevationPenalty
  scaled_duration = segment.duration * (baseSpeedMultiplier + segmentImpedance * impedanceMultiplier) + elevationPenalty

--   io.write("evaluating segment: " .. sourceImpedance.datum .. " m to " .. targetImpedance.datum .. " m with distance " .. segment.distance .. "\n")
--   io.write("   impedance: " .. sourceImpedance.datum .. " / " .. targetImpedance.datum .. " > " .. segmentImpedance .. "\n")
--   io.write("   elevation penalty: " .. sourceElev.datum .. " / " .. targetElev.datum .. " > " .. elevationPenalty .. "\n")
--   io.write("   segment weight: " .. segment.weight .. " > " .. scaled_weight .. "\n")

  segment.weight = scaled_weight
  segment.duration = scaled_duration
end

function process_node(profile, node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access then
    if profile.access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier then
      --  make an exception for rising bollard barriers
      local bollard = node:get_value_by_key("bollard")
      local rising_bollard = bollard and "rising" == bollard

      if profile.barrier_blacklist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if "traffic_signals" == tag then
    -- Direction should only apply to vehicles
    result.traffic_lights = true
  end
end

-- main entry point for processsing a way
function process_way(profile, way, result)
  -- the intial filtering of ways based on presence of tags
  -- affects processing times significantly, because all ways
  -- have to be checked.
  -- to increase performance, prefetching and intial tag check
  -- is done in directly instead of via a handler.

  -- in general we should  try to abort as soon as
  -- possible if the way is not routable, to avoid doing
  -- unnecessary work. this implies we should check things that
  -- commonly forbids access early, and handle edge cases later.

  -- data table for storing intermediate values during processing
  local data = {
    -- prefetch tags
    highway = way:get_value_by_key('highway'),
    bridge = way:get_value_by_key('bridge'),
    route = way:get_value_by_key('route'),
    leisure = way:get_value_by_key('leisure'),
    man_made = way:get_value_by_key('man_made'),
    railway = way:get_value_by_key('railway'),
    platform = way:get_value_by_key('platform'),
    amenity = way:get_value_by_key('amenity'),
    public_transport = way:get_value_by_key('public_transport')
  }

  -- perform an quick initial check and abort if the way is
  -- obviously not routable. here we require at least one
  -- of the prefetched tags to be present, ie. the data table
  -- cannot be empty
  if next(data) == nil then     -- is the data table empty?
    return
  end

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,

    -- determine access status by checking our hierarchy of
    -- access tags, e.g: motorcar, motor_vehicle, vehicle
    WayHandlers.access,

    -- check whether forward/backward directons are routable
    WayHandlers.oneway,

    -- check whether forward/backward directons are routable
    WayHandlers.destinations,

    -- check whether we're using a special transport mode
    WayHandlers.ferries,
    WayHandlers.movables,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.speed,
    WayHandlers.surface,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.classification,

    -- handle various other flags
    WayHandlers.roundabouts,
    WayHandlers.startpoint,

    -- set name, ref and pronunciation
    WayHandlers.names,

    -- set weight properties of the way
    WayHandlers.weights
  }

  WayHandlers.run(profile, way, result, data, handlers)
end

function process_turn (profile, turn)
  turn.duration = 0.

  if turn.direction_modifier == direction_modifier.u_turn then
     turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
     turn.duration = profile.properties.traffic_signal_penalty
  end
  if profile.properties.weight_name == 'routability' then
      -- penalize turns from non-local access only segments onto local access only tags
      if not turn.source_restricted and turn.target_restricted then
          turn.weight = turn.weight + 3000
      end
  end
end

return {
  setup = setup,
  process_way = process_way,
  process_segment = process_segment, -- UMA: added
  process_node = process_node,
  process_turn = process_turn
}