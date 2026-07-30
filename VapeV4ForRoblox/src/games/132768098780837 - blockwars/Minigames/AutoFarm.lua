local AutoFarm
local FlySpeed
local BedHeight
local StopDistance
local Defend
local DefendHealth
local AntiSuffocate
local AutoReset
local StuckTime
local restore = {}
local clipped = {}
local target
local phase
local closest, progressed
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

local function healthPercent()
	local humanoid = entitylib.character.Humanoid
	return humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) * 100 or 100
end

-- Nothing to collide with means nothing to get wedged in, which is most of the
-- stuck problem. Only parts that were solid get recorded, so putting them back
-- is just setting them true again.
local function noclip()
	local character = lplr.Character
	if not character then return end
	for _, part in character:GetDescendants() do
		if part:IsA('BasePart') and part.CanCollide then
			clipped[part] = true
			part.CanCollide = false
		end
	end
end

local function unclip()
	for part in clipped do
		if part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(clipped)
end

-- Noclip stops us snagging on geometry but not from parking inside a block,
-- and that is what suffocates. Rise until nothing solid overlaps the root.
local function buried(root)
	if not AntiSuffocate.Enabled then return false end
	overlapCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	for _, part in workspace:GetPartsInPart(root, overlapCheck) do
		if part.CanCollide then return true end
	end
	return false
end

local function resetProgress()
	closest, progressed = nil, os.clock()
end

-- Dying respawns us at base, which unwedges anything geometry related. But with
-- our own bed gone a death is elimination, so that case has to ride it out.
local function checkStuck(distance, beds)
	if not AutoReset.Enabled then return end

	if distance < 2 then
		resetProgress()
		return
	end
	if not closest or distance < closest - 1 then
		closest, progressed = distance, os.clock()
		return
	end
	if (os.clock() - progressed) < StuckTime.Value then return end

	resetProgress()
	for _, v in beds do
		if not isEnemyBed(v) and not isBroken(v) then
			entitylib.character.Humanoid.Health = 0
			return
		end
	end
end

local function flyTo(goal, dt)
	local root = entitylib.character.RootPart
	root.AssemblyLinearVelocity = Vector3.zero

	if buried(root) then
		root.CFrame += Vector3.new(0, FlySpeed.Value * dt, 0)
		return
	end

	local delta = goal - root.Position
	if delta.Magnitude < 0.1 then return end
	root.CFrame += delta.Unit * math.min(FlySpeed.Value * dt, delta.Magnitude)
end

-- Breaker bails out while isAttacking is set, and Killaura sets it for anything
-- within attack range, so the two cannot usefully run together.
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
			resetProgress()

			AutoFarm:Clean(runService.PreSimulation:Connect(function(dt)
				if not entitylib.isAlive then
					phase, target = nil, nil
					resetProgress()
					return
				end
				noclip()
				local position = entitylib.character.RootPart.Position

				-- Stay on one bed until it is actually down, otherwise drifting
				-- closer to a second bed pulls us off a half broken one.
				if target and (isBroken(target) or not isEnemyBed(target)) then
					target = nil
					resetProgress()
				end
				if not target then
					local found = nearestBed(beds, position)
					if found ~= target then
						resetProgress()
					end
					target = found
				end

				if target then
					-- Swinging back only while actually being hurt, so a healthy
					-- run never stops breaking to trade with a defender.
					local hurt = Defend.Enabled and healthPercent() < DefendHealth.Value
					phase = hurt and 'Defending' or 'Beds'
					setEnabled(Breaker, not hurt)
					setEnabled(Killaura, hurt)

					-- Sit above the bed rather than inside the defence, which
					-- keeps Breaker's line of sight pointed down at the cover.
					local goal = target.Position + Vector3.new(0, BedHeight.Value, 0)
					checkStuck((goal - position).Magnitude, beds)
					flyTo(goal, dt)
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
				if not enemy then
					resetProgress()
					return
				end

				local goal = enemy.RootPart.Position
				local distance = (goal - position).Magnitude
				if distance > StopDistance.Value then
					checkStuck(distance, beds)
					flyTo(goal, dt)
				else
					resetProgress()
					entitylib.character.RootPart.AssemblyLinearVelocity = Vector3.zero
				end
			end))
		else
			unclip()
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
	Default = 30,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'Past about 37 the bypass cannot keep up and you get set back.\nRaise AnticheatBypass Chase Speed first if you want to go faster.'
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
Defend = AutoFarm:CreateToggle({
	Name = 'Fight back',
	Default = true,
	Function = function(callback)
		if DefendHealth then
			DefendHealth.Object.Visible = callback
		end
	end,
	Tooltip = 'Stop breaking and swing back once your health drops'
})
DefendHealth = AutoFarm:CreateSlider({
	Name = 'Fight back at',
	Min = 1,
	Max = 100,
	Default = 50,
	Darker = true,
	Suffix = '% health'
})
AntiSuffocate = AutoFarm:CreateToggle({
	Name = 'Anti Suffocate',
	Default = true,
	Tooltip = 'Rise out of any block the flight path ends up inside of'
})
AutoReset = AutoFarm:CreateToggle({
	Name = 'Auto reset',
	Default = true,
	Function = function(callback)
		if StuckTime then
			StuckTime.Object.Visible = callback
		end
	end,
	Tooltip = 'Respawn when the flight stops making progress.\nSkipped when your own bed is gone, since dying then is elimination.'
})
StuckTime = AutoFarm:CreateSlider({
	Name = 'Reset after',
	Min = 1,
	Max = 15,
	Default = 5,
	Darker = true,
	Suffix = function(val)
		return val == 1 and 'second' or 'seconds'
	end
})
