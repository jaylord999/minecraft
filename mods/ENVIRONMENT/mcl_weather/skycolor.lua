-- Constants
mcl_weather = mcl_weather or {}
mcl_weather.skycolor = mcl_weather.skycolor or {}

local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)
local S = minetest.get_translator(modname)

local NIGHT_VISION_RATIO = 0.45
local MINIMUM_DAY_NIGHT_RATIO = 0.0
local DEBUG = false

-- Settings
local minimum_update_interval = 250e3
vl_tuning.setting("minimum_sky_update_interval", "number", {
	default = 0.25,
	set = function(val) minimum_update_interval = val * 1e6 end,
	get = function() return minimum_update_interval * 1e-6 end,
})

-- Module state
local mods_loaded = false

-- Daylight cycle handling
local fixed_time = 0.5
local fixed_time_setting = vl_tuning.setting("fixed_daylight_time", "number", {
	description = S("Time of day to use when gamerule:doDaylightCycle == false"),
	default = 0.5,
	set = function(val) fixed_time = val end,
	get = function() return fixed_time end,
})
local gamerule_doDaylightCycle = true
vl_tuning.setting("gamerule:doDaylightCycle", "bool",{
	description = S("Whether the daylight cycle and moon phases progress"),
	default = true,
	set = function(val) gamerule_doDaylightCycle = val end,
	get = function() return gamerule_doDaylightCycle end,
	on_change = function(self)
		if not self[1] then
			fixed_time_setting:set(minetest.get_timeofday())
		end
	end
})
local function daylightCycle()
	if not gamerule_doDaylightCycle and fixed_time then
		minetest.set_timeofday(fixed_time)
	end
	minetest.after(1, daylightCycle)
end
minetest.after(1, daylightCycle)

function mcl_weather.set_sky_box_clear(player, sky, fog)
	-- Make sure the player's head isn't in water before changing the skybox
	local node_head = mcl_playerinfo[player:get_player_name()].node_head
	if minetest.get_item_group(node_head, "water") ~= 0 then return nil end

	local sc = {
			day_sky = "#7BA4FF",
			day_horizon = "#C0D8FF",
			dawn_sky = "#7BA4FF",
			dawn_horizon = "#C0D8FF",
			night_sky = "#050B18",
			night_horizon = "#1C2D45",
			indoors = "#C0D8FF",
			fog_sun_tint = "#ff5f33",
			fog_moon_tint = nil,
			fog_tint_type = "custom"
		}
	if sky then
		sc.day_sky = sky
		sc.dawn_sky = sky
	end
	if fog then
		sc.day_horizon = fog
		sc.dawn_horizon = fog
	end
	player:set_sky({
		type = "regular",
		sky_color = sc,
		clouds = true,
	})
	player:set_sun({visible = true, sunrise_visible = true})
	player:set_moon({visible = true, scale = 1.6})
	player:set_stars({
		visible = true,
		count = 2200,
		star_color = "#ac8126",
		day_opacity = 0.05,
	})
	return sc
end

function mcl_weather.set_sky_color(player, def)
	-- Make sure the player's head isn't in water before changing the skybox
	local node_head = mcl_playerinfo[player:get_player_name()].node_head
	if minetest.get_item_group(node_head, "water") ~= 0 then return end

	player:set_sky({
		type = def.type,
		sky_color = def.sky_color,
		clouds = def.clouds,
	})
end

local skycolor = {
	-- Should be activated before do any effect.
	active = true,

	-- To skip update interval
	force_update = true,

	-- Update interval.
	update_interval = 3,

	-- Main sky colors: starts from midnight to midnight.
	-- Please do not set directly. Use add_layer instead.
	colors = {},

	-- min value which will be used in color gradient, usualy its first user given color in 'pure' color.
	min_val = 0,

	-- number of colors while constructing gradient of user given colors
	max_val = 1000,

	NIGHT_VISION_RATIO = NIGHT_VISION_RATIO,

	-- Table for tracking layer order
	layer_names = {},

	utils = {},
}
mcl_weather.skycolor = skycolor
local skycolor_utils = skycolor.utils

local night_fx = {}

local function clear_night_fx(player)
	local name = player:get_player_name()
	local fx = night_fx[name]
	if not fx then return end
	for _, id in ipairs(fx) do
		if id then
			minetest.delete_particlespawner(id)
		end
	end
	night_fx[name] = nil
end

