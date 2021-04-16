--00Fant
-- To Much Changed...
-- Vacuum.lua --
dofile( "$SURVIVAL_DATA/Scripts/game/util/Curve.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/pipes.lua" )
dofile("$SURVIVAL_DATA/Scripts/game/survival_loot.lua")

Vacuum = class()
Vacuum.poseWeightCount = 1
Vacuum.connectionInput = sm.interactable.connectionType.logic
Vacuum.maxParentCount = 2
Vacuum.maxChildCount = 0	
Vacuum.fireDelay = 40 -- ticks
 
-- 00Fant version 2.2
Vacuum.LootFirePower = 5
Vacuum.HarvestAreaSize = 0.5 --DEFAULT IS 0.5


DestroyList = {}

local VacuumMode = { outgoing = 1, incoming = 2 }

local UuidToProjectile = {

	[tostring(obj_consumable_water)] = { name = "water" },
	[tostring(obj_consumable_fertilizer)] = { name = "fertilizer" },
	[tostring(obj_consumable_chemical)] = { name = "chemical" },

	[tostring(obj_plantables_banana)] = { name = "banana" },
	[tostring(obj_plantables_blueberry)] = { name = "blueberry" },
	[tostring(obj_plantables_orange)] = { name = "orange" },
	[tostring(obj_plantables_pineapple)] = { name = "pineapple" },
	[tostring(obj_plantables_carrot)] = { name = "carrot" },
	[tostring(obj_plantables_redbeet)] = { name = "redbeet" },
	[tostring(obj_plantables_tomato)] = { name = "tomato" },
	[tostring(obj_plantables_broccoli)] = { name = "broccoli" },
	[tostring(obj_plantables_potato)] = { name = "potato" },
	[tostring(obj_plantables_eggplant)] = { name = "eggplant" },

	[tostring(obj_seed_banana)] = { name = "seed", hvs = hvs_growing_banana },
	[tostring(obj_seed_blueberry)] = { name = "seed", hvs = hvs_growing_blueberry },
	[tostring(obj_seed_orange)] = { name = "seed", hvs = hvs_growing_orange },
	[tostring(obj_seed_pineapple)] = { name = "seed", hvs = hvs_growing_pineapple },
	[tostring(obj_seed_carrot)] = { name = "seed", hvs = hvs_growing_carrot },
	[tostring(obj_seed_potato)] = { name = "seed", hvs = hvs_growing_potato },
	[tostring(obj_seed_redbeet)] = { name = "seed", hvs = hvs_growing_redbeet },
	[tostring(obj_seed_tomato)] = { name = "seed", hvs = hvs_growing_tomato },
	[tostring(obj_seed_broccoli)] = { name = "seed", hvs = hvs_growing_broccoli },
	[tostring(obj_seed_cotton)] = { name = "seed", hvs = hvs_growing_cotton },
	[tostring(obj_seed_eggplant)] = { name = "seed", hvs = hvs_growing_eggplant },
}

function Vacuum.server_onCreate( self )
	self.sv = {}

	-- client table goes to client
	self.sv.client = {}
	self.sv.client.pipeNetwork = {}
	self.sv.client.state = PipeState.off
	self.sv.client.showBlockVisualization = false

	-- storage table goes to storage
	self.sv.storage = self.storage:load()
	if self.sv.storage == nil then
		self.sv.storage = { mode = VacuumMode.outgoing } -- Default value
		self.storage:save( self.sv.storage )
	end

	self.sv.dirtyClientTable = false
	self.sv.dirtyStorageTable = false

	self.sv.fireDelayProgress = 0
	self.sv.canFire = true
	self.sv.ChestCollectTimer = 0
	self.sv.ChestCollectItemIndex = 0
	self.sv.areaTrigger = nil
	self.sv.connectedContainers = {}
	self.sv.foundContainer = nil
	self.sv.foundItem = sm.uuid.getNil()
	self.sv.parentActive = false
	self:sv_buildPipeNetwork()
	self:sv_updateStates()
	self.last_setVacuumStateOnAllShapes = nil
	-- public data used to interface with the packing station
	self.interactable:setPublicData( { packingStationTick = 0 } )
	
	self.sv.startDelay = 4
end

function Vacuum.sv_markClientTableAsDirty( self )
	self.sv.dirtyClientTable = true
end

function Vacuum.sv_markStorageTableAsDirty( self )
	self.sv.dirtyStorageTable = true
	self:sv_markClientTableAsDirty()
end

function Vacuum.sv_n_toogle( self )
	if self.sv.storage.mode == VacuumMode.outgoing then
		self:server_outgoingReset()
		self.sv.storage.mode = VacuumMode.incoming
	else
		self.sv.storage.mode = VacuumMode.outgoing
	end

	self:sv_updateStates()
	self:sv_markStorageTableAsDirty()
end

function Vacuum.sv_updateStates( self )

	if self.sv.storage.mode == VacuumMode.incoming then
		if not self.sv.areaTrigger then
			local size = sm.vec3.new( self.HarvestAreaSize, self.HarvestAreaSize, self.HarvestAreaSize )		
			-- 00Fant start
			
			--local filter = sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.areaTrigger + sm.areaTrigger.filter.harvestable
			local filter = sm.areaTrigger.filter.all

			-- 00Fant end
			self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, size, sm.vec3.new(0.0, -1.0, 0.0), sm.quat.identity(), filter )			
			self.sv.areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
		end
	else
		if self.sv.areaTrigger then
			sm.areaTrigger.destroy( self.sv.areaTrigger )
			self.sv.areaTrigger = nil
		end
	end
end

function Vacuum.sv_buildPipeNetwork( self )

	self.sv.client.pipeNetwork = {}
	self.sv.connectedContainers = {}

	local function fnOnVertex( vertex )

		if isAnyOf( vertex.shape:getShapeUuid(), ContainerUuids ) then -- Is Container
			assert( vertex.shape:getInteractable():getContainer() )
			local container = {
				shape = vertex.shape,
				distance = vertex.distance,
				shapesOnContainerPath = vertex.shapesOnPath
			}

			table.insert( self.sv.connectedContainers, container )
		elseif isAnyOf( vertex.shape:getShapeUuid(), PipeUuids ) then -- Is Pipe
			assert( vertex.shape:getInteractable() )
			local pipe = {
				shape = vertex.shape,
				state = PipeState.off
			}

			table.insert( self.sv.client.pipeNetwork, pipe )
		end

		return true
	end

	ConstructPipedShapeGraph( self.shape, fnOnVertex )

	-- Sort container by closests
	table.sort( self.sv.connectedContainers, function(a, b) return a.distance < b.distance end )

	-- Synch the pipe network and initial state to clients
	local state = PipeState.off

	for _, container in ipairs( self.sv.connectedContainers ) do
		for _, shape in ipairs( container.shapesOnContainerPath ) do
			for _, pipe in ipairs( self.sv.client.pipeNetwork ) do
				if pipe.shape:getId() == shape:getId() then
					pipe.state = PipeState.connected
				end
			end
		end
	end

	self.sv.client.state = state
	self:sv_markClientTableAsDirty()
end

