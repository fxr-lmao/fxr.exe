local AutoFarm
local FlySpeed
local BedHeight
local StopDistance
local borrowed = {}
local phase

-- Nearest enemy bed still standing. Mirrors the ownership and HP checks
-- Breaker uses, so we only ever fly at something it will actually hit.
local function nearestBed(beds, position)
	local best, bestdist
	for _, v in beds do
		if v:GetAttribute('BedTeamId') == (lplr.Team and lplr.Team.Name or '') then continue end
		if (v:GetAttribute('HP') or 10) <= 0 then continue end

		local dist = (v.Position - position).Magnitude
		if not bestdist or dist < bestdist then
			best, bestdist = v, dist
		end
	end
	return best
end

local function flyTo(goal, dt)
	local root = entitylib.character.RootPart
	local delta = goal - root.Position
	root.AssemblyLinearVelocity = Vector3.zero
	if delta.Magnitude < 0.1 then return end
	root.CFrame += delta.Unit * math.min(FlySpeed.Value * dt, delta.Magnitude)
end

AutoFarm = vape.Categories.Minigames:CreateModule({
	Name = 'AutoFarm',
	Function = function(callback)
		if callback then
			-- Breaker and Killaura already do the damage, this only does the
			-- travelling. Remember which ones we switched on so we can put
			-- them back the way we found them.
			table.clear(borrowed)
			for _, module in {AnticheatBypass, Breaker, Killaura} do
				if module and not module.Enabled then
					module:Toggle()
					table.insert(borrowed, module)
				end
			end

			local beds = collection('BedWarsX_BedSpawn', AutoFarm)

			AutoFarm:Clean(runService.PreSimulation:Connect(function(dt)
				if not entitylib.isAlive then
					phase = nil
					return
				end
				local position = entitylib.character.RootPart.Position

				local bed = nearestBed(beds, position)
				if bed then
					-- Sit above the bed rather than inside the defence, which
					-- keeps Breaker's line of sight pointed down at the cover.
					phase = 'Beds'
					flyTo(bed.Position + Vector3.new(0, BedHeight.Value, 0), dt)
					return
				end

				phase = 'Players'
				local target = entitylib.EntityPosition({
					Range = math.huge,
					Part = 'RootPart',
					Players = true,
					NPCs = true
				})
				if not target then return end

				local goal = target.RootPart.Position
				if (goal - position).Magnitude > StopDistance.Value then
					flyTo(goal, dt)
				else
					entitylib.character.RootPart.AssemblyLinearVelocity = Vector3.zero
				end
			end))
		else
			for _, module in borrowed do
				if module.Enabled then
					module:Toggle()
				end
			end
			table.clear(borrowed)
			phase = nil
		end
	end,
	ExtraText = function()
		return phase
	end,
	Tooltip = 'Flies to every enemy bed and breaks it, then hunts down whoever is left.'
})
FlySpeed = AutoFarm:CreateSlider({
	Name = 'Fly speed',
	Min = 1,
	Max = 150,
	Default = 60,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'Raise AnticheatBypass Chase Speed to match, or the fake root falls behind and you get set back'
})
BedHeight = AutoFarm:CreateSlider({
	Name = 'Bed height',
	Min = 1,
	Max = 30,
	Default = 10,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'How far above a bed to hover while Breaker digs it out'
})
StopDistance = AutoFarm:CreateSlider({
	Name = 'Player distance',
	Min = 1,
	Max = 13,
	Default = 8,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'How close to close in on a player, keep it inside Killaura attack range'
})
