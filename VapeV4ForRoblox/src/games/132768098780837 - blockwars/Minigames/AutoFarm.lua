local AutoFarm
local FlySpeed
local BedHeight
local StopDistance
local AntiSuffocate
local restore = {}
local target
local phase
local overlapCheck = OverlapParams.new()

local function isEnemyBed(bed)
	return bed:GetAttribute('BedTeamId') ~= (lplr.Team and lplr.Team.Name or '')
end

local function isBroken(bed)
	return not bed.Parent or (bed:GetAttribute('HP') or 10) <= 0
end

-- Nearest enemy bed still standing. Mirrors the checks Breaker uses, so we
-- only ever fly at something it will actually hit.
local function nearestBed(beds, position)
	local best, bestdist
	for _, v in beds do
		if not isEnemyBed(v) or isBroken(v) then continue end

		local dist = (v.Position - position).Magnitude
		if not bestdist or dist < bestdist then
			best, bestdist = v, dist
		end
	end
	return best
end

-- Flying by CFrame walks straight through geometry, and stopping inside a
-- block is what suffocates you. Rise until nothing solid overlaps the root.
local function stuck(root)
	if not AntiSuffocate.Enabled then return false end
	overlapCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	for _, part in workspace:GetPartsInPart(root, overlapCheck) do
		if part.CanCollide then return true end
	end
	return false
end

local function flyTo(goal, dt)
	local root = entitylib.character.RootPart
	root.AssemblyLinearVelocity = Vector3.zero

	if stuck(root) then
		root.CFrame += Vector3.new(0, FlySpeed.Value * dt, 0)
		return
	end

	local delta = goal - root.Position
	if delta.Magnitude < 0.1 then return end
	root.CFrame += delta.Unit * math.min(FlySpeed.Value * dt, delta.Magnitude)
end

-- Breaker bails out while isAttacking is set, and Killaura sets it for anything
-- within attack range -- so running both at once means a defended bed never
-- breaks. Only one of them is live at a time.
local function setEnabled(module, wanted)
	if module and module.Enabled ~= wanted then
		module:Toggle()
	end
end

AutoFarm = vape.Categories.Minigames:CreateModule({
	Name = 'AutoFarm',
	Function = function(callback)
		if callback then
			table.clear(restore)
			for _, module in {AnticheatBypass, Breaker, Killaura} do
				if module then
					restore[module] = module.Enabled
				end
			end
			setEnabled(AnticheatBypass, true)

			local beds = collection('BedWarsX_BedSpawn', AutoFarm)
			target = nil

			AutoFarm:Clean(runService.PreSimulation:Connect(function(dt)
				if not entitylib.isAlive then
					phase, target = nil, nil
					return
				end
				local position = entitylib.character.RootPart.Position

				-- Stay on one bed until it is actually down, otherwise drifting
				-- closer to a second bed pulls us off a half broken one.
				if target and (isBroken(target) or not isEnemyBed(target)) then
					target = nil
				end
				target = target or nearestBed(beds, position)

				if target then
					phase = 'Beds'
					setEnabled(Killaura, false)
					setEnabled(Breaker, true)
					-- Sit above the bed rather than inside the defence, which
					-- keeps Breaker's line of sight pointed down at the cover.
					flyTo(target.Position + Vector3.new(0, BedHeight.Value, 0), dt)
					return
				end

				phase = 'Players'
				setEnabled(Breaker, false)
				setEnabled(Killaura, true)

				local enemy = entitylib.EntityPosition({
					Range = math.huge,
					Part = 'RootPart',
					Players = true,
					NPCs = true
				})
				if not enemy then return end

				local goal = enemy.RootPart.Position
				if (goal - position).Magnitude > StopDistance.Value then
					flyTo(goal, dt)
				else
					entitylib.character.RootPart.AssemblyLinearVelocity = Vector3.zero
				end
			end))
		else
			for module, wasEnabled in restore do
				setEnabled(module, wasEnabled)
			end
			table.clear(restore)
			phase, target = nil, nil
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
AntiSuffocate = AutoFarm:CreateToggle({
	Name = 'Anti Suffocate',
	Default = true,
	Tooltip = 'Rise out of any block the flight path ends up inside of'
})