function Vacuum.constructionRayCast( self )
	local start = self.shape:getWorldPosition()
	local stop = self.shape:getWorldPosition() - self.shape.at * 4.625
	local valid, result = sm.physics.raycast( start, stop, self.shape )
	if valid then
		local groundPointOffset = -( sm.construction.constants.subdivideRatio_2 - 0.04 + sm.construction.constants.shapeSpacing + 0.005 )
		local pointLocal = result.pointLocal
		if result.type ~= "body" and result.type ~= "joint" then
			pointLocal = pointLocal + result.normalLocal * groundPointOffset
		end

		local n = sm.vec3.closestAxis( result.normalLocal )
		local a = pointLocal * sm.construction.constants.subdivisions - n * 0.5
		local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), math.floor( a.z ) ) + n

		local function getTypeData()
			local shapeOffset = sm.vec3.new( sm.construction.constants.subdivideRatio_2, sm.construction.constants.subdivideRatio_2, sm.construction.constants.subdivideRatio_2 )
			local localPos = gridPos * sm.construction.constants.subdivideRatio + shapeOffset
			if result.type == "body" then
				local shape = result:getShape()
				if shape and sm.exists( shape ) then
					return shape:getBody():transformPoint( localPos ), shape
				else
					valid = false
				end
			elseif result.type == "joint" then
				local joint = result:getJoint()
				if joint and sm.exists( joint ) then
					return joint:getShapeA():getBody():transformPoint( localPos ), joint
				else
					valid = false
				end
			elseif result.type == "lift" then
				local lift, topShape = result:getLiftData()
				if lift and ( not topShape or lift:hasBodies() ) then
					valid = false
				end
				return localPos, lift
			end
			return localPos
		end

		local worldPos, obj = getTypeData()
		return valid, gridPos, result.normalLocal, worldPos, obj
	end
	return valid
end

function Vacuum.server_outgoingReload( self, container, item )
	self.sv.foundContainer, self.sv.foundItem = container, item

	local isBlock = sm.item.isBlock( self.sv.foundItem )
	if self.sv.client.showBlockVisualization ~= isBlock then
		self.sv.client.showBlockVisualization = isBlock
		self:sv_markClientTableAsDirty()
	end

	if self.sv.canFire then
		self.sv.fireDelayProgress = Vacuum.fireDelay
		self.sv.canFire = false
	end

	if self.sv.foundContainer then
		self.network:sendToClients( "cl_n_onOutgoingReload", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath, item = self.sv.foundItem } )
	end
end

function Vacuum.server_outgoingReset( self )
	self.sv.canFire = false
	self.sv.foundContainer = nil
	self.sv.foundItem = sm.uuid.getNil()

	if self.sv.client.showBlockVisualization then
		self.sv.client.showBlockVisualization = false
		self:sv_markClientTableAsDirty()
	end
end

function Vacuum.server_outgoingLoaded( self )
	return self.sv.foundContainer and self.sv.foundItem ~= sm.uuid.getNil()
end

function Vacuum.server_outgoingShouldReload( self, container, item )
	return self.sv.foundItem ~= item
end

function Vacuum.getInputs( self )
	local ActiveButtonInputParent = nil
	local ArrowSwitchInputParent = nil
	for index, parent in pairs( sm.interactable.getParents( self.shape:getInteractable() ) ) do
		if tostring( sm.shape.getColor( sm.interactable.getShape( parent ) ) ) == "d02525ff" then  --Red
			ArrowSwitchInputParent = parent
		else
			ActiveButtonInputParent = parent
		end
	end
	return ActiveButtonInputParent, ArrowSwitchInputParent
end

