dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ElevatorManager.lua"  )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/RespawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )

SurvivalGame = class( nil )
SurvivalGame.enableLimitedInventory = true
SurvivalGame.enableRestrictions = true
SurvivalGame.enableFuelConsumption = true
SurvivalGame.enableAmmoConsumption = true
SurvivalGame.enableUpgradeCost = true

local SyncInterval = 400 -- 400 ticks | 10 seconds

isSurvival = false
g_characters = g_characters or {}
Trees = Trees or {}
Rocks = Rocks or {}
Rods = Rods or {}
Empty_Soils = Empty_Soils or {}
Growing_Soils = Growing_Soils or {}
Finish_Soils = Finish_Soils or {}					 

function SurvivalGame.server_onCreate( self )
	isSurvival = true
	print( "SurvivalGame.server_onCreate" )
	self.sv = {}
	self.sv.saved = self.storage:load()
	print( "Saved:", self.sv.saved )
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.data = self.data
		printf( "Seed: %.0f", self.sv.saved.data.seed )
		self.sv.saved.overworld = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/Overworld.lua", "Overworld", { dev = self.sv.saved.data.dev }, self.sv.saved.data.seed )
		self.storage:save( self.sv.saved )
	end
	self.data = nil

	print( self.sv.saved.data )
	if self.sv.saved.data and self.sv.saved.data.dev then
		g_godMode = true
		g_survivalDev = true
	end

	self:loadCraftingRecipes()

	g_elevatorManager = ElevatorManager()
	g_elevatorManager:sv_onCreate()

	g_respawnManager = RespawnManager()
	g_respawnManager:sv_onCreate( self.sv.saved.overworld )

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate( self.sv.saved.overworld )

	g_questManager = QuestManager()
	g_questManager:sv_onCreate( self )
	g_questManager:sv_activateQuest( quest_use_terminal )

	if g_survivalDev then
		g_questManager:sv_completeQuest( quest_pickup_logbook )
	end

	-- Game script managed global warehouse table
	self.warehouses = sm.storage.load( STORAGE_CHANNEL_WAREHOUSES )
	if self.warehouses then
		print( "Loaded warehouses:" )
		print( self.warehouses )
	else
		self.warehouses = {}
		self:sv_e_saveWarehouses()
	end
	g_warehouses = self.warehouses


	self.sv.time = sm.storage.load( STORAGE_CHANNEL_TIME )
	if self.sv.time then
		print( "Loaded timeData:" )
		print( self.sv.time )
	else
		self.sv.time = {}
		self.sv.time.timeOfDay = 6 / 24 -- 06:00
		self.sv.time.timeProgress = true
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
	end
	self:sv_updateClientData()

	self.sv.syncTimer = Timer()
	self.sv.syncTimer:start( 0 )
 end

function SurvivalGame.server_onRefresh( self )
	g_craftingRecipes = nil
	g_refineryRecipes = nil
	self:loadCraftingRecipes()
end

function SurvivalGame.client_onCreate( self )

	self.cl = {}
	self.cl.time = {}
	self.cl.time.timeOfDay = 0.0
	self.cl.time.timeProgress = true

	if sm.isHost and g_survivalDev then
		self:bindChatCommands()
	end

	if not sm.isHost then
		self:loadCraftingRecipes()
	end

	if g_respawnManager == nil then
		assert( not sm.isHost )
		g_respawnManager = RespawnManager()
	end
	g_respawnManager:cl_onCreate()

	if g_beaconManager == nil then
		assert( not sm.isHost )
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()

	if g_unitManager == nil then
		assert( not sm.isHost )
		g_unitManager = UnitManager()
	end
	g_unitManager:cl_onCreate()

	if g_questManager == nil then
		assert( not sm.isHost )
		g_questManager = QuestManager()
	end
	g_questManager:cl_onCreate()

	-- Music effect
	g_survivalMusic = sm.effect.createEffect( "SurvivalMusic" )
	assert(g_survivalMusic)

	-- Survival HUD
	g_survivalHud = sm.gui.createSurvivalHudGui()
	assert(g_survivalHud)
	
	self:bindChatCommands()
end

