-- ConsumableContainer.lua --

dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"

ConsumableContainer = class( nil )
ConsumableContainer.maxChildCount = 255

local ContainerSize = 5

function ConsumableContainer.server_onCreate( self )

	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, ContainerSize, self.data.stackSize )
	end
	if self.data.filterUid then
		local filters = { sm.uuid.new( self.data.filterUid ) }
		container:setFilters( filters )
	end	
end

function ConsumableContainer.client_canCarry( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container and sm.exists( container ) then
		return not container:isEmpty()
	end
	return false
end

function ConsumableContainer.client_onInteract( self, character, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			local gui = nil
			
			local shapeUuid = self.shape:getShapeUuid()
			
			if shapeUuid == obj_container_ammo then
				gui = sm.gui.createAmmunitionContainerGui( true )
				
			elseif shapeUuid == obj_container_battery then
				gui = sm.gui.createBatteryContainerGui( true )
				
			elseif shapeUuid == obj_container_chemical then
				gui = sm.gui.createChemicalContainerGui( true )
				
			elseif shapeUuid == obj_container_fertilizer then
				gui = sm.gui.createFertilizerContainerGui( true )
				
			elseif shapeUuid == obj_container_gas then
				gui = sm.gui.createGasContainerGui( true )
				
			elseif shapeUuid == obj_container_seed then
				gui = sm.gui.createSeedContainerGui( true )
				
			elseif shapeUuid == obj_container_water then
				gui = sm.gui.createWaterContainerGui( true )
			end
			
			if gui == nil then
				gui = sm.gui.createContainerGui( true )
				gui:setText( "UpperName", "#{CONTAINER_TITLE_GENERIC}" )
			end
			
			gui:setContainer( "UpperGrid", container )
			gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			gui:open()
		end
	end	
end

function ConsumableContainer.client_onUpdate( self, dt )
	local parents = self.shape:getInteractable():getParents()
	local container = self.shape.interactable:getContainer( 0 )
	if container then
		local quantities = sm.container.quantity( container )
		
		local quantity = 0
		--print( parents )
		if #parents > 0 then
			--quantity = self.Air / 20
		else
			for _,q in ipairs(quantities) do
				quantity = quantity + q
			end
		end
		local frame = ContainerSize - math.ceil( quantity / self.data.stackSize )
		self.interactable:setUvFrameIndex( frame )
	end
end	

SeedContainer = class( ConsumableContainer )
SeedContainer.connectionOutput = sm.interactable.connectionType.water  
SeedContainer.colorNormal = sm.color.new( 0x84ff32ff )
SeedContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

function SeedContainer.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container =	self.shape:getInteractable():addContainer( 0, 5, 65535 )
	end
	local filter = sm.item.getPlantableUuids()
	table.insert( filter, sm.uuid.new( "44b03130-28c6-4060-903f-9a96fb7f7fe0" ) )
	container:setFilters( sm.item.getPlantableUuids() )
end




FertilizerContainer = class( ConsumableContainer )
FertilizerContainer.connectionOutput = sm.interactable.connectionType.water  
FertilizerContainer.colorNormal = sm.color.new( 0x84ff32ff )
FertilizerContainer.colorHighlight = sm.color.new( 0xa7ff4fff )


WaterContainer = class( ConsumableContainer )
WaterContainer.maxParentCount = 1
WaterContainer.connectionInput = sm.interactable.connectionType.power  
WaterContainer.connectionOutput = sm.interactable.connectionType.water
WaterContainer.colorNormal = sm.color.new( 0x84ff32ff )
WaterContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

WaterContainer.Air = 0
WaterContainer.LastAir = 0
WaterContainer.AirRefrehRate = 10
WaterContainer.AirConsumRate = 1
WaterContainer.areaTrigger = nil
WaterContainer.seatedCharacter = nil
WaterContainer.timer = 0

function WaterContainer.IsInWater(self)
	if not self.areaTrigger then
		self.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, sm.vec3.new( 0.25, 0.25, 0.25 ), sm.vec3.new(0.0, 0, 0.0), sm.quat.identity(), sm.areaTrigger.filter.all )		
	end
	for _, result in ipairs(  self.areaTrigger:getContents() ) do
		if sm.exists( result ) then
			if type( result ) == "AreaTrigger" then
				local userData = result:getUserData()
				if userData and userData.water == true then
					return true
				end
			end
		end
	end
	return false
end

function WaterContainer.server_onFixedUpdate( self, timeStep )
	self.timer = self.timer + 1
	if self.timer >= 40 then
		self.timer = 0
	else
		return
	end
	
	
	local parent = self.shape:getInteractable():getSingleParent()
	if parent then
		local InWater =  self.IsInWater(self)
		if InWater and self.Air > 0 then
			if parent:isActive() then
				self.Air = self.Air - ( self.AirConsumRate )
				if  self.Air < 0 then
					self.Air = 0
				end
				 self.seatedCharacter = parent.shape:getInteractable():getSeatCharacter()
				if self.seatedCharacter then
					sm.event.sendToPlayer( self.seatedCharacter:getPlayer(), "sv_e_debug", { breath = 100 } )
				end
			end		
		end
		if not InWater and self.Air < 100 then
			self.Air = self.Air + ( self.AirRefrehRate )
			if  self.Air > 100 then
				self.Air = 100
			end
		end	
		-- if self.LastAir ~= self.Air then
			-- self.LastAir = self.Air 
			-- self.network:sendToClients( "setAir", self.Air )
		-- end
	end	
end

function WaterContainer.setAir( self, air )
	self.Air = air
end

function WaterContainer.client_onUpdate( self, dt )
	local parents = self.shape:getInteractable():getParents()
	if #parents > 0 then
		local seatedCharacter = nil
		local frame = 5 - ( self.Air / 20 ) 
		self.interactable:setUvFrameIndex( frame )			
		for _, parent in ipairs( parents ) do					
			if parent then
				if parent.shape then
					seatedCharacter = parent.shape:getInteractable():getSeatCharacter()
					break
				end
			end
		end		
		if seatedCharacter then
			if seatedCharacter:getPlayer() and seatedCharacter:getPlayer():getId() == sm.localPlayer.getId() then
				if seatedCharacter and not self.seatedCharacter then
					self.seatedCharacter = seatedCharacter
				end				
			end
		else
			if not seatedCharacter and self.seatedCharacter then
				self.seatedCharacter = nil
			end			
		end	
	else
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			local quantities = sm.container.quantity( container )
			local quantity = 0
			for _,q in ipairs(quantities) do
				quantity = quantity + q
			end
			local frame = ContainerSize - math.ceil( quantity / self.data.stackSize )
			self.interactable:setUvFrameIndex( frame )
		end
	end
end	

ChemicalContainer = class( ConsumableContainer )
ChemicalContainer.connectionOutput = sm.interactable.connectionType.water
ChemicalContainer.colorNormal = sm.color.new( 0x84ff32ff )
ChemicalContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

BatteryContainer = class( ConsumableContainer )
BatteryContainer.connectionOutput = sm.interactable.connectionType.electricity
BatteryContainer.colorNormal = sm.color.new( 0x84ff32ff )
BatteryContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

GasolineContainer = class( ConsumableContainer )
GasolineContainer.connectionOutput = sm.interactable.connectionType.gasoline
GasolineContainer.colorNormal = sm.color.new( 0x84ff32ff )
GasolineContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

AmmoContainer = class( ConsumableContainer )
AmmoContainer.connectionOutput = sm.interactable.connectionType.ammo
AmmoContainer.colorNormal = sm.color.new( 0x84ff32ff )
AmmoContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

FoodContainer = class( ConsumableContainer )

local FoodUuids = {
	obj_plantables_banana,
	obj_plantables_blueberry,
	obj_plantables_orange,
	obj_plantables_pineapple,
	obj_plantables_carrot,
	obj_plantables_redbeet,
	obj_plantables_tomato,
	obj_plantables_broccoli,
	obj_plantables_potato,
	obj_consumable_sunshake,
	obj_consumable_carrotburger,
	obj_consumable_pizzaburger,
	obj_consumable_longsandwich,
	obj_consumable_milk,
	obj_resource_steak,
	obj_resource_corn,
	obj_consumable_fant_redwoc,
	obj_consumable_fant_steak,
	obj_consumable_fant_totebots,
	obj_consumable_fant_fries
}

function FoodContainer.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container =	self.shape:getInteractable():addContainer( 0, 20, 65535 )
	end
	container:setFilters( FoodUuids )
end

FoodContainer.client_onUpdate = nil

ExplosiveAmmoContainer = class( ConsumableContainer )
ExplosiveAmmoContainer.connectionOutput = sm.interactable.connectionType.ammo
ExplosiveAmmoContainer.colorNormal = sm.color.new( 0x84ff32ff )
ExplosiveAmmoContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

function ExplosiveAmmoContainer.server_onCreate( self )

	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, 30, self.data.stackSize )
	end
	if self.data.filterUid then
		local filters = { sm.uuid.new( self.data.filterUid ), sm.uuid.new( self.data.filterUid2 ) }
		container:setFilters( filters )
	end	
end


function ExplosiveAmmoContainer.client_onUpdate( self, dt )
	local parents = self.shape:getInteractable():getParents()
	local container = self.shape.interactable:getContainer( 0 )
	if container then
		local quantities = sm.container.quantity( container )
		local quantity = 0
		--print( parents )
		if #parents > 0 then
			--quantity = self.Air / 20
		else
			for _,q in ipairs(quantities) do
				quantity = quantity + q
			end
		end
		
		local frame = 5 - math.ceil( ((quantity/30)*50) / 10 )
		self.interactable:setUvFrameIndex( frame )
	end
end	