function Vacuum.server_onFixedUpdate( self )
	if self.sv.startDelay > 0 then
		self.sv.startDelay = self.sv.startDelay  - (1/40)
		return
	end
	DestroyListLoop(self)
	
	local function setVacuumState( state, shapes )
		if self.sv.client.state ~= state then
			self.sv.client.state = state
			self:sv_markClientTableAsDirty()
		end

		for _, obj in ipairs( self.sv.client.pipeNetwork ) do
			for _, shape in ipairs( shapes ) do
				if obj.shape:getId() == shape:getId() then
					if obj.state ~= state then
						obj.state = state
						self:sv_markClientTableAsDirty()
					end
				end
			end
		end
	end

	local function setVacuumStateOnAllShapes( state )
		if self.sv.client.state ~= state then
			self.sv.client.state = state
			self:sv_markClientTableAsDirty()
		end

		for _, container in ipairs( self.sv.connectedContainers ) do
			for _, shape in ipairs( container.shapesOnContainerPath ) do
				for _, pipe in ipairs( self.sv.client.pipeNetwork ) do
					if pipe.shape:getId() == shape:getId() then
						pipe.state = state
						self:sv_markClientTableAsDirty()
					end
				end
			end
		end

	end

	-- Update fire delay progress
	if not self.sv.canFire then
		self.sv.fireDelayProgress = self.sv.fireDelayProgress - 1
		if self.sv.fireDelayProgress <= 0 then
			self.sv.fireDelayProgress = Vacuum.fireDelay
			self.sv.canFire = true
		end
	end

	
	
	-- Optimize this either through a simple has changed that only checks the body and not shapes
	-- Or let the body check and fire an event whenever it detects a change
	-- if  self.shape:getBody():hasChanged( sm.game.getCurrentTick() - 1 ) then
		-- self:sv_buildPipeNetwork()
	-- end
	

	if self.sv.ChestCollectTimer == nil then
		self.sv.ChestCollectTimer = 0
	end
	if self.sv.ChestCollectTimer > 0 then
		self.sv.ChestCollectTimer = self.sv.ChestCollectTimer - 1
		--print( self.sv.ChestCollectTimer )
	end
	
	
	
	local parents, arrowSwitchparent = self:getInputs() --sm.interactable.getParents( self.shape:getInteractable() )
	if self.LastarrowSwitchparent == nil then
		self.LastarrowSwitchparent = false
	end
	if arrowSwitchparent ~= nil then
		if self.LastarrowSwitchparent ~= arrowSwitchparent.active then
			self.LastarrowSwitchparent = arrowSwitchparent.active
			
			if arrowSwitchparent.active then
				self:server_outgoingReset()
				self.sv.storage.mode = VacuumMode.incoming
			else
				self.sv.storage.mode = VacuumMode.outgoing
			end

			self:sv_updateStates()
			self:sv_markStorageTableAsDirty()
					
		end
	end
	
	if self.lastChangedPipPipeNetwork == nil then
		self.lastChangedPipPipeNetwork = 0
	end
	if self.shape:getBody():hasChanged( sm.game.getCurrentTick() - 1 ) then
		if self.lastChangedPipPipeNetwork <= 0 then
			self.sv.ChangedPipPipeNetwork = true
		end
	end
	if self.lastChangedPipPipeNetwork >= 0 then
		self.lastChangedPipPipeNetwork = self.lastChangedPipPipeNetwork - 0.08
		if self.lastChangedPipPipeNetwork <= 0 then
			self.lastChangedPipPipeNetwork = 0
		end
	end	
	if parents then
		if parents.active then
			if self.sv.ChangedPipPipeNetwork then
				self:sv_buildPipeNetwork()
				self.sv.ChangedPipPipeNetwork = false
				self.lastChangedPipPipeNetwork = 1
			end
		end
	end
	
	if self.sv.storage.mode == VacuumMode.outgoing and #self.sv.connectedContainers > 0 then
		local publicData = self.interactable:getPublicData()
		assert(publicData)
		local interfacingWithPackingStation = sm.game.getCurrentTick() - 4 < publicData.packingStationTick

		local parent = parents --self.shape:getInteractable():getSingleParent()
		
		
		if parent then
			if parent.active and not self.sv.parentActive and self.sv.canFire then
				if interfacingWithPackingStation then
					assert( publicData.packingStationProjectileName )
					local function findItemUidFromProjectileName()
						for uid, projectile in pairs( UuidToProjectile ) do
							if projectile.name == publicData.packingStationProjectileName  then
								return sm.uuid.new( uid );
							end			
						end
						return sm.uuid.getNil()
					end

					local itemUid = findItemUidFromProjectileName()
					assert( itemUid )

					local function findContainerAndItemWithUid()
						for _, container in ipairs( self.sv.connectedContainers ) do
							if sm.exists( container.shape ) then
								if not container.shape:getInteractable():getContainer():isEmpty() then
									if sm.container.canSpend( container.shape:getInteractable():getContainer(), itemUid, 1 ) then
										return container, itemUid
									end
								end
							end
						end
						return nil, sm.uuid.getNil()
					end

					local container, item = findContainerAndItemWithUid()
					if item == itemUid then
						if self:server_outgoingShouldReload( container, item ) then
							self:server_outgoingReload( container, item )
						end
						publicData.requestExternalOpen = true
						setVacuumState( PipeState.valid, self.sv.connectedContainers[1].shapesOnContainerPath )
					else
						publicData.requestExternalOpen = false
						setVacuumState( PipeState.invalid, self.sv.connectedContainers[1].shapesOnContainerPath )
					end

				else
					if publicData.requestExternalOpen then
						self:server_outgoingReset()
					end
					publicData.requestExternalOpen = false
					setVacuumState( PipeState.connected, self.sv.connectedContainers[1].shapesOnContainerPath )
				end


				local function getFilterChest( updown )		
					local FilterChestStart = self.shape:getWorldPosition()
					local FilterChestStop = self.shape:getWorldPosition() - sm.shape.getUp( self.shape ) * 1
					if updown then
						FilterChestStop = self.shape:getWorldPosition() + sm.shape.getUp( self.shape ) * 1
					end
					local FilterChestValid, FilterChestResult = sm.physics.raycast( FilterChestStart, FilterChestStop, self.shape )
					
					if FilterChestValid and FilterChestResult then
						if FilterChestResult.type == "body" then
							FilterChestShape = FilterChestResult:getShape()
							if FilterChestShape then
								if FilterChestShape:getInteractable() then
									if FilterChestShape:getInteractable():getContainer() then
										return FilterChestShape:getInteractable():getContainer(), FilterChestResult					
									end			
								end					
							end
						elseif FilterChestResult.type == "shape" then
							if FilterChestResult then
								if FilterChestResult:getInteractable() then
									if FilterChestResult:getInteractable():getContainer() then
										return FilterChestResult:getInteractable():getContainer(), FilterChestResult
									end
								end
							end
						end										
					end
					return nil, nil
				end

				local FilterChestContainer , FilterChestObj = getFilterChest( true )
				if not FilterChestContainer then
					FilterChestContainer , FilterChestObj = getFilterChest( false )	
				end
				--print(FilterChestContainer)
				
				if not interfacingWithPackingStation then
					local function findFirstContainerAndItem()
						for _, container in ipairs( self.sv.connectedContainers ) do
							if sm.exists( container.shape ) then
								if not container.shape:getInteractable():getContainer():isEmpty() then
									for slot = 0, container.shape:getInteractable():getContainer():getSize() - 1 do
										local item = container.shape:getInteractable():getContainer():getItem( slot )
										local IncludeFilter = false
										local foundItem = false
										
										if item.uuid ~= tool_gatling and item.uuid ~= tool_shotgun and item.uuid ~= tool_spudgun and item.uuid ~= tool_spudgun_creative and item.uuid ~= tool_weld and item.uuid ~= tool_paint and item.uuid ~= tool_connect and item.uuid ~= tool_lift and item.uuid ~= tool_sledgehammer then
											if FilterChestContainer then
												
												local FilterChestrgb = 0
												if FilterChestObj then
													FilterChestColor = sm.shape.getColor( FilterChestObj:getShape() )
													FilterChestrgb = math.floor( ( FilterChestColor.r + FilterChestColor.g + FilterChestColor.b ) * 10 ) / 10
												end
												--print(FilterChestObj)
												if FilterChestrgb ~= 2.8 then
													IncludeFilter = true
												else
													IncludeFilter = false
												end
												
												for Filterslot = 0, FilterChestContainer:getSize() - 1 do
													local Filteritem = FilterChestContainer:getItem( Filterslot )											
													if Filteritem then
														if Filteritem.uuid == item.uuid then
															if Filteritem.quantity > 0 then
																foundItem = true
																break
															end
														end
													end
												end
											else
												foundItem = true
											end
											
											--print(tostring(foundItem) .. " - " .. tostring(IncludeFilter).. " - " .. tostring(FilterChestContainer))
											
											if not FilterChestContainer then
												if UuidToProjectile[tostring(item.uuid)] or sm.item.isBlock( item.uuid ) then
													return container, item.uuid
												else									
													if item then
														if item.quantity > 0 then
															return container, item.uuid
														end
													end
												end												
											else
												if foundItem and IncludeFilter then
													if UuidToProjectile[tostring(item.uuid)] or sm.item.isBlock( item.uuid ) then
														return container, item.uuid
													else									
														if item then
															if item.quantity > 0 then
																return container, item.uuid
															end
														end
													end																																										
												elseif not foundItem and not IncludeFilter then
													if UuidToProjectile[tostring(item.uuid)] or sm.item.isBlock( item.uuid ) then
														return container, item.uuid
													else									
														if item then
															if item.quantity > 0 then
																return container, item.uuid
															end
														end
													end																																										
												end
											end
										end
									end
								end
							end
						end
						return nil, sm.uuid.getNil()
					end
					local container, item = findFirstContainerAndItem()
					if self:server_outgoingShouldReload( container, item ) then
						self:server_outgoingReload( container, item )
					end
				end

				local function isValidPlacement()
					local hit, gridPos, normalLocal, worldPos, obj = self:constructionRayCast()
					if sm.item.isBlock( self.sv.foundItem ) then						
						if hit then
							local function countTerrain()
								if type(obj) == "Shape" then
									return obj:getBody():isDynamic()
								end
								return false
							end
							return sm.physics.sphereContactCount( worldPos, 0.125, countTerrain() ) == 0 and
							sm.construction.validateLocalPosition( self.sv.foundItem, gridPos, normalLocal, obj ), gridPos, obj, false
						end
					else
						return false, worldPos, obj, true
					end
				end
				local valid, gridPos, obj, drop = isValidPlacement()
						
				
				
				--00Fant
				PumpMode = false	
				FindChestContainer = nil
				
				if obj then
					local FindChestStart = self.shape:getWorldPosition()
					local FindChestStop = self.shape:getWorldPosition() - self.shape.at * 5
					local FindChestValid, FindChestResult = sm.physics.raycast( FindChestStart, FindChestStop, self.shape )
					
					if FindChestValid and FindChestResult then
						if FindChestResult.type == "body" then
							FindChestShape = FindChestResult:getShape()
							if FindChestShape then
								if FindChestShape:getInteractable() then
									FindChestContainer = FindChestShape:getInteractable():getContainer()						
								end					
							end
						elseif FindChestResult.type == "shape" then
							if FindChestResult then
								if FindChestResult:getInteractable() then
									FindChestContainer = FindChestResult:getInteractable():getContainer()
								end
							end
						end								
					end
				end

							
				if FindChestContainer and self.sv.foundContainer then					
					sm.container.beginTransaction()
					sm.container.collect( FindChestContainer, self.sv.foundItem, 1, true)			
					if sm.container.endTransaction() then
						sm.container.beginTransaction()
						sm.container.spend( self.sv.foundContainer.shape:getInteractable():getContainer(), self.sv.foundItem, 1, true )
						if sm.container.endTransaction() then
							self.network:sendToClients( "cl_n_onOutgoingFire", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath, withoutEffect = true } )
						end
						self:server_outgoingReset()
					end
				else
					
					PumpColor = sm.shape.getColor( self.shape )
					Pumprgb = math.floor( ( PumpColor.r + PumpColor.g + PumpColor.b ) * 10 ) / 10
					if Pumprgb == 2.8 then
						PumpMode = true
					else
						PumpMode = false
					end
					
					if PumpMode then
						if self.sv.foundItem ~= sm.uuid.getNil() then					
							sm.container.beginTransaction()
							sm.container.spend( self.sv.foundContainer.shape:getInteractable():getContainer(), self.sv.foundItem, 1, true )
							if sm.container.endTransaction() then										
								if self.sv.foundItem == obj_resource_corn then
									sm.shape.createPart( obj_resource_corn, self.shape.worldPosition + sm.shape.getAt( self.shape ) * -1, sm.quat.identity(), true, true ) 
								elseif self.sv.foundItem == obj_consumable_fant_popcorn then
									sm.shape.createPart( obj_consumable_fant_popcorn, self.shape.worldPosition + sm.shape.getAt( self.shape ) * -1, sm.quat.identity(), true, true ) 
								elseif self.sv.foundItem == obj_interactive_propanetank_small then
									part = sm.shape.createPart( obj_interactive_propanetank_small, self.shape.worldPosition + sm.shape.getAt( self.shape ) * -1, sm.quat.identity(), true, true ) 	
									--print( part )
									--sm.physics.applyImpulse( part, sm.vec3.new( 0, -2500, 0 ), false, nil )
									
								elseif self.sv.foundItem == obj_interactive_propanetank_large then
									part = sm.shape.createPart( obj_interactive_propanetank_large, self.shape.worldPosition + sm.shape.getAt( self.shape ) * -1, sm.quat.identity(), true, true ) 									
									--sm.physics.applyImpulse( part, sm.vec3.new( 0, -2500, 0 ), false, nil )
								else
									local projectileName = "loot"
									local params = { lootUid = self.sv.foundItem, lootQuantity = 1, epic = false }
									sm.projectile.shapeCustomProjectileAttack( params, projectileName, 0, sm.vec3.new( 0, 0, 0 ), sm.vec3.new( 0, -Vacuum.LootFirePower, 0 ), self.shape, 0 )			
									self.network:sendToClients( "cl_n_onOutgoingFire", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath } )					
								end							
								self.network:sendToClients( "cl_n_onOutgoingFire", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath } )									
							end		
							self:server_outgoingReset()
						else
							self.network:sendToClients( "cl_n_onError", { shapesOnContainerPath = self.sv.connectedContainers[1].shapesOnContainerPath } )
						end
					else
						local projectile = UuidToProjectile[tostring( self.sv.foundItem )]
						if projectile then
							sm.container.beginTransaction()
							sm.container.spend( self.sv.foundContainer.shape:getInteractable():getContainer(), self.sv.foundItem, 1, true )
							if sm.container.endTransaction() then
								-- If successful spend, fire an projectile
								if projectile.hvs then
									sm.projectile.shapeCustomProjectileAttack(
										{ hvs = projectile.hvs },
										projectile.name,
										0,
										sm.vec3.new( 0.0, 0.25, 0.0 ),
										sm.vec3.new( 0, -100, 0 ),
										self.shape )
								else
									sm.projectile.shapeFire(
										self.shape,
										projectile.name,
										sm.vec3.new( 0.0, 0.25, 0.0 ),
										sm.vec3.new( 0, -20, 0 ) )
								end

								self.network:sendToClients( "cl_n_onOutgoingFire", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath } )
							end
							self:server_outgoingReset()
						elseif valid then						
							sm.container.beginTransaction()
							sm.container.spend( self.sv.foundContainer.shape:getInteractable():getContainer(), self.sv.foundItem, 1, true )
							if sm.container.endTransaction() then	
								sm.construction.buildBlock( self.sv.foundItem, gridPos, obj )	
								self.network:sendToClients( "cl_n_onOutgoingFire", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath } )
							end
							self:server_outgoingReset()				
						else
							if self.sv.foundItem ~= sm.uuid.getNil() then	
								if not sm.item.isBlock( self.sv.foundItem ) then
									sm.container.beginTransaction()
									sm.container.spend( self.sv.foundContainer.shape:getInteractable():getContainer(), self.sv.foundItem, 1, true )
									if sm.container.endTransaction() then										
										local projectileName = "loot"
										local params = { lootUid = self.sv.foundItem, lootQuantity = 1, epic = false }
										sm.projectile.shapeCustomProjectileAttack( params, projectileName, 0, sm.vec3.new( 0, 0, 0 ), sm.vec3.new( 0, -Vacuum.LootFirePower, 0 ), self.shape, 0 )			
										self.network:sendToClients( "cl_n_onOutgoingFire", { shapesOnContainerPath = self.sv.foundContainer.shapesOnContainerPath } )									
									end		
									self:server_outgoingReset()
								else
									self.network:sendToClients( "cl_n_onError", { shapesOnContainerPath = self.sv.connectedContainers[1].shapesOnContainerPath } )
								end
							end
						end
					end

				end
			end
			self.sv.parentActive = parent.active
		end

	elseif self.sv.storage.mode == VacuumMode.incoming and #self.sv.connectedContainers > 0 then
		local incomingObjects = {}
		local parent = parents --self.shape:getInteractable():getSingleParent()
		if parent and parent.active then
			local function GetCollectChest()
				local CollectChestStart = self.shape:getWorldPosition()
				local CollectChestStop = self.shape:getWorldPosition() - sm.shape.getAt( self.shape ) * 1.75
				
				local CollectChestValid, CollectChestResult = sm.physics.raycast( CollectChestStart, CollectChestStop, self.shape )
				
				if CollectChestValid and CollectChestResult then
					local obj, container
					
					if CollectChestResult.type == "body" then
						FilterChestShape = CollectChestResult:getShape()
						if FilterChestShape then
							if FilterChestShape:getInteractable() then
								if FilterChestShape:getInteractable():getContainer() then
									container = FilterChestShape:getInteractable():getContainer()
									obj = CollectChestResult					
								end			
							end					
						end
					elseif CollectChestResult.type == "shape" then
						if CollectChestResult then
							if CollectChestResult:getInteractable() then
								if FilterChestShape:getInteractable():getContainer() then
									container = FilterChestShape:getInteractable():getContainer()
									obj = CollectChestResult					
								end	
							end
						end
					end		
					
					return obj, container
				end
			end
			local CollectChestPart, CollectChestContainer = GetCollectChest()
			
			
			local function getFilterChest( updown )		
				local FilterChestStart = self.shape:getWorldPosition()
				local FilterChestStop = self.shape:getWorldPosition() - sm.shape.getUp( self.shape ) * 1
				if updown then
					FilterChestStop = self.shape:getWorldPosition() + sm.shape.getUp( self.shape ) * 1
				end
				local FilterChestValid, FilterChestResult = sm.physics.raycast( FilterChestStart, FilterChestStop, self.shape )
				
				if FilterChestValid and FilterChestResult then
					local containerPart, containerObj, AntiFilter
					
					if FilterChestResult.type == "body" then
						FilterChestShape = FilterChestResult:getShape()
						if FilterChestShape then
							if FilterChestShape:getInteractable() then
								if FilterChestShape:getInteractable():getContainer() then
									containerPart = FilterChestShape:getInteractable():getContainer()
									containerObj = FilterChestResult					
								end			
							end					
						end
					elseif FilterChestResult.type == "shape" then
						if FilterChestResult then
							if FilterChestResult:getInteractable() then
								if FilterChestShape:getInteractable():getContainer() then
									containerPart = FilterChestShape:getInteractable():getContainer()
									containerObj = FilterChestResult					
								end	
							end
						end
					end		
					
					local FilterChestrgb = 0
					if containerObj then
						FilterChestColor = sm.shape.getColor( containerObj:getShape() )
						FilterChestrgb = math.floor( ( FilterChestColor.r + FilterChestColor.g + FilterChestColor.b ) * 10 ) / 10
					end
					--print(FilterChestObj)
					if FilterChestrgb ~= 2.8 then
						AntiFilter = false
					else
						AntiFilter = true
					end
					
					return containerPart, containerObj, AntiFilter
				end

			end

			local FilterChestContainer , FilterChestObj, AntiFilter = getFilterChest( true )
			if not FilterChestContainer then
				FilterChestContainer , FilterChestObj, AntiFilter = getFilterChest( false )	
			end

			local function CheckFilterChestItem( container, itemUid, antiFilterState )
				if not container then
					return true
				end

				if not container:isEmpty() then
					if sm.container.canSpend( container, itemUid, 1 ) then		
						if antiFilterState then
							return false 
						end
						return true 
					end
				end
				if antiFilterState then
					return true 
				end
				return false 
			end
			

			
			
			if CollectChestContainer and self.sv.ChestCollectTimer <= 0 then
				--print( CollectChestContainer )
				local partUuid = nil
				local amount = 0
				for Collectslot = 0, CollectChestContainer:getSize() - 1 do
					local Collectitem = CollectChestContainer:getItem( Collectslot )											
					if Collectitem then
						if Collectitem.uuid then
							if Collectitem.quantity > 0 then
								if CheckFilterChestItem( FilterChestContainer, Collectitem.uuid, AntiFilter ) then
									partUuid = Collectitem.uuid
									amount = Collectitem.quantity
									break
								end
							end
						end
					end
				end
				if partUuid and amount then
					local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )		
					if container then	
						if sm.container.canSpend( CollectChestContainer, partUuid, amount ) then						
							sm.container.beginTransaction()
							sm.container.spend( CollectChestContainer, partUuid, amount, true )
							if sm.container.endTransaction() then										
								table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, withOutSuckEffect = true } )	
								self.sv.ChestCollectTimer = Vacuum.fireDelay
								self.network:sendToClients( "cl_n_onIncomingFire", { shapesOnContainerPath = container.shapesOnContainerPath, item = partUuid, withEffect = false } )
							end			
						end					
					end		
				end
				self.sv.canFire = true
			elseif not CollectChestContainer then	
				for _, result in ipairs(  self.sv.areaTrigger:getContents() ) do	
					if sm.exists( result ) and IsNotInList( result ) then	
						if type( result ) == "Harvestable" then	
							if result:getType() == "mature"  then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = data["amount"]

									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											-- Collect seeds from harvestable
											local seedUuid = data["seed"]
											local seedIncomingObj = nil
											if seedUuid then
												local seedAmount = randomStackAmountAvg2()
												seedUuid = sm.uuid.new( seedUuid )
												local seedContainer = FindContainerToCollectTo( self.sv.connectedContainers, seedUuid, seedAmount )
												if seedContainer then
													seedIncomingObj = { container = seedContainer, uuid = seedUuid, amount = seedAmount }
												end
											end
											table.insert( incomingObjects, { container = container, harvestable = result, uuid = partUuid, amount = amount, seedIncomingObj = seedIncomingObj, Object = result } )
										end
									end
								end
							elseif result:getType() == "oil" and CheckFilterChestItem( FilterChestContainer, obj_resource_crudeoil, AntiFilter ) then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = math.random( 1, 3 )
									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, isOil = true, destroy = true } )										
										end
									end
								end
							elseif result:getType() == "flower" and CheckFilterChestItem( FilterChestContainer, obj_resource_flower, AntiFilter ) then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = math.random( 1, 4 )
									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, destroy = true, isFlower = true } )									
										end
									end
								end	
							elseif result:getType() == "corn" and CheckFilterChestItem( FilterChestContainer, obj_resource_corn, AntiFilter ) then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = math.random( 1, 4 )
									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, destroy = true, isCorn = true } )								
										end
									end
								end	
							elseif result:getType() == "clam" and CheckFilterChestItem( FilterChestContainer, obj_resources_slimyclam, AntiFilter ) then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = math.random( 1, 4 )
									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, destroy = true, isClam = true } )									
										end
									end
								end												
							elseif result:getType() == "honey"  and CheckFilterChestItem( FilterChestContainer, obj_resource_beewax, AntiFilter )then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = math.random( 2, 4 )
									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, destroy = true, isHoney = true } )									
										end
									end
								end												
							elseif result:getType() == "cotton" and CheckFilterChestItem( FilterChestContainer, obj_resource_cotton, AntiFilter ) then
								local data = result:getData()
								if data then
									local partUuid = data["harvest"]
									local amount = 1
									if partUuid and amount then
										partUuid = sm.uuid.new( partUuid )
										local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
										if container then
											table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, destroy = true, isCotton = true } )								
										end
									end
								end												
							elseif result:getType() == "filler" then	
								local lootObject  = g_lootHarvestables[result["id"]]
								if lootObject then 
									local LootUuid = lootObject["uuid"]
									local amount = lootObject["quantity"]
									local container = FindContainerToCollectTo( self.sv.connectedContainers, LootUuid, amount )
									if container and CheckFilterChestItem( FilterChestContainer, LootUuid, AntiFilter ) then									
										table.insert( incomingObjects, { container = container, uuid = LootUuid, amount = amount, Object = result, destroy = true } )																		
									end			
								end					
							elseif result:getData() ~= "" then
								local data = result:getData()
								if data then
									if data["destroyEffect"] == "LootCrate - Destroy" then
										local lootTable = self.saved and self.saved.lootTable or nil
										if lootTable == nil then
											lootTable = "loot_crate_standard" 
										end
										local lootList = SelectLoot( lootTable )
										for i = 1, #lootList do								 
											local partUuid = lootList[i].uuid
											local amount = lootList[i].quantity or 1
											local container = FindContainerToCollectTo( self.sv.connectedContainers, partUuid, amount )
											if container then
												if partUuid and amount then
													table.insert( incomingObjects, { container = container, uuid = partUuid, amount = amount, Object = result, destroy = true, isLootCrate = true } )																		
												end		
											end
										end							
									end			
								end												
							else					
								print( "Muh" )
							end		
							-- 00Fant end

						elseif type( result ) == "AreaTrigger" then
							local userData = result:getUserData()
							if userData and ( userData.water == true or userData.chemical == true or userData.oil == true )  then
								local uidLiquidType = obj_consumable_water
								if userData.chemical == true then
									uidLiquidType = obj_consumable_chemical
								elseif userData.oil == true then
									uidLiquidType = obj_resource_crudeoil
								end
								
								if CheckFilterChestItem( FilterChestContainer, uidLiquidType, AntiFilter ) then
								
									local container = FindContainerToCollectTo( self.sv.connectedContainers, uidLiquidType, 1 )
									if container then

										local waterZ = result:getWorldMax().z
										local raycastStart = self.shape:getWorldPosition() + self.shape.at
										if raycastStart.z > waterZ then

											local raycastEnd = self.shape:getWorldPosition() - self.shape.at * 4

											local hit, result = sm.physics.raycast( raycastStart, raycastEnd, self.shape:getBody(), sm.physics.filter.static + sm.physics.filter.areaTrigger )
											if hit and result.type == "areaTrigger" then
												table.insert( incomingObjects, { container = container, uuid = uidLiquidType, amount = 1 } )
											end
										else
											table.insert( incomingObjects, { container = container, uuid = uidLiquidType, amount = 1 } )
										end
									end
								end
							end
						-- elseif type( result ) == "Body" then
						-- 	for _, shape in ipairs( result:getShapes() ) do
						-- 		if shape:getBody():getCreationId() ~= self.shape:getBody():getCreationId() and shape:getBody():isDynamic() then
						-- 			local container = findContainerWithFreeSlots( shape:getShapeUuid(), 1 )
						-- 			if container then
						-- 				table.insert( incomingObjects, { container = container, shape = shape, uuid = shape:getShapeUuid(), amount = 1 } )
						-- 			end
						-- 		end
						-- 	end
						end
					end
				end
			end
		
			if self.sv.canFire then
				for _, incomingObject in ipairs( incomingObjects ) do
					if incomingObject.container then					
						sm.container.beginTransaction()	

						sm.container.collect( incomingObject.container.shape:getInteractable():getContainer(), incomingObject.uuid, incomingObject.amount, true)
						if incomingObject.seedIncomingObj then
							sm.container.collect( incomingObject.seedIncomingObj.container.shape:getInteractable():getContainer(), incomingObject.seedIncomingObj.uuid, incomingObject.seedIncomingObj.amount, true)
						end

						if sm.container.endTransaction() and IsNotInList( incomingObject.Object ) then
							AddToDestroyList( incomingObject.Object )
							
							if incomingObject.withOutSuckEffect ~= nil then
								self.network:sendToClients( "cl_n_onIncomingFire", { shapesOnContainerPath = incomingObject.container.shapesOnContainerPath, item = incomingObject.uuid, withEffect = false } )
							else
								self.network:sendToClients( "cl_n_onIncomingFire", { shapesOnContainerPath = incomingObject.container.shapesOnContainerPath, item = incomingObject.uuid, withEffect = true  } )
							end
											
							if incomingObject.shape then
								incomingObject.shape:destroyShape()
							end
								
							if incomingObject.harvestable then	
								sm.effect.playEffect( "Plants - Picked", sm.harvestable.getPosition( incomingObject.harvestable ) )
								sm.harvestable.create( hvs_soil, sm.harvestable.getPosition( incomingObject.harvestable ), sm.harvestable.getRotation( incomingObject.harvestable ) )
								sm.harvestable.destroy( incomingObject.harvestable )						
							end
								
							if incomingObject.isOil then
								sm.effect.playEffect( "Oilgeyser - Picked", incomingObject.Object.worldPosition )
								sm.harvestable.create( hvs_farmables_growing_oilgeyser,  incomingObject.Object.worldPosition,  incomingObject.Object.worldRotation )
							end
													
							if incomingObject.isFlower then
								sm.effect.playEffect( "Pigmentflower - Picked", incomingObject.Object.worldPosition )
								sm.harvestable.create( hvs_farmables_growing_pigmentflower, incomingObject.Object.worldPosition, incomingObject.Object.worldRotation )
							end
								
							if incomingObject.isCorn then
								sm.effect.playEffect( "Plants - Picked", incomingObject.Object.worldPosition )	
								sm.harvestable.create( hvs_farmables_growing_cornplant, incomingObject.Object.worldPosition, incomingObject.Object.worldRotation )
							end
							
							if incomingObject.isClam then
								sm.effect.playEffect( "SlimyClam - Bubbles", incomingObject.Object.worldPosition )	
								sm.harvestable.create( hvs_farmables_slimyclam_broken, incomingObject.Object.worldPosition, incomingObject.Object.worldRotation )
							end
							
							if incomingObject.isHoney then
								sm.effect.playEffect( "beehive - beeswarm", incomingObject.Object.worldPosition )	
								sm.harvestable.create( hvs_farmables_beehive_broken, incomingObject.Object.worldPosition, incomingObject.Object.worldRotation )
							end
							
							if incomingObject.isCotton then
								sm.effect.playEffect( "Cotton - Picked", incomingObject.Object.worldPosition )	
								sm.harvestable.create( hvs_farmables_growing_cottonplant, incomingObject.Object.worldPosition, incomingObject.Object.worldRotation )
							end

							if incomingObject.isLootCrate then
								sm.effect.playEffect( "LootCrate - Destroy", incomingObject.Object.worldPosition )		
							end
						
							if incomingObject.destroy then						
								sm.harvestable.destroy( incomingObject.Object )
							end
						end
					else
						self.network:sendToClients( "cl_n_onError", { shapesOnContainerPath = self.sv.connectedContainers[1].shapesOnContainerPath } )
					end
				end

				if #incomingObjects == 0 then
					self.network:sendToClients( "cl_n_onError", { shapesOnContainerPath = self.sv.connectedContainers[1].shapesOnContainerPath } )
				end
				self.sv.canFire = false
			end
		end
		
		-- Synch visual feedback
		if #incomingObjects > 0 then

			-- Highlight the longest connection
			local longestConnection = incomingObjects[1].container
			for _, incomingObject in ipairs( incomingObjects ) do
				if #incomingObject.container.shapesOnContainerPath > #longestConnection.shapesOnContainerPath then
					longestConnection = incomingObject.container
				end
			end

			setVacuumState( PipeState.valid, longestConnection.shapesOnContainerPath )
		else
			if self.last_setVacuumStateOnAllShapes ~= PipeState.connected then
				self.last_setVacuumStateOnAllShapes = PipeState.connected 
				setVacuumStateOnAllShapes( PipeState.connected )
			end
		end
	end

	-- Storage table dirty
	if self.sv.dirtyStorageTable then
		self.storage:save( self.sv.storage )
		self.sv.dirtyStorageTable = false
	end

	-- Client table dirty
	if self.sv.dirtyClientTable then
		self.network:setClientData( { mode = self.sv.storage.mode, pipeNetwork = self.sv.client.pipeNetwork, state = self.sv.client.state, showBlockVisualization = self.sv.client.showBlockVisualization } )
		self.sv.dirtyClientTable = false
	end