function SurvivalGame.bindChatCommands( self )
	sm.game.bindChatCommand( "/ammo", { { "int", "quantity", true } }, "cl_onChatCommand", "Give ammo (default 50)" )
	sm.game.bindChatCommand( "/spudgun", {}, "cl_onChatCommand", "Give the spudgun" )
	sm.game.bindChatCommand( "/gatling", {}, "cl_onChatCommand", "Give the potato gatling gun" )
	sm.game.bindChatCommand( "/shotgun", {}, "cl_onChatCommand", "Give the fries shotgun" )
	sm.game.bindChatCommand( "/sunshake", {}, "cl_onChatCommand", "Give 1 sunshake" )
	sm.game.bindChatCommand( "/baguette", {}, "cl_onChatCommand", "Give 1 revival baguette" )
	sm.game.bindChatCommand( "/keycard", {}, "cl_onChatCommand", "Give 1 keycard" )
	sm.game.bindChatCommand( "/powercore", {}, "cl_onChatCommand", "Give 1 powercore" )
	sm.game.bindChatCommand( "/components", { { "int", "quantity", true } }, "cl_onChatCommand", "Give <quantity> components (default 10)" )
	sm.game.bindChatCommand( "/glowsticks", { { "int", "quantity", true } }, "cl_onChatCommand", "Give <quantity> components (default 10)" )
	sm.game.bindChatCommand( "/tumble", { { "bool", "enable", true } }, "cl_onChatCommand", "Set tumble state" )
	sm.game.bindChatCommand( "/god", {}, "cl_onChatCommand", "Mechanic characters will take no damage" )
	sm.game.bindChatCommand( "/respawn", {}, "cl_onChatCommand", "Respawn at last bed (or at the crash site)" )
	sm.game.bindChatCommand( "/encrypt", {}, "cl_onChatCommand", "Restrict interactions in all warehouses" )
	sm.game.bindChatCommand( "/decrypt", {}, "cl_onChatCommand", "Unrestrict interactions in all warehouses" )
	sm.game.bindChatCommand( "/limited", {}, "cl_onChatCommand", "Use the limited inventory" )
	sm.game.bindChatCommand( "/unlimited", {}, "cl_onChatCommand", "Use the unlimited inventory" )
	sm.game.bindChatCommand( "/ambush", { { "number", "magnitude", true }, { "int", "wave", true } }, "cl_onChatCommand", "Starts a 'random' encounter" )
	sm.game.bindChatCommand( "/recreate", {}, "cl_onChatCommand", "Recreate world" )
	sm.game.bindChatCommand( "/timeofday", { { "number", "timeOfDay", true } }, "cl_onChatCommand", "Sets the time of the day as a fraction (0.5=mid day)" )
	sm.game.bindChatCommand( "/timeprogress", { { "bool", "enabled", true } }, "cl_onChatCommand", "Enables or disables time progress" )
	sm.game.bindChatCommand( "/day", {}, "cl_onChatCommand", "Disable time progression and set time to daytime" )
	sm.game.bindChatCommand( "/spawn", { { "string", "unitName", true } }, "cl_onChatCommand", "Spawn a unit: 'woc', 'tapebot', 'totebot', 'haybot'" )
	sm.game.bindChatCommand( "/harvestable", { { "string", "harvestableName", true } }, "cl_onChatCommand", "Create a harvestable: 'tree', 'stone'" )
	sm.game.bindChatCommand( "/cleardebug", {}, "cl_onChatCommand", "Clear debug draw objects" )
	sm.game.bindChatCommand( "/export", { { "string", "name", false } }, "cl_onChatCommand", "Exports blueprint $SURVIVAL_DATA/LocalBlueprints/<name>.blueprint" )
	sm.game.bindChatCommand( "/import", { { "string", "name", false } }, "cl_onChatCommand", "Imports blueprint $SURVIVAL_DATA/LocalBlueprints/<name>.blueprint" )
	sm.game.bindChatCommand( "/starterkit", {}, "cl_onChatCommand", "Spawn a starter kit" )
	sm.game.bindChatCommand( "/mechanicstartkit", {}, "cl_onChatCommand", "Spawn a starter kit for starting at mechanic station" )
	sm.game.bindChatCommand( "/pipekit", {}, "cl_onChatCommand", "Spawn a pipe kit" )
	sm.game.bindChatCommand( "/foodkit", {}, "cl_onChatCommand", "Spawn a food kit" )
	sm.game.bindChatCommand( "/seedkit", {}, "cl_onChatCommand", "Spawn a seed kit" )
	sm.game.bindChatCommand( "/die", {}, "cl_onChatCommand", "Kill the player" )
	sm.game.bindChatCommand( "/sethp", { { "number", "hp", false } }, "cl_onChatCommand", "Set player hp value" )
	sm.game.bindChatCommand( "/setwater", { { "number", "water", false } }, "cl_onChatCommand", "Set player water value" )
	sm.game.bindChatCommand( "/setfood", { { "number", "food", false } }, "cl_onChatCommand", "Set player food value" )
	sm.game.bindChatCommand( "/aggroall", {}, "cl_onChatCommand", "All hostile units will be made aware of the player's position" )
	sm.game.bindChatCommand( "/goto", { { "string", "name", false } }, "cl_onChatCommand", "Teleport to predefined position" )
	sm.game.bindChatCommand( "/raid", { { "int", "level", false }, { "int", "wave", true }, { "number", "hours", true } }, "cl_onChatCommand", "Start a level <level> raid at player position at wave <wave> in <delay> hours." )
	sm.game.bindChatCommand( "/stopraid", {}, "cl_onChatCommand", "Cancel all incoming raids" )
	sm.game.bindChatCommand( "/disableraids", { { "bool", "enabled", false } }, "cl_onChatCommand", "Disable raids if true" )
	sm.game.bindChatCommand( "/camera", {}, "cl_onChatCommand", "Spawn a SplineCamera tool" )
	sm.game.bindChatCommand( "/noaggro", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the player as a target" )
	sm.game.bindChatCommand( "/killall", {}, "cl_onChatCommand", "Kills all spawned units" )

	sm.game.bindChatCommand( "/printglobals", {}, "cl_onChatCommand", "Print all global lua variables" )
	sm.game.bindChatCommand( "/clearpathnodes", {}, "cl_onChatCommand", "Clear all path nodes in overworld" )
	sm.game.bindChatCommand( "/enablepathpotatoes", { { "bool", "enable", true } }, "cl_onChatCommand", "Creates path nodes at potato hits in overworld and links to previous node" )

	sm.game.bindChatCommand( "/activatequest",  { { "string", "uuid", true } }, "cl_onChatCommand", "Activate quest" )
	sm.game.bindChatCommand( "/completequest",  { { "string", "uuid", true } }, "cl_onChatCommand", "Complete quest" )

	
			-- 00Fant´s code Start
	sm.game.bindChatCommand( "/all", {}, "cl_onChatCommand", "cheatmode" )
	sm.game.bindChatCommand( "/delete", {}, "cl_onChatCommand", "delete" )
	sm.game.bindChatCommand( "/del", {}, "cl_onChatCommand", "delete" )
	sm.game.bindChatCommand( "/undo", {}, "cl_onChatCommand", "undo" )
	sm.game.bindChatCommand( "/fly", {}, "cl_onChatCommand", "fly" )
	sm.game.bindChatCommand( "/clearinv", {}, "cl_onChatCommand", "clear" )
	sm.game.bindChatCommand( "/chunk", {}, "cl_onChatCommand", "chunk" )
	sm.game.bindChatCommand( "/field", { { "int", "x", true }, { "int", "y", true } }, "cl_onChatCommand", "field" )
	sm.game.bindChatCommand( "/cleanup",  { { "int", "radius", true } }, "cl_onChatCommand", "cleanup" )
	sm.game.bindChatCommand( "/cam", { { "int", "toggle", true } }, "cl_onChatCommand", "Camera lock" )
	sm.game.bindChatCommand( "/camself", { { "int", "toggle", true } }, "cl_onChatCommand", "Camera lock" )
	sm.game.bindChatCommand( "/fill", { { "string", "type", true } }, "cl_onChatCommand", "Aim at a Container and use the Command on it. /fill or /fill ammo, gas, batterie, fuel, chemical, potato, water or the short variants like /fill am, ga, ch, wa, po" )


	-- 00Fant´s code End
		--RostigerSpielerStart
	sm.game.bindChatCommand( "/unlim", {}, "cl_onChatCommand", "unlimited" )
	sm.game.bindChatCommand( "/lim", {}, "cl_onChatCommand", "limited" )
		--RostigerSpieler End
end

function SurvivalGame.client_onClientDataUpdate( self, clientData )
	self.cl.time = clientData.time

	-- if not g_survivalDev and clientData.dev and not sm.isHost then
		-- self:bindChatCommands()
	-- end

	g_survivalDev = clientData.dev
end

function SurvivalGame.cl_n_questMsg( self, params )
	g_questManager:cl_handleMsg( params )
end

function SurvivalGame.loadCraftingRecipes( self )
	LoadCraftingRecipes({
		workbench = "$SURVIVAL_DATA/CraftingRecipes/workbench.json",
		dispenser = "$SURVIVAL_DATA/CraftingRecipes/dispenser.json",
		cookbot = "$SURVIVAL_DATA/CraftingRecipes/cookbot.json",
		craftbot = "$SURVIVAL_DATA/CraftingRecipes/craftbot.json",
		recyclebot = "$SURVIVAL_DATA/CraftingRecipes/recyclebot.json",
		modbot = "$SURVIVAL_DATA/CraftingRecipes/modbot.json",
		dressbot = "$SURVIVAL_DATA/CraftingRecipes/dressbot.json"
	})
end

function SurvivalGame.server_onFixedUpdate( self, timeStep )
	-- Update time
	local prevTime = self.sv.time.timeOfDay
	if self.sv.time.timeProgress then
		self.sv.time.timeOfDay = self.sv.time.timeOfDay + timeStep / DAYCYCLE_TIME
	end
	local newDay = self.sv.time.timeOfDay >= 1.0
	if newDay then
		self.sv.time.timeOfDay = math.fmod( self.sv.time.timeOfDay, 1 )
	end

	if self.sv.time.timeOfDay >= DAYCYCLE_DAWN and prevTime < DAYCYCLE_DAWN then
		g_unitManager:sv_initNewDay()
	end

	-- Ambush
	--if not g_survivalDev then
	--	for _,ambush in ipairs( AMBUSHES ) do
	--		if self.sv.time.timeOfDay >= ambush.time and ( prevTime < ambush.time or newDay ) then
	--			self:sv_ambush( { magnitude = ambush.magnitude, wave = ambush.wave } )
	--		end
	--	end
	--end

	-- Client and save sync
	self.sv.syncTimer:tick()
	if self.sv.syncTimer:done() then
		self.sv.syncTimer:start( SyncInterval )
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
		self:sv_updateClientData()
	end

	g_elevatorManager:sv_onFixedUpdate()
	g_unitManager:sv_onFixedUpdate()
	g_questManager:sv_onFixedUpdate()
	
	for k, character in pairs(g_characters) do
		if character:isSwimming() == false then
			character:setSwimming( self.fly )
		end
		if character:isDiving() == false then
			character:setDiving( self.fly )
		end
	end
end

function SurvivalGame.sv_updateClientData( self )
	self.network:setClientData( { time = self.sv.time, dev = g_survivalDev } )
end

function SurvivalGame.client_onUpdate( self, dt )
	-- Update time
	if self.cl.time.timeProgress then
		self.cl.time.timeOfDay = math.fmod( self.cl.time.timeOfDay + dt / DAYCYCLE_TIME, 1.0 )
	end
	sm.game.setTimeOfDay( self.cl.time.timeOfDay )

	-- Update lighting values
	local index = 1
	while index < #DAYCYCLE_LIGHTING_TIMES and self.cl.time.timeOfDay >= DAYCYCLE_LIGHTING_TIMES[index + 1] do
		index = index + 1
	end
	assert( index <= #DAYCYCLE_LIGHTING_TIMES )

	local light = 0.0
	if index < #DAYCYCLE_LIGHTING_TIMES then
		local p = ( self.cl.time.timeOfDay - DAYCYCLE_LIGHTING_TIMES[index] ) / ( DAYCYCLE_LIGHTING_TIMES[index + 1] - DAYCYCLE_LIGHTING_TIMES[index] )
		light = sm.util.lerp( DAYCYCLE_LIGHTING_VALUES[index], DAYCYCLE_LIGHTING_VALUES[index + 1], p )
	else
		light = DAYCYCLE_LIGHTING_VALUES[index]
	end
	sm.render.setOutdoorLighting( light )
	
	if self.camModeSelf then
		local DirectionVector = sm.localPlayer.getPlayer().character.worldPosition - sm.camera.getPosition()
		local Distance = sm.vec3.length( DirectionVector )
		local DirectionNormalized = sm.vec3.normalize( DirectionVector )
		if DirectionNormalized == sm.vec3.new( 0, 0, 0 ) then
			DirectionNormalized = sm.vec3.new( 1, 0, 0 )
		end
		sm.camera.setDirection( sm.vec3.lerp( sm.camera.getDirection(), DirectionNormalized, dt * 25 ) )
		if Distance > 5 then
			local NewPos =  sm.localPlayer.getPlayer().character.worldPosition - DirectionNormalized * 4
			NewPos.z = sm.localPlayer.getPlayer().character.worldPosition.z + 3
			self.camSelfPos = NewPos
		end
		if self.camSelfPos ~= nil then
			sm.camera.setPosition(  sm.vec3.lerp( sm.camera.getPosition(),  self.camSelfPos, ( dt * ( Distance / 25 ) * 3 ) / 2 ) )
		end
	end
end

function SurvivalGame.client_showMessage( self, params )
	sm.gui.chatMessage( params )
end

function SurvivalGame.cl_onChatCommand( self, params )
	if params[1] == "/ammo" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_plantables_potato, quantity = ( params[2] or 50 ) } )
	elseif params[1] == "/spudgun" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_spudgun, quantity = 1 } )
	elseif params[1] == "/gatling" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_gatling, quantity = 1 } )
	elseif params[1] == "/shotgun" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_shotgun, quantity = 1 } )
	elseif params[1] == "/sunshake" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_sunshake, quantity = 1 } )
	elseif params[1] == "/baguette" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_longsandwich, quantity = 1 } )
	elseif params[1] == "/keycard" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_survivalobject_keycard, quantity = 1 } )
	elseif params[1] == "/camera" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = sm.uuid.new( "5bbe87d3-d60a-48b5-9ca9-0086c80ebf7f" ), quantity = 1 } )
	elseif params[1] == "/powercore" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_survivalobject_powercore, quantity = 1 } )
	elseif params[1] == "/components" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_component, quantity = ( params[2] or 10 ) } )
	elseif params[1] == "/glowsticks" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_glowstick, quantity = ( params[2] or 10 ) } )
	elseif params[1] == "/god" then
		self.network:sendToServer( "sv_switchGodMode" )
	elseif params[1] == "/encrypt" then
		self.network:sendToServer( "sv_enableRestrictions", true )
	elseif params[1] == "/decrypt" then
		self.network:sendToServer( "sv_enableRestrictions", false )
	elseif params[1] == "/unlimited" or params[1] =="/unlim" then
		self.network:sendToServer( "sv_setLimitedInventory", false )
	elseif params[1] == "/limited" or params[1] =="/lim" then
		self.network:sendToServer( "sv_setLimitedInventory", true )
	elseif params[1] == "/ambush" then
		self.network:sendToServer( "sv_ambush", { magnitude = params[2] or 1, wave = params[3] } )
	elseif params[1] == "/recreate" then
		self.network:sendToServer( "sv_recreateWorld", sm.localPlayer.getPlayer() )
	elseif params[1] == "/timeofday" then
		self.network:sendToServer( "sv_setTimeOfDay", params[2] )
	elseif params[1] == "/timeprogress" then
		self.network:sendToServer( "sv_setTimeProgress", params[2] )
	elseif params[1] == "/day" then
		self.network:sendToServer( "sv_setTimeOfDay", 0.5 )
		self.network:sendToServer( "sv_setTimeProgress", false )
	elseif params[1] == "/die" then
		self.network:sendToServer( "sv_killPlayer", { player = sm.localPlayer.getPlayer() })
	elseif params[1] == "/spawn" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local spawnParams = {
				uuid = sm.uuid.new( "00000000-0000-0000-0000-000000000000" ),
				world = sm.localPlayer.getPlayer().character:getWorld(),
				position = rayCastResult.pointWorld,
				yaw = 0.0
			}
			if params[2] == "woc" then
				spawnParams.uuid = unit_woc
			elseif params[2] == "tapebot" or params[2] == "tb" then
				spawnParams.uuid = unit_tapebot
			elseif params[2] == "redtapebot" or params[2] == "rtb" then
				spawnParams.uuid = unit_tapebot_red
			elseif params[2] == "totebot" or params[2] == "green" or params[2] == "t" then
				spawnParams.uuid = unit_totebot_green
			elseif params[2] == "haybot" or params[2] == "h" then
				spawnParams.uuid = unit_haybot
			elseif params[2] == "worm" then
				spawnParams.uuid = unit_worm
			elseif params[2] == "farmbot" or params[2] == "f" then
				spawnParams.uuid = unit_farmbot
			elseif params[2] then
				spawnParams.uuid = sm.uuid.new( params[2] )
			end
			self.network:sendToServer( "sv_spawnUnit", spawnParams )
		end
	elseif params[1] == "/harvestable" then
		local character = sm.localPlayer.getPlayer().character
		if character then
			local harvestableUuid = sm.uuid.new( "00000000-0000-0000-0000-000000000000" )
			if params[2] == "tree" then
				harvestableUuid = sm.uuid.new( "c4ea19d3-2469-4059-9f13-3ddb4f7e0b79" )
			elseif params[2] == "stone" then
				harvestableUuid = sm.uuid.new( "0d3362ae-4cb3-42ae-8a08-d3f9ed79e274" )
			elseif params[2] == "soil" then
				harvestableUuid = hvs_soil
			elseif params[2] == "fencelong" then
				harvestableUuid = sm.uuid.new( "c0f19413-6d8e-4b20-819a-949553242259" )
			elseif params[2] == "fenceshort" then
				harvestableUuid = sm.uuid.new( "144b5e79-483e-4da6-86ab-c575d0fdcd11" )
			elseif params[2] == "fencecorner" then
				harvestableUuid = sm.uuid.new( "ead875db-59d0-45f5-861e-b3075e1f8434" )
			elseif params[2] == "beehive" then
				harvestableUuid = hvs_farmables_beehive
			elseif params[2] == "cotton" then
				harvestableUuid = hvs_farmables_cottonplant
			elseif params[2] then
				harvestableUuid = sm.uuid.new( params[2] )
			end
			local spawnParams = { world = character:getWorld(), uuid = harvestableUuid, position = character.worldPosition, quat = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) )  }
			self.network:sendToServer( "sv_spawnHarvestable", spawnParams )
		end
	elseif params[1] == "/cleardebug" then
		sm.debugDraw.clear()
	elseif params[1] == "/export" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid and rayCastResult.type == "body" then
			local importParams = {
				name = params[2],
				body = rayCastResult:getBody()
			}
			self.network:sendToServer( "sv_exportCreation", importParams )
		end
	elseif params[1] == "/import" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local importParams = {
				world = sm.localPlayer.getPlayer().character:getWorld(),
				name = params[2],
				position = rayCastResult.pointWorld
			}
			self.network:sendToServer( "sv_importCreation", importParams )
		end
	elseif params[1] == "/noaggro" then
		if type( params[2] ) == "boolean" then
			self.network:sendToServer( "sv_n_switchAggroMode", { aggroMode = not params[2] } )
		else
			self.network:sendToServer( "sv_n_switchAggroMode", { aggroMode = not sm.game.getEnableAggro() } )
		end
	
		-- 00Fant´s code Start
	elseif params[1] == "/all" then
		self.network:sendToServer( "sv_switchGodMode" )
		self.network:sendToServer( "sv_setLimitedInventory", false )
		self.network:sendToServer( "sv_setTimeOfDay", 0.5 )
		self.network:sendToServer( "sv_setTimeProgress", false )
		--self.network:sendToServer( "sv_enableRestrictions", false )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_spudgun, quantity = 1 } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_connect, quantity = 1 } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_weld, quantity = 1 } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_paint, quantity = 1 } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_shotgun, quantity = 1 } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_gatling, quantity = 1 } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_plantables_potato, quantity = ( 50 ) } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_gas, quantity = ( 20 ) } )
		--self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_battery, quantity = ( 20 ) } )
	elseif params[1] == "/delete" or params[1] == "/del" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid and rayCastResult.type == "body" then
			local importParams = {
				name = "undo",
				body = rayCastResult:getBody()
			}
			self.network:sendToServer( "sv_exportCreation", importParams )
			
			importParams = {
				name = params[2],
				body = rayCastResult:getBody()
			}
			self.network:sendToServer( "sv_delete", importParams )
		end
	elseif params[1] == "/fill" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local raycastShape = rayCastResult:getShape()
			if raycastShape ~= nil then
				self.network:sendToServer( "sv_fill", { shape = rayCastResult:getShape(), filltype = params[2] } )
			end
		end
	elseif params[1] == "/undo" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local importParams = {
				world = sm.localPlayer.getPlayer().character:getWorld(),
				name = "undo",
				position = rayCastResult.pointWorld
			}
			self.network:sendToServer( "sv_importCreation", importParams )
		end
	elseif params[1] == "/fly" then
		self.network:sendToServer( "sv_fly", { character = sm.localPlayer.getPlayer().character } )
		
	elseif params[1] == "/clearinv" then
		local isLimited = sm.game.getLimitedInventory()
		self.network:sendToServer( "sv_setLimitedInventory", true )
		self.network:sendToServer( "sv_clear", { player = sm.localPlayer.getPlayer() } )
		self.network:sendToServer( "sv_setLimitedInventory", isLimited )
		sm.gui.displayAlertText( "Open Close Inventory to Refresh your Hotbar", 2 )
	
	elseif params[1] == "/chunk" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		self.network:sendToServer( "sv_chunk", { sm.localPlayer.getPlayer(), sm.localPlayer.getPlayer().character:getWorld(), rayCastResult.pointWorld } )
		sm.gui.displayAlertText( "After a Map reload the Chunk Clone Loader are Gone!", 2 )
			
	elseif params[1] == "/field" then
		local SizeX = 0
		if params[2] ~= nil then
			SizeX = params[2]
		end
		local SizeY = 0
		if params[3] ~= nil then
			SizeY = params[3]
		else
			SizeY = SizeX
		end
		local halfSizeX = math.floor( SizeX / 2 )
		if halfSizeX < 0 then
			halfSizeX = 0
		end
		local halfSizeY = math.floor( SizeY / 2 )
		if halfSizeY < 0 then
			halfSizeY = 0
		end

		local RayPosDefault = sm.localPlayer.getPlayer().character.worldPosition + sm.vec3.new( 0, 0, 10 )
		local RayDirection = sm.vec3.new( 0, 0, -1 ) * 100
		local SoilData = {}
		for X = -halfSizeX, halfSizeX do 
			for Y = -halfSizeY, halfSizeY do 
				local RayCastPos = self:getLocalBlockGridPosition( RayPosDefault + ( sm.vec3.new( X, Y, 0 ) * 0.75 )  )
				local valid, result = sm.localPlayer.getRaycast( 100, RayCastPos, RayDirection )
				if result then
					if result.type == "terrainSurface" then
						if result.normalWorld.z >= 0.97236992 then
							table.insert( SoilData, result.pointWorld )
						end
					end
				end
			end
		end
		self.network:sendToServer( "PlaceSoilField", { player = sm.localPlayer.getPlayer(), data = SoilData } )
	elseif params[1] == "/cleanup" then
		if params[2] ~= nil then
			self.network:sendToServer( "cleanup", { player = sm.localPlayer.getPlayer(), radius = params[2] } )
		end
	elseif params[1] == "/cam" then
		if self.camMode == nil then
			self.camMode = false
		end
		if not self.camMode then
			local pos = sm.camera.getPosition( ) 
			local dir = sm.camera.getDirection( ) 
			sm.camera.setCameraState( sm.camera.state.cutsceneTP )
			sm.camera.setPosition( pos )
			sm.camera.setDirection( dir )
			self.camMode = true
			self.camModeSelf = false
		else
			sm.camera.setCameraState( sm.camera.state.default )
			self.camMode = false
			self.camModeSelf = false
		end
	elseif params[1] == "/camself" then
		if self.camModeSelf == nil then
			self.camModeSelf = false
		end
		if not self.camModeSelf then
			local dir = sm.camera.getDirection( ) 
			local pos = sm.camera.getPosition( )
			sm.camera.setCameraState( sm.camera.state.cutsceneTP )
			sm.camera.setPosition( pos )
			sm.camera.setDirection( dir )
			self.camModeSelf = true
			self.camMode = false
			self.camSelfPos = pos
		else
			sm.camera.setCameraState( sm.camera.state.default )
			self.camModeSelf = false
			self.camMode = false
		end
		-- 00Fant´s code End
	else
		self.network:sendToServer( "sv_onChatCommand", params )
	end
