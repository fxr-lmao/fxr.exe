local Breaker
local Range
local BreakSpeed
local UpdateRate
local Custom
local Bed
local LuckyBlock
local IronOre
local Effect
local CustomHealth = {}
local Animation
local SelfBreak
local InstantBreak
local LimitItem
local customlist, parts = {}, {}

local function getPick()
	local inv = getInventory()
	for _, tool in inv do
		if tool:GetAttribute('Tier') then
			return tool
		end
	end
end

local rayCheck = RaycastParams.new()

-- The server only accepts a hit it can trace from camPos, so a bed buried under a
-- defence has to be dug out one layer at a time. Walk the line of sight and return
-- the outermost placed block standing in the way, or nil for a clear shot at the bed.
local function getCoveringBlock(bed, localPosition)
	local ignore = {lplr.Character, gameCamera}
	local dest = bed:GetClosestPointOnSurface(localPosition)

	for _ = 1, 10 do
		rayCheck.FilterDescendantsInstances = ignore
		local ray = workspace:Raycast(localPosition, dest - localPosition, rayCheck)
		if not ray or ray.Instance == bed then return end
		if ray.Instance:HasTag('BedWarsX_PlacedBlock') then
			return ray.Instance
		end

		-- Decorations and players are not worth breaking, look past them
		table.insert(ignore, ray.Instance)
	end
end

local function attemptBreak(tab, localPosition, tool)
	if not tab then return end
	for _, v in tab do
		if (v.Position - localPosition).Magnitude < Range.Value and v:GetAttribute('BedTeamId') ~= (lplr.Team and lplr.Team.Name or '') and (v:GetAttribute('HP') or 10) > 0 then
			if tool.Parent ~= lplr.Character then
				entitylib.character.Humanoid:EquipTool(tool)
			end

			if v:HasTag('BedWarsX_BedSpawn') then
				local target = getCoveringBlock(v, localPosition) or v
				bw.RemoteIndex.Block_AttemptHit:FireServer({
					camPos = localPosition,
					hitPos = target:GetClosestPointOnSurface(localPosition),
					blockInstance = target
				})

				task.wait(BreakSpeed.Value)
			else
				bw.RemoteIndex.Mine_AttemptHit:FireServer(v)
			end

			task.wait(0.05)
			return true
		end
	end

	return false
end

Breaker = vape.Categories.Minigames:CreateModule({
	Name = 'Breaker',
	Function = function(callback)
		if callback then
			local beds = collection('BedWarsX_BedSpawn', Breaker)
			local generators = collection('BedWarsX_Resource', Breaker)

			repeat
				task.wait(1 / UpdateRate.Value)
				if not Breaker.Enabled then break end

				local tool = getPick()
				if entitylib.isAlive and tool and not isAttacking then
					local localPosition = bypassRoot and bypassRoot.Position or entitylib.character.RootPart.Position

					if attemptBreak(beds, localPosition, tool) then continue end
					if attemptBreak(generators, localPosition, tool) then continue end
				end
			until not Breaker.Enabled
		end
	end,
	Tooltip = 'Break blocks around you automatically'
})
Range = Breaker:CreateSlider({
	Name = 'Break range',
	Min = 1,
	Max = 12,
	Default = 12,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end
})
BreakSpeed = Breaker:CreateSlider({
	Name = 'Break speed',
	Min = 0,
	Max = 0.3,
	Default = 0.15,
	Decimal = 100,
	Suffix = 'seconds',
	Tooltip = 'Delay between hits on a bed. Lower is faster, but the server drops hits that arrive too quickly.'
})
UpdateRate = Breaker:CreateSlider({
	Name = 'Update rate',
	Min = 1,
	Max = 120,
	Default = 60,
	Suffix = 'hz'
})