local function spawn_aurora(player)
	local name = player:get_player_name()
	if night_fx[name] then return end
	local ids = {}
	local colours = {"#25ff8a", "#2fe0c0", "#8a4dff", "#ff4fd0"}
	for i, col in ipairs(colours) do
		local x0 = -170 + (i - 1) * 85
		ids[#ids + 1] = minetest.add_particlespawner({
			amount = 30,
			time = 0,
			attached = player,
			playername = name,
			minpos = {x = x0, y = 80, z = 90},
			maxpos = {x = x0 + 100, y = 130, z = 170},
			minvel = {x = 1.2, y = 0.2, z = 0},
			maxvel = {x = 2.8, y = 1.2, z = 0},
			minacc = {x = 0, y = 0, z = 0},
			maxacc = {x = 0, y = 0, z = 0},
			minexptime = 8,
			maxexptime = 16,
			minsize = 28,
			maxsize = 86,
			collisiondetection = false,
			glow = 14,
			texture = "blank.png^[colorize:" .. col .. ":160",
		})
	end
	night_fx[name] = ids
end

local starburst_timers = {}

local function spawn_night_shooting_star(player)
	local name = player:get_player_name()
	local now = minetest.get_us_time()
	local last = starburst_timers[name] or 0
	if now - last < 20e6 then
		return
	end
	starburst_timers[name] = now

	local pos = player:get_pos()
	local spawn_pos = vector.add(pos, {
		x = math.random(-12, 12),
		y = math.random(8, 18),
		z = math.random(-12, 12),
	})
	local dir = {
		x = math.random(-14, 14) / 10,
		y = -0.9,
		z = math.random(-14, 14) / 10,
	}
	minetest.add_particle({
		pos = spawn_pos,
		velocity = dir,
		acceleration = vector.zero(),
		expirationtime = 1.5,
		size = 0.9,
		collisiondetection = false,
		vertical = false,
		texture = "mcl_particles_bonemeal.png^[colorize:#dfeeff:180",
		glow = 8,
	})
end

minetest.register_globalstep(function(dtime)
	local time = minetest.get_timeofday()
	local night = time < 0.21 or time > 0.79
	for _, player in ipairs(minetest.get_connected_players()) do
		if night then
			spawn_aurora(player)
			if math.random() < 0.005 then
				spawn_night_shooting_star(player)
			end
		else
			clear_night_fx(player)
		end
	end
end)

-- Add layer to colors table
function skycolor.add_layer(layer_name, layer_color, instant_update)
	skycolor.colors[layer_name] = layer_color
	table.insert(skycolor.layer_names, layer_name)
	skycolor.force_update = true
end