end

-- 00Fant´s code Start

function SurvivalGame.sv_fill( self, params )
	local filltype = "all"
	if params.filltype ~= nil then
		if params.filltype:lower():match( "ga" ) then
			filltype = "gas"
		end
		if params.filltype:lower():match( "fu" ) then
			filltype = "gas"
		end
		if params.filltype:lower():match( "wa" ) then
			filltype = "water"
		end
		if params.filltype:lower():match( "ba" ) then
			filltype = "batterie"
		end
		if params.filltype:lower():match( "am" ) then
			filltype = "ammo"
		end
		if params.filltype:lower():match( "po" ) then
			filltype = "ammo"
		end
		if params.filltype:lower():match( "ch" ) then
			filltype = "chemicals"
		end	
	end
	
	local Quantitys = {
		1000,
		500,
		250,
		100,
		50,
		25,
		10,
		1
	}
	if filltype == "all" then
		Quantitys = {
			50,
			25,
			10,
			1
		}
	end
	local interactable = sm.shape.getInteractable( params.shape ) 
	local container = sm.interactable.getContainer( interactable, 0 )
	if container then
		for index, Quantity in pairs( Quantitys ) do
			for loop = 0, 20 do
				if sm.container.canCollect( container, obj_consumable_gas, Quantity ) and ( filltype == "all" or filltype == "gas" ) then
					sm.container.beginTransaction()
					sm.container.collect( container, obj_consumable_gas, Quantity, true )	
					if sm.container.endTransaction() then	
					end		
				end
				if sm.container.canCollect( container, obj_consumable_battery, Quantity ) and ( filltype == "all" or filltype == "batterie" )  then	
					sm.container.beginTransaction()
					sm.container.collect( container, obj_consumable_battery, Quantity, true )	
					if sm.container.endTransaction() then					
					end		
				end
				if sm.container.canCollect( container, obj_plantables_potato, Quantity ) and ( filltype == "all" or filltype == "ammo" )  then	
					sm.container.beginTransaction()
					sm.container.collect( container, obj_plantables_potato, Quantity, true )	
					if sm.container.endTransaction() then				
					end		
				end
				if sm.container.canCollect( container, obj_consumable_water, Quantity ) and ( filltype == "all" or filltype == "water" )  then	
					sm.container.beginTransaction()
					sm.container.collect( container, obj_consumable_water, Quantity, true )	
					if sm.container.endTransaction() then				
					end		
				end
				if sm.container.canCollect( container, obj_consumable_chemical, Quantity ) and ( filltype == "all" or filltype == "chemicals" )  then	
					sm.container.beginTransaction()
					sm.container.collect( container, obj_consumable_chemical, Quantity, true )	
					if sm.container.endTransaction() then				
					end		
				end
			end
		end
	end
end

function SurvivalGame.cleanup( self, params )
	sm.event.sendToPlayer( params.player, "Cleanup", params.radius )
end

function SurvivalGame.getLocalBlockGridPosition( self, pos )
	local size = sm.vec3.new( 3, 3, 1 )
	local size_2 = sm.vec3.new( 1, 1, 0 )
	local a = pos * sm.construction.constants.subdivisions
	local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), a.z ) - size_2
	return gridPos * sm.construction.constants.subdivideRatio + ( size * sm.construction.constants.subdivideRatio ) * 0.5
end

function SurvivalGame.PlaceSoilField( self, params )
	print( "Create Field!" )
	for i, k in pairs( params.data ) do 
		if k ~= nil then
			sm.event.sendToPlayer( params.player, "PlaceSoil", k )
		end
	end
end

function SurvivalGame.sv_chunk( self, params )
	sm.character.createCharacter( params[1],params[2], params[3], params[1].character["id"] ) 
end

function SurvivalGame.sv_delete( self, params )
	local shapes = sm.body.getCreationShapes( params.body )
	for i, shape in ipairs(shapes) do 
		sm.shape.destroyShape( shape, 0 )
	end
end

function SurvivalGame.sv_fly( self, data )
	if self.fly == nil then
		self.fly = false
	end
	if self.fly == true then
		self.fly = false
		self.network:sendToClients( "remove_from_g_characters", data.character )
	else
		self.fly = true
		self.network:sendToClients( "add_to_g_characters", data.character )
	end	
	data.character:setSwimming( self.fly )
	data.character:setDiving( self.fly )
	print( "Fly Mode: " ..tostring( self.fly ) )