end



function AddToDestroyList( object )
	if object == nil then
		return false
	end
	if DestroyList == nil then
		DestroyList = {}
	end
	table.insert( DestroyList, { obj = object, time = 1 } )
end

function IsNotInList( object )
	if DestroyList == nil then
		DestroyList = {}
		return true
	end
	if object == nil then
		return false
	end
	if #DestroyList <= 0 then
		return true
	end
	for i = 1, #DestroyList do
		if object == DestroyList[i].obj then
			return false
		end
	end
	return true
end

DestroyLoopRun = nil
DestroyLoopTimer = 0
function DestroyListLoop(self)
	if DestroyLoopRun ~= nil then
		if DestroyLoopRun.shape == nil then
			DestroyLoopRun = nil
		end
		if DestroyLoopRun ~= self then
			return
		end
	else
		DestroyLoopRun = self
	end
	if DestroyLoopRun ~= nil then
		DestroyLoopTimer = DestroyLoopTimer - 0.04
		if DestroyLoopTimer <= 0 then
			DestroyLoopTimer = 1
			DestroyLoopRun = nil
			local cleanTable = {}
			for i = 1, #DestroyList do
				if DestroyList[i] ~= nil then		
					if DestroyList[i].time > 0 then
						DestroyList[i].time = DestroyList[i].time - 0.1
						table.insert(cleanTable, DestroyList[i])
					end
				end
			end
			DestroyList = cleanTable
			if #DestroyList > 0 then
				print("Destroy List Count: " .. tostring(#DestroyList) )
			end
			if #DestroyList <= 0 then
				DestroyLoopRun = nil
			end
		end
	end
	
end

-- Client
function Vacuum.client_onCreate( self )
	self.cl = {}

	-- Update from onClientDataUpdate
	self.cl.mode = VacuumMode.outgoing
	self.cl.pipeNetwork = {}
	self.cl.state = PipeState.off
	self.cl.showBlockVisualization = false

	self.cl.overrideUvFrameIndexTask = nil
	self.cl.poseAnimTask = nil
	self.cl.vacuumEffect = nil

	self.cl.pipeEffectPlayer = PipeEffectPlayer()
	self.cl.pipeEffectPlayer:onCreate()
	
	self.cl.startDelay = 4
end

function Vacuum.client_onClientDataUpdate( self, clientData )
	if #clientData.pipeNetwork > 0 then
		assert( clientData.mode )
		assert( clientData.state )
	end
	self.cl.mode = clientData.mode
	self.cl.pipeNetwork = clientData.pipeNetwork
	self.cl.state = clientData.state
	self.cl.showBlockVisualization = clientData.showBlockVisualization
end



function Shorter( a, b, c, d, e, f )
	if a < b and a < c and a < d and a < e and a < f then
		return true
	end
	return false
end	

function AimAtArrow( self )
	local valid, result = sm.localPlayer.getRaycast( 7 )
	if valid and result then
		local leftDistance = sm.vec3.length( ( self.shape:getWorldPosition() - ( sm.shape.getRight( self.shape ) * 2 ) ) - result.pointWorld )
		local rightDistance = sm.vec3.length( ( self.shape:getWorldPosition() + ( sm.shape.getRight( self.shape ) * 2 ) ) - result.pointWorld )
		local upDistance = sm.vec3.length( ( self.shape:getWorldPosition() + ( sm.shape.getAt( self.shape ) * 2 ) ) - result.pointWorld )
		local downDistance = sm.vec3.length( ( self.shape:getWorldPosition() - ( sm.shape.getAt( self.shape ) * 2 ) ) - result.pointWorld )
		local frontDistance = sm.vec3.length( ( self.shape:getWorldPosition() + ( sm.shape.getUp( self.shape ) * 2 ) ) - result.pointWorld )
		local backDistance = sm.vec3.length( ( self.shape:getWorldPosition() - ( sm.shape.getUp( self.shape ) * 2 ) ) - result.pointWorld )
		if Shorter( leftDistance, rightDistance, upDistance, downDistance, frontDistance, backDistance ) then
			return false
		elseif Shorter( rightDistance, leftDistance, upDistance, downDistance, frontDistance, backDistance ) then
			return false
		elseif Shorter( upDistance, downDistance, leftDistance, rightDistance, frontDistance, backDistance ) then
			return true
		elseif Shorter( downDistance, upDistance, leftDistance, rightDistance, frontDistance, backDistance ) then
			return true
		elseif Shorter( frontDistance, backDistance, leftDistance, rightDistance, upDistance, downDistance ) then
			return true
		elseif Shorter( backDistance, frontDistance, leftDistance, rightDistance, upDistance, downDistance ) then
			return true
		end	
	end		
	return false
end

function Vacuum.client_onInteract( self, character, state )
	if state == true then
		--if AimAtArrow( self ) then
			self.network:sendToServer( "sv_n_toogle" )
		-- else
			-- local gui = sm.gui.createContainerGui( true )
			-- gui:setText( "UpperName", "Vacuumpump Filter" )
			-- gui:setContainer( "UpperGrid", self.filtercontainer )
			-- gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			-- gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			-- gui:open()
		-- end	
	end
end

function Vacuum.client_onUpdate( self, dt )
	if self.cl.startDelay > 0 then
		self.cl.startDelay = self.cl.startDelay  - dt
		return
	end
	-- Update pose anims
	self:cl_updatePoseAnims( dt )

	-- Update Uv Index frames
	self:cl_updateUvIndexFrames( dt )

	-- Update effects through pipes
	self.cl.pipeEffectPlayer:update( dt )

	-- Visualize block if a block is loaded
	if self.cl.state == PipeState.connected and self.cl.showBlockVisualization then
		local valid, gridPos, localNormal, worldPos, obj = self:constructionRayCast()
		if valid then
			local function countTerrain()
				if type(obj) == "Shape" then
					return obj:getBody():isDynamic()
				end
				return false
			end
			sm.visualization.setBlockVisualization(gridPos,
				sm.physics.sphereContactCount( worldPos, sm.construction.constants.subdivideRatio_2, countTerrain() ) > 0 or not sm.construction.validateLocalPosition( blk_cardboard, gridPos, localNormal, obj ),
				obj)
		end
	end
end

-- Events

function Vacuum.cl_n_onOutgoingReload( self, data )
	-- 00Fant
	
	if not data then
		return
	end
	if not data.item then
		return
	end
	if data.item == sm.uuid.getNil() then
		return
	end
	if data.item == tool_gatling then
		return
	end
	if data.item == tool_shotgun then
		return
	end
	if data.item == tool_spudgun then
		return
	end
	if data.item == tool_spudgun_creative then
		return
	end
	if data.item == tool_weld then
		return
	end
	if data.item == tool_paint then
		return
	end
	if data.item == tool_connect then
		return
	end
	if data.item == tool_lift then
		return
	end
	if data.item == tool_sledgehammer then
		return
	end
	
	--print(data.item)
	-- 00Fant
	local shapeList = {}
	for idx, shape in reverse_ipairs( data.shapesOnContainerPath ) do
		table.insert( shapeList, shape )
	end
	table.insert( shapeList, self.shape )

	self.cl.pipeEffectPlayer:pushShapeEffectTask( shapeList, data.item )

	self:cl_setOverrideUvIndexFrame( shapeList, PipeState.valid )
end

function Vacuum.cl_n_onOutgoingFire( self, data )
	local shapeList = data.shapesOnContainerPath
	if shapeList then
		table.insert( shapeList, self.shape )
	end		

	self:cl_setOverrideUvIndexFrame( shapeList, PipeState.valid )
	self:cl_setPoseAnimTask( "outgoingFire" )
	if data.withoutEffect == nil or data.withoutEffect == false then
		self.cl.vacuumEffect = sm.effect.createEffect( "Vacuumpipe - Blowout", self.interactable )
		self.cl.vacuumEffect:setOffsetRotation( sm.quat.angleAxis( math.pi*0.5, sm.vec3.new( 1, 0, 0 ) ) )
		self.cl.vacuumEffect:start()
	end
end

function Vacuum.cl_n_onIncomingFire( self, data )

	table.insert( data.shapesOnContainerPath, 1, self.shape )

	self.cl.pipeEffectPlayer:pushShapeEffectTask( data.shapesOnContainerPath, data.item )

	self:cl_setOverrideUvIndexFrame( data.shapesOnContainerPath, PipeState.valid )
	self:cl_setPoseAnimTask( "incomingFire" )
	if data.withEffect then
		self.cl.vacuumEffect = sm.effect.createEffect( "Vacuumpipe - Suction", self.interactable )
		self.cl.vacuumEffect:setOffsetRotation( sm.quat.angleAxis( math.pi*0.5, sm.vec3.new( 1, 0, 0 ) ) )
		self.cl.vacuumEffect:start()
	end
end

function Vacuum.cl_n_onError( self, data )
	self:cl_setOverrideUvIndexFrame( data.shapesOnContainerPath, PipeState.invalid )
end

-- State sets

function Vacuum.cl_pushEffectTask( self, shapeList, effect )
	self.cl.pipeEffectPlayer:pushEffectTask( shapeList, effect )
end

function Vacuum.cl_setOverrideUvIndexFrame( self, shapeList, state )
	local shapeMap = {}
	if shapeList then
		for _, shape in ipairs( shapeList ) do
			shapeMap[shape:getId()] = state
		end
	end
	self.cl.overrideUvFrameIndexTask = { shapeMap = shapeMap, state = state, progress = 0 }
end

function Vacuum.cl_setPoseAnimTask( self, name )
	self.cl.poseAnimTask = { name = name, progress = 0 }
end

-- Updates

PoseCurves = {}
PoseCurves["outgoingFire"] = Curve()
PoseCurves["outgoingFire"]:init({{v=0.5, t=0.0},{v=1.0, t=0.1},{v=0.5, t=0.2},{v=0.0, t=0.3},{v=0.5, t=0.6}})

PoseCurves["incomingFire"] = Curve()
PoseCurves["incomingFire"]:init({{v=0.5, t=0.0},{v=0.0, t=0.1},{v=0.5, t=0.2},{v=1.0, t=0.3},{v=0.5, t=0.6}})

function Vacuum.cl_updatePoseAnims( self, dt )

	if self.cl.poseAnimTask then

		self.cl.poseAnimTask.progress = self.cl.poseAnimTask.progress + dt

		local curve = PoseCurves[self.cl.poseAnimTask.name]
		if curve then
			self.shape:getInteractable():setPoseWeight( 0, curve:getValue( self.cl.poseAnimTask.progress ) )

			if self.cl.poseAnimTask.progress > curve:duration() then
				self.cl.poseAnimTask = nil
			end
		else
			self.cl.poseAnimTask = nil
		end
	end

end

local GlowCurve = Curve()
GlowCurve:init({{v=1.0, t=0.0}, {v=0.5, t=0.05}, {v=0.0, t=0.1}, {v=0.5, t=0.3}, {v=1.0, t=0.4}, {v=0.5, t=0.5}, {v=0.0, t=0.7}, {v=0.5, t=0.75}, {v=1.0, t=0.8}})

function Vacuum.cl_updateUvIndexFrames( self, dt )

	local glowMultiplier = 1.0

	-- Events allow for overriding the uv index frames, time it out
	if self.cl.overrideUvFrameIndexTask then
		self.cl.overrideUvFrameIndexTask.progress = self.cl.overrideUvFrameIndexTask.progress + dt

		glowMultiplier = GlowCurve:getValue( self.cl.overrideUvFrameIndexTask.progress )

		if self.cl.overrideUvFrameIndexTask.progress > 0.1 then

			self.cl.overrideUvFrameIndexTask.change = true
		end

		if self.cl.overrideUvFrameIndexTask.progress > 0.7 then

			self.cl.overrideUvFrameIndexTask.change = false
		end

		if self.cl.overrideUvFrameIndexTask.progress > GlowCurve:duration() then

			self.cl.overrideUvFrameIndexTask = nil
		end
	end

	-- Light up vacuum
	local state = self.cl.state
	if self.cl.overrideUvFrameIndexTask and self.cl.overrideUvFrameIndexTask.change == true then
		state = self.cl.overrideUvFrameIndexTask.state
	end

	VacuumFrameIndexTable = {
		[VacuumMode.outgoing] = {
			[PipeState.off] = 0,
			[PipeState.invalid] = 1,
			[PipeState.connected] = 2,
			[PipeState.valid] = 4
		},
		[VacuumMode.incoming] = {
			[PipeState.off] = 0,
			[PipeState.invalid] = 1,
			[PipeState.connected] = 3,
			[PipeState.valid] = 5
		}
	}
	assert( self.cl.mode > 0 and self.cl.mode <= 2 )
	assert( state > 0 and state <= 4 )
	local vacuumFrameIndex = VacuumFrameIndexTable[self.cl.mode][state]
	self.interactable:setUvFrameIndex( vacuumFrameIndex )
	if self.cl.overrideUvFrameIndexTask then
		self.interactable:setGlowMultiplier( glowMultiplier )
	else
		self.interactable:setGlowMultiplier( 1.0 )
	end

	local function fnOverride( pipe )

		local state = pipe.state
		local glow = 1.0

		if self.cl.overrideUvFrameIndexTask then
			local overrideState = self.cl.overrideUvFrameIndexTask.shapeMap[pipe.shape:getId()]
			if overrideState then
				if self.cl.overrideUvFrameIndexTask.change == true then
					state = overrideState
				end
				glow = glowMultiplier
			end
		end

		return state, glow
	end

	-- Light up pipes
	LightUpPipes( self.cl.pipeNetwork, fnOverride )
end