function skycolor.current_layer_name()
	return skycolor.layer_names[#skycolor.layer_names]
end

-- Retrieve layer from colors table
function skycolor.retrieve_layer()
	local last_layer = skycolor.current_layer_name()
	return skycolor.colors[last_layer]
end

-- Remove layer from colors table
function skycolor.remove_layer(layer_name)
	for k, name in pairs(skycolor.layer_names) do
		if name == layer_name then
			table.remove(skycolor.layer_names, k)
			skycolor.force_update = true
			return
		end
	end
end

-- Wrapper for updating day/night ratio that respects night vision
function skycolor.override_day_night_ratio(player, ratio)
	player._skycolor_day_night_ratio = ratio
	skycolor.update_player_sky_color(player)
	player._skycolor_day_night_ratio = nil
end

local skycolor_filters = {}
skycolor.filters = skycolor_filters
dofile(modpath.."/skycolor/water.lua")
dofile(modpath.."/skycolor/dimensions.lua")
dofile(modpath.."/skycolor/effects.lua")

local function get_skycolor_info(player)
	local player_name = player:get_player_name()

	local info = mcl_playerinfo[player_name] or {}

	local skycolor_data = info.skycolor
	if not skycolor_data then
		skycolor_data = {}
		info.skycolor = skycolor_data
	end

	return skycolor_data
end

local function apply_player_lighting(player, cave_darkness)
	if not player.set_lighting then return end
	cave_darkness = cave_darkness or 0
	local shadow_strength = 0.02 + cave_darkness * 0.04
	local exposure_factor = 1.0 - cave_darkness * 0.12

	player:set_lighting({
		shadows = { intensity = shadow_strength },
		volumetric_light = { strength = 0.02 },
		exposure = {
			luminance_min = 0.0,
			luminance_max = 1.0,
			exposure_correction = math.max(0.85, exposure_factor),
			speed_dark_bright = 600,
			speed_bright_dark = 600,
		},
		saturation = 1.0,
	})
end

local water_sky = skycolor.water_sky
function skycolor.update_player_sky_color(player)
	-- Don't update more than once every 250 milliseconds
	local skycolor_data = get_skycolor_info(player)
	local last_update = skycolor_data.last_update or 0
	local now_us = minetest.get_us_time()
	if (now_us - last_update) < minimum_update_interval then return end
	skycolor_data.last_update = now_us

	local sky_data = {
		day_night_ratio = player._skycolor_day_night_ratio
	}

	for i = 1,#skycolor_filters do
		skycolor_filters[i](player, sky_data)
	end

	-- Cave shading via player lighting is intentionally kept near-neutral.
	-- Luanti cannot apply a Minecraft-style directional cave light mask without a shader.
	-- A full cave-darkening effect makes the entire screen go night, which is not desired.
	apply_player_lighting(player, 0)
	assert(sky_data.sky)
	player:set_sky(sky_data.sky)

	if sky_data.sun   then player:set_sun(sky_data.sun) end
	if sky_data.moon  then player:set_moon(sky_data.moon) end
	if sky_data.stars then player:set_stars(sky_data.stars) end

	-- Cave shading should be local lighting, not a whole-screen night override.
	-- Weather/effects may still set a global day/night ratio explicitly.
	if sky_data.day_night_ratio ~= nil then
		player:override_day_night_ratio(sky_data.day_night_ratio)
	end
end

-- Update sky color. If players not specified update sky for all players.
function skycolor.update_sky_color(players)
	-- Override day/night ratio as well
	players = skycolor_utils.get_players(players)
	local update = skycolor.update_player_sky_color
	for _, player in ipairs(players) do
		update(player)
	end
end

-- Returns current layer color in {r, g, b} format
function skycolor.get_sky_layer_color(timeofday)
	if #skycolor.layer_names == 0 then
		return nil
	end

	-- min timeofday value 0; max timeofday value 1. So sky color gradient range will be between 0 and 1 * skycolor.max_val
	local rounded_time = math.floor(timeofday * skycolor.max_val)
	return skycolor_utils.convert_to_rgb(
		skycolor.min_val, skycolor.max_val,
		rounded_time, skycolor.retrieve_layer()
	)
end

function skycolor_utils.convert_to_rgb(minval, maxval, current_val, colors)
	-- Clamp current_val to valid range
	current_val = math.max(minval, current_val)
	current_val = math.min(maxval, current_val)

	-- Rescale current_val from a number between minval and maxval to a number between 1 and #colors
	local scaled_value = (current_val - minval) / (maxval - minval) * (#colors - 1) + 1.0

	-- Get the first color's values
	local index1 = math.floor(scaled_value)
	local color1 = colors[index1]
	local frac1 = 1.0 - (scaled_value - index1)

	-- Get the second color's values
	local index2 = math.min(index1 + 1, #colors) -- clamp to maximum color index (will occur if index1 == #colors)
	local frac2 = 1.0 - frac1
	local color2 = colors[index2]

	-- Interpolate between color1 and color2
	local res = {
		r = math.floor(frac1 * color1.r + frac2 * color2.r),
		g = math.floor(frac1 * color1.g + frac2 * color2.g),
		b = math.floor(frac1 * color1.b + frac2 * color2.b),
	}

	if DEBUG then
		minetest.log(dump({
			minval = minval,
			maxval = maxval,
			current_val = current_val,
			colors = colors,
			res = res,
			scaled_value = scaled_value,

			frac1 = frac1,
			index1 = index1,
			color1 = color1,

			frac2 = frac2,
			index2 = index2,
			color2 = color2,
		}))
	end

	return res
end

-- Simple getter. Either returns user given players list or get all connected players if none provided
function skycolor_utils.get_players(players)
	if players == nil or #players == 0 then
		if mods_loaded then
			players = minetest.get_connected_players()
		elseif players == nil then
			players = {}
		end
	end
	return players
end

-- Returns the sky color of the first player, which is done assuming that all players are in same color layout.
function skycolor_utils.get_current_bg_color()
	local players = skycolor_utils.get_players(nil)
	if players[1] then
		return players[1]:get_sky(true).sky_color
	end
	return nil
end

local timer = 0
minetest.register_globalstep(function(dtime)
	if skycolor.active ~= true or #minetest.get_connected_players() == 0 then
		return
	end

	if skycolor.force_update then
		skycolor.update_sky_color()
		skycolor.force_update = false
		return
	end

	-- regular updates based on iterval
	timer = timer + dtime;
	if timer >= skycolor.update_interval then
		skycolor.update_sky_color()
		timer = 0
	end
end)

local function initsky(player)
	apply_player_lighting(player)

	if (skycolor.active) then
		mcl_weather.skycolor.force_update = true
	end

	player:set_clouds(mcl_worlds:get_cloud_parameters() or {height=mcl_worlds.layer_to_y(127), speed={x=-2, z=0}, thickness=4, color="#FFF0FEF"})
end

minetest.register_on_joinplayer(initsky)
minetest.register_on_respawnplayer(initsky)

mcl_worlds.register_on_dimension_change(function(player)
	skycolor.update_sky_color({player})
end)

minetest.register_on_mods_loaded(function()
	mods_loaded = true
end)