end

function SurvivalGame.add_to_g_characters( self, character )
	self.fly = true
	local hasPly = false
	for k, g_character in pairs(g_characters) do
		if g_character == character then
			hasPly = true
		end
	end
	if hasPly == false then
		table.insert( g_characters, character )
		sm.gui.displayAlertText( "If the Flymode has not worked, try it again. (lag reason)" )
	end
end

function SurvivalGame.remove_from_g_characters( self, character )
	local newPlayers = {}
	for k, g_character in pairs(g_characters) do
		if g_character ~= character then
			table.insert( newPlayers, g_character )
		end
	end
	self.fly = false
	g_characters = newPlayers
end

function SurvivalGame.sv_clear( self, data )
	local inventory = data.player:getInventory()
	local size = inventory:getSize()
	local lostItems = {}
	print( size )
	for i = 0, size do
		local item = inventory:getItem( i )
		if item.uuid ~= sm.uuid.getNil() then
			item.slot = i
			lostItems[#lostItems+1] = item
		end
	end

	if #lostItems > 0 then
		if sm.container.beginTransaction() then
			for i, item in ipairs( lostItems ) do
				sm.container.spendFromSlot( inventory, item.slot, item.uuid, item.quantity, true )
			end		
			sm.container.endTransaction()
		end
	end
end
-- 00Fant´s code End

function SurvivalGame.sv_giveItem( self, params )
	sm.container.beginTransaction()
	sm.container.collect( params.player:getInventory(), params.item, params.quantity, false )
	sm.container.endTransaction()
end

function SurvivalGame.sv_switchGodMode( self )
	g_godMode = not g_godMode
	self.network:sendToClients( "client_showMessage", "GODMODE: " .. ( g_godMode and "On" or "Off" ) )
end

function SurvivalGame.sv_n_switchAggroMode( self, params )
	sm.game.setEnableAggro(params.aggroMode )
	self.network:sendToClients( "client_showMessage", "AGGRO: " .. ( params.aggroMode and "On" or "Off" ) )
end

function SurvivalGame.sv_enableRestrictions( self, state )
	sm.game.setEnableRestrictions( state )
	self.network:sendToClients( "client_showMessage", ( state and "Restricted" or "Unrestricted"  ) )
end

function SurvivalGame.sv_setLimitedInventory( self, state )
	sm.game.setLimitedInventory( state )
	self.network:sendToClients( "client_showMessage", ( state and "Limited inventory" or "Unlimited inventory"  ) )
end

function SurvivalGame.sv_ambush( self, params )
	if sm.exists( self.sv.saved.overworld ) then
		sm.event.sendToWorld( self.sv.saved.overworld, "sv_ambush", params )
	end
end

function SurvivalGame.sv_recreateWorld( self, player )
	local character = player:getCharacter()
	if character:getWorld() == self.sv.saved.overworld then
		self.sv.saved.overworld:destroy()
		self.sv.saved.overworld = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/Overworld.lua", "Overworld", { dev = g_survivalDev }, self.sv.saved.data.seed )
		self.storage:save( self.sv.saved )

		local params = { pos = character:getWorldPosition(), dir = character:getDirection() }
		self.sv.saved.overworld:loadCell( math.floor( params.pos.x/64 ), math.floor( params.pos.y/64 ), player, "sv_recreatePlayerCharacter", params )

		self.network:sendToClients( "client_showMessage", "Recreating world" )
	else
		self.network:sendToClients( "client_showMessage", "Recreate world only allowed for overworld" )
	end
end

function SurvivalGame.sv_setTimeOfDay( self, timeOfDay )
	if timeOfDay then
		self.sv.time.timeOfDay = timeOfDay
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- Force sync
	end
	self.network:sendToClients( "client_showMessage", ( "Time of day set to "..self.sv.time.timeOfDay ) )
end

function SurvivalGame.sv_setTimeProgress( self, timeProgress )
	if timeProgress ~= nil then
		self.sv.time.timeProgress = timeProgress
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- Force sync
	end
	self.network:sendToClients( "client_showMessage", ( "Time scale set to "..( self.sv.time.timeProgress and "on" or "off ") ) )
end

function SurvivalGame.sv_killPlayer( self, params )
	params.damage = 9999
	sm.event.sendToPlayer( params.player, "sv_e_receiveDamage", params )
end

function SurvivalGame.sv_spawnUnit( self, params )
	sm.event.sendToWorld( params.world, "sv_e_spawnUnit", params )
end

function SurvivalGame.sv_spawnHarvestable( self, params )
	sm.event.sendToWorld( params.world, "sv_spawnHarvestable", params )
end

function SurvivalGame.sv_exportCreation( self, params )
	local obj = sm.json.parseJsonString( sm.creation.exportToString( params.body ) )
	sm.json.save( obj, "$SURVIVAL_DATA/LocalBlueprints/"..params.name..".blueprint" )
end

function SurvivalGame.sv_importCreation( self, params )
	sm.creation.importFromFile( params.world, "$SURVIVAL_DATA/LocalBlueprints/"..params.name..".blueprint", params.position )
end

function SurvivalGame.sv_onChatCommand( self, params, player )
	if params[1] == "/tumble" then
		if params[2] ~= nil then
			player.character:setTumbling( params[2] )
		end
		if player.character:isTumbling() then
			self.network:sendToClients( "client_showMessage", "Player is tumbling" )
		else
			self.network:sendToClients( "client_showMessage", "Player is not tumbling" )
		end

	elseif params[1] == "/sethp" then
		sm.event.sendToPlayer( player, "sv_e_debug", { hp = params[2] } )

	elseif params[1] == "/setwater" then
		sm.event.sendToPlayer( player, "sv_e_debug", { water = params[2] } )

	elseif params[1] == "/setfood" then
		sm.event.sendToPlayer( player, "sv_e_debug", { food = params[2] } )

	elseif params[1] == "/goto" then
		local pos
		if params[2] == "here" then
			pos = player.character:getWorldPosition()
		elseif params[2] == "start" then
			pos = START_AREA_SPAWN_POINT
		elseif params[2] == "hideout" then
			pos = sm.vec3.new( 32, -1248, 100 )
		else
			self.network:sendToClient( player, "client_showMessage", "Unknown place" )
		end
		if pos then
			local cellX, cellY = math.floor( pos.x/64 ), math.floor( pos.y/64 )
			self.sv.saved.overworld:loadCell( cellX, cellY, player, "sv_recreatePlayerCharacter", { pos = pos, dir = player.character:getDirection() } )
		end

	elseif params[1] == "/respawn" then
		sm.event.sendToPlayer( player, "sv_e_respawn" )

	elseif params[1] == "/printglobals" then
		print( "Globals:" )
		for k,_ in pairs(_G) do
			print( k )
		end

	elseif params[1] == "/activatequest" then
		local uuid = params[2]
		if uuid then
			g_questManager:sv_activateQuest( uuid )
		else
			g_questManager:sv_activateAllQuests()
		end
	elseif params[1] == "/completequest" then
		local uuid = params[2]
		if uuid then
			g_questManager:sv_completeQuest( uuid )
		else
			g_questManager:sv_completeAllQuests()
		end
	elseif params[1] == "/clearpathnodes"
		or params[1] == "/enablepathpotatoes"
		or params[1] == "/starterkit"
		or params[1] == "/mechanicstartkit"
		or params[1] == "/pipekit"
		or params[1] == "/foodkit"
		or params[1] == "/seedkit"
		or params[1] == "/aggroall"
		or params[1] == "/raid"
		or params[1] == "/stopraid"
		or params[1] == "/disableraids"
		or params[1] == "/killall"
	then
		params.player = player
		if sm.exists( player.character ) then
			sm.event.sendToWorld( player.character:getWorld(), "sv_e_onChatCommand", params )
		end
	end
end

function SurvivalGame.server_onPlayerJoined( self, player, newPlayer )
	print( player.name, "joined the game" )

	if newPlayer then --Player is first time joiners
		local inventory = player:getInventory()

		sm.container.beginTransaction()

		if g_survivalDev then
			--Hotbar
			sm.container.setItem( inventory, 0, tool_sledgehammer, 1 )
			sm.container.setItem( inventory, 1, tool_spudgun, 1 )
			sm.container.setItem( inventory, 7, obj_plantables_potato, 50 )
			sm.container.setItem( inventory, 8, tool_lift, 1 )
			sm.container.setItem( inventory, 9, tool_connect, 1 )

			--Actual inventory
			sm.container.setItem( inventory, 10, tool_paint, 1 )
			sm.container.setItem( inventory, 11, tool_weld, 1 )
		else
			sm.container.setItem( inventory, 0, tool_sledgehammer, 1 )
			sm.container.setItem( inventory, 1, tool_lift, 1 )
		end

		sm.container.endTransaction()

		local spawnPoint = START_AREA_SPAWN_POINT
		if g_survivalDev then
			spawnPoint = SURVIVAL_DEV_SPAWN_POINT
		end
		if not sm.exists( self.sv.saved.overworld ) then
			sm.world.loadWorld( self.sv.saved.overworld )
		end
		self.sv.saved.overworld:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), player, "sv_createNewPlayer" )
	else
		local inventory = player:getInventory()

		local sledgehammerCount = sm.container.totalQuantity( inventory, tool_sledgehammer )
		if sledgehammerCount == 0 then
			sm.container.beginTransaction()
			sm.container.collect( inventory, tool_sledgehammer, 1 )
			sm.container.endTransaction()
		elseif sledgehammerCount > 1 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_sledgehammer, sledgehammerCount - 1 )
			sm.container.endTransaction()
		end

		local tool_lift_creative = sm.uuid.new( "5cc12f03-275e-4c8e-b013-79fc0f913e1b" )
		local creativeLiftCount = sm.container.totalQuantity( inventory, tool_lift_creative )
		if creativeLiftCount > 0 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_lift_creative, creativeLiftCount )
			sm.container.endTransaction()
		end

		local liftCount = sm.container.totalQuantity( inventory, tool_lift )
		if liftCount == 0 then
			sm.container.beginTransaction()
			sm.container.collect( inventory, tool_lift, 1 )
			sm.container.endTransaction()
		elseif liftCount > 1 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_lift, liftCount - 1 )
			sm.container.endTransaction()
		end
	end
	g_unitManager:sv_onPlayerJoined( player )
	g_questManager:sv_onPlayerJoined( player )
end

function SurvivalGame.server_onPlayerLeft( self, player )
	print( player.name, "left the game" )
	g_elevatorManager:sv_onPlayerLeft( player )
end

function SurvivalGame.sv_e_saveWarehouses( self )
	sm.storage.save( STORAGE_CHANNEL_WAREHOUSES, self.warehouses )
	print( "Saved warehouses:" )
	print( self.warehouses )
end

function SurvivalGame.sv_e_requestWarehouseRestrictions( self, params )
	-- Send the warehouse restrictions to the world that asked
	print("SurvivalGame.sv_e_requestWarehouseRestrictions")

	-- Warehouse get
	local warehouse = nil
	if params.warehouseIndex then
		warehouse = self.warehouses[params.warehouseIndex]
	end
	if warehouse then
		sm.event.sendToWorld( params.world, "server_updateRestrictions", warehouse.restrictions )
	end
end

function SurvivalGame.sv_e_setWarehouseRestrictions( self, params )
	-- Set the restrictions for this warehouse and propagate the restrictions to all floors

	-- Warehouse get
	local warehouse = nil
	if params.warehouseIndex then
		warehouse = self.warehouses[params.warehouseIndex]
	end

	if warehouse then
		for _, newRestrictionSetting in pairs( params.restrictions ) do
			if warehouse.restrictions[newRestrictionSetting.name] then
				warehouse.restrictions[newRestrictionSetting.name].state = newRestrictionSetting.state
			else
				warehouse.restrictions[newRestrictionSetting.name] = newRestrictionSetting
			end
		end
		self.warehouses[params.warehouseIndex] = warehouse
		self:sv_e_saveWarehouses()

		for i, world in ipairs( warehouse.worlds ) do
			if sm.exists( world ) then
				sm.event.sendToWorld( world, "server_updateRestrictions", warehouse.restrictions )
			end
		end
	end
end

function SurvivalGame.sv_e_createElevatorDestination( self, params )
	print( "SurvivalGame.sv_e_createElevatorDestination" )
	print( params )

	-- Warehouse get or create
	local warehouse
	if params.warehouseIndex then
		warehouse = self.warehouses[params.warehouseIndex]
	else
		assert( params.name == "ELEVATOR_ENTRANCE" )
		warehouse = {}
		warehouse.world = params.portal:getWorldA()
		warehouse.worlds = {}
		warehouse.exits = params.exits
		warehouse.maxLevels = params.maxLevels
		warehouse.index = #self.warehouses + 1
		warehouse.restrictions = { erasable = { name = "erasable", state = false }, connectable = { name = "connectable", state = false } }
		self.warehouses[#self.warehouses + 1] = warehouse
		self:sv_e_saveWarehouses()
	end


	-- Level up
	local level
	if params.level then
		if params.name == "ELEVATOR_UP" then
			level = params.level + 1
		elseif params.name == "ELEVATOR_DOWN" then
			level = params.level - 1
		elseif params.name == "ELEVATOR_EXIT" then
			if #warehouse.exits > 0 then
				for _,cell in ipairs( warehouse.exits ) do
					if not sm.exists( warehouse.world ) then
						sm.world.loadWorld( warehouse.world )
					end
					local name = params.name.." "..cell.x..","..cell.y
					sm.portal.addWorldPortalHook( warehouse.world, name, params.portal )
					print( "Added portal hook '"..name.."' in world "..warehouse.world.id )

					g_elevatorManager:sv_loadBForPlayersInElevator( params.portal, warehouse.world, cell.x, cell.y )
				end
			else
				sm.log.error( "No exit hint found, this elevator is going nowhere!" )
			end
			return
		else
			assert( false )
		end
	else
		if params.name == "ELEVATOR_EXIT" then
			level = warehouse.maxLevels
		elseif params.name == "ELEVATOR_ENTRANCE" then
			level = 1
		else
		end
	end

	-- Create warehouse world
	local worldData = {}
	worldData.level = level
	worldData.warehouseIndex = warehouse.index
	worldData.maxLevels = warehouse.maxLevels
	local world = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/WarehouseWorld.lua", "WarehouseWorld", worldData )
	print( "Created WarehouseWorld "..world.id )

	-- Use the same restrictions for the new floor as the other floors
	warehouse.worlds[#warehouse.worlds+1] = world
	if warehouse.restrictions then
		sm.event.sendToWorld( world, "server_updateRestrictions", warehouse.restrictions )
	end
	-- Elevator portal hook
	local name
	if params.name == "ELEVATOR_UP" then
		name = "ELEVATOR_DOWN"
	elseif params.name == "ELEVATOR_DOWN" then
		name = "ELEVATOR_UP"
	else
		name = params.name
	end
	sm.portal.addWorldPortalHook( world, name, params.portal )
	print( "Added portal hook '"..name.."' in world "..world.id )

	g_elevatorManager:sv_loadBForPlayersInElevator( params.portal, world, 0, 0 )
end

function SurvivalGame.sv_e_elevatorEvent( self, params )
	print( "SurvivalGame.sv_e_elevatorEvent" )
	print( params )
	g_elevatorManager[params.fn]( g_elevatorManager, params )
end

function SurvivalGame.sv_createNewPlayer( self, world, x, y, player )
	local params = { player = player, x = x, y = y }
	sm.event.sendToWorld( self.sv.saved.overworld, "sv_spawnNewCharacter", params )
end

function SurvivalGame.sv_recreatePlayerCharacter( self, world, x, y, player, params )
	local yaw = math.atan2( params.dir.y, params.dir.x ) - math.pi/2
	local pitch = math.asin( params.dir.z )
	local newCharacter = sm.character.createCharacter( player, self.sv.saved.overworld, params.pos, yaw, pitch )
	player:setCharacter( newCharacter )
	print( "Recreate character in new world" )
	print( params )
end

function SurvivalGame.sv_e_respawn( self, params )
	if params.player.character and sm.exists( params.player.character ) then
		g_respawnManager:sv_requestRespawnCharacter( params.player )
	else
		local spawnPoint = START_AREA_SPAWN_POINT
		if g_survivalDev then
			spawnPoint = SURVIVAL_DEV_SPAWN_POINT
		end
		if not sm.exists( self.sv.saved.overworld ) then
			sm.world.loadWorld( self.sv.saved.overworld )
		end
		self.sv.saved.overworld:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), params.player, "sv_createNewPlayer" )
	end
end

function SurvivalGame.sv_loadedRespawnCell( self, world, x, y, player )
	g_respawnManager:sv_respawnCharacter( player, world )
end

function SurvivalGame.sv_e_onSpawnPlayerCharacter( self, player )
	if player.character and sm.exists( player.character ) then
		g_respawnManager:sv_onSpawnCharacter( player )
		g_beaconManager:sv_onSpawnCharacter( player )
	else
		sm.log.warning("SurvivalGame.sv_e_onSpawnPlayerCharacter for a character that doesn't exist")
	end
end

function SurvivalGame.sv_e_markBag( self, params )
	if sm.exists( params.world ) then
		sm.event.sendToWorld( params.world, "sv_e_markBag", params )
	else
		sm.log.warning("SurvivalGame.sv_e_markBag in a world that doesn't exist")
	end
end

function SurvivalGame.sv_e_unmarkBag( self, params )
	if sm.exists( params.world ) then
		sm.event.sendToWorld( params.world, "sv_e_unmarkBag", params )
	else
		sm.log.warning("SurvivalGame.sv_e_unmarkBag in a world that doesn't exist")
	end
end

-- Beacons
function SurvivalGame.sv_e_createBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_createBeacon", params )
	else
		sm.log.warning( "SurvivalGame.sv_e_createBeacon in a world that doesn't exist" )
	end
end

function SurvivalGame.sv_e_destroyBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_destroyBeacon", params )
	else
		sm.log.warning( "SurvivalGame.sv_e_destroyBeacon in a world that doesn't exist" )
	end
end

function SurvivalGame.sv_e_unloadBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_unloadBeacon", params )
	else
		sm.log.warning( "SurvivalGame.sv_e_unloadBeacon in a world that doesn't exist" )
	end
end