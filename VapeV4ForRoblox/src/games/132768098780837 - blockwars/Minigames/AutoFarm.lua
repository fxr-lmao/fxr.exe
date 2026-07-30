local AutoFarm
local FlySpeed
local BedHeight
local StopDistance
local Clearance
local Shop
local ShopTime
local AntiSuffocate
local AutoReset
local StuckTime
local restore = {}
local clipped = {}
local target
local shopUntil
local phase
local closest, progressed
local cruise
local overlapCheck = OverlapParams.new()
local pathCheck = RaycastParams.new()
pathCheck.RespectCanCollide = true

-- How far above a goal the router is allowed to climb before it admits the
-- route is hopeless and lets the stuck timer respawn us.
local CEILING = 300

local function isEnemyBed(bed)
	return bed:GetAttribute('BedTeamId') ~= (lplr.Team and lplr.Team.Name or '')
end

local function isBroken(bed)
	return not bed.Parent or (bed:GetAttribute('HP') or 10) <= 0
end

local function liveEnemyBed(bed)
	return isEnemyBed(bed) and not isBroken(bed)
end

local function nearest(list, position, filter)
	local best, bestdist
	for _, v in list do
		if filter and not filter(v) then continue end

		local dist = (v.Position - position).Magnitude
		if not bestdist or dist < bestdist then
			best, bestdist = v, dist
		end
	end
	return best
end

local function blocked(from, to)
	pathCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	return workspace:Raycast(from, to - from, pathCheck) ~= nil
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

local function insideBlock(root)
	if not AntiSuffocate.Enabled then return false end
	overlapCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	for _, part in workspace:GetPartsInPart(root, overlapCheck) do
		if part.CanCollide then return true end
	end
	return false
end

-- Timer only. Called whenever the router is doing something deliberate, so
-- climbing or re-planning never reads as being stuck.
local function madeProgress()
	progressed = os.clock()
end

-- Full reset, for when the destination changes and the old route is meaningless.
local function resetRoute()
	closest, progressed, cruise = nil, os.clock(), nil
end

-- Dying respawns us at base, which unwedges anything geometry related. But with
-- our own bed gone a death is elimination, so that case has to ride it out.
local function checkStuck(distance, beds)
	if not AutoReset.Enabled then return end

	if distance < 2 then
		madeProgress()
		return
	end
	if not closest or distance < closest - 1 then
		closest, progressed = distance, os.clock()
		return
	end
	if (os.clock() - progressed) < StuckTime.Value then return end

	resetRoute()
	for _, v in beds do
		if not isEnemyBed(v) and not isBroken(v) then
			entitylib.character.Humanoid.Health = 0
			return
		end
	end
end

-- Straight lines walk into buildings. Climb above whatever is in the way, cross
-- at that height, then drop onto the goal -- and if the lane at cruise height is
-- still solid, go higher and try again.
local function flyTo(goal, dt)
	local root = entitylib.character.RootPart
	local step = FlySpeed.Value * dt
	root.AssemblyLinearVelocity = Vector3.zero

	-- Rise out of anything solid we are sitting in, but keep travelling while
	-- doing it. Returning here is what turned a ceiling into an endless climb.
	if insideBlock(root) then
		root.CFrame += Vector3.new(0, step, 0)
		madeProgress()
	end

	local position = root.Position
	local delta = goal - position
	if delta.Magnitude < 0.1 then
		cruise = nil
		return
	end

	-- Clear line of sight, and not already committed to a route.
	if not cruise and not blocked(position, goal) then
		root.CFrame += delta.Unit * math.min(step, delta.Magnitude)
		return
	end

	cruise = cruise or math.max(position.Y, goal.Y) + Clearance.Value

	if position.Y < cruise - 1 then
		root.CFrame += Vector3.new(0, math.min(step, cruise - position.Y), 0)
		madeProgress()
		return
	end

	local flat = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
	if flat.Magnitude > 2 then
		local ahead = position + flat.Unit * math.min(flat.Magnitude, 12)
		if blocked(position, ahead) then
			-- Not high enough yet. Past the ceiling stop bumping it and stop
			-- feeding the timer, so auto reset takes over instead of looping.
			if cruise < goal.Y + CEILING then
				cruise += Clearance.Value
				madeProgress()
			end
			return
		end
		root.CFrame += flat.Unit * math.min(step, flat.Magnitude)
		return
	end

	-- Over the goal now, drop onto it.
	root.CFrame += delta.Unit * math.min(step, delta.Magnitude)
	if delta.Magnitude < 2 then
		cruise = nil
	end
end

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
			for _, module in {AnticheatBypass, Breaker, Killaura, AutoBuy} do
				if module then
					restore[module] = module.Enabled
				end
			end
			-- Killaura stays on for the whole run. Breaker already stands down
			-- on its own while isAttacking is set, so the two share the bed
			-- phase instead of taking turns, and defenders get answered.
			setEnabled(AnticheatBypass, true)
			setEnabled(Killaura, true)

			local beds = collection('BedWarsX_BedSpawn', AutoFarm)
			local shops = collection('BedWarsX_ShopNPC', AutoFarm)
			target, shopUntil = nil, nil
			resetRoute()

			AutoFarm:Clean(runService.PreSimulation:Connect(function(dt)
				if not entitylib.isAlive then
					phase, target = nil, nil
					resetRoute()
					return
				end
				noclip()
				setEnabled(Killaura, true)
				local position = entitylib.character.RootPart.Position

				-- Stay on one bed until it is actually down, otherwise drifting
				-- closer to a second bed pulls us off a half broken one.
				if target and (isBroken(target) or not isEnemyBed(target)) then
					if Shop.Enabled and isBroken(target) then
						shopUntil = os.clock() + ShopTime.Value
					end
					target = nil
					resetRoute()
				end

				-- Restock between beds. AutoBuy only fires within 20 studs of a
				-- shop npc, so this just has to park us next to one.
				if shopUntil then
					if os.clock() < shopUntil then
						local shop = nearest(shops, position)
						if shop then
							phase = 'Shop'
							setEnabled(Breaker, false)
							setEnabled(AutoBuy, true)

							local distance = (shop.Position - position).Magnitude
							if distance > StopDistance.Value then
								checkStuck(distance, beds)
								flyTo(shop.Position, dt)
							else
								madeProgress()
							end
							return
						end
					end
					shopUntil = nil
					setEnabled(AutoBuy, false)
					resetRoute()
				end

				if not target then
					target = nearest(beds, position, liveEnemyBed)
					resetRoute()
				end

				if target then
					phase = 'Beds'
					setEnabled(Breaker, true)
					-- Sit above the bed rather than inside the defence, which
					-- keeps Breaker's line of sight pointed down at the cover.
					local goal = target.Position + Vector3.new(0, BedHeight.Value, 0)
					checkStuck((goal - position).Magnitude, beds)
					flyTo(goal, dt)
					return
				end

				phase = 'Players'
				setEnabled(Breaker, false)

				local enemy = entitylib.EntityPosition({
					Range = math.huge,
					Part = 'RootPart',
					Players = true,
					NPCs = true
				})
				if not enemy then
					madeProgress()
					return
				end

				local goal = enemy.RootPart.Position
				local distance = (goal - position).Magnitude
				if distance > StopDistance.Value then
					checkStuck(distance, beds)
					flyTo(goal, dt)
				else
					madeProgress()
					cruise = nil
					entitylib.character.RootPart.AssemblyLinearVelocity = Vector3.zero
				end
			end))
		else
			unclip()
			for module, wasEnabled in restore do
				setEnabled(module, wasEnabled)
			end
			table.clear(restore)
			phase, target, shopUntil = nil, nil, nil
			resetRoute()
		end
	end,
	ExtraText = function()
		return phase
	end,
	Tooltip = 'Flies to every enemy bed and breaks it, restocks between beds, then hunts down whoever is left.'
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
Clearance = AutoFarm:CreateSlider({
	Name = 'Clearance',
	Min = 2,
	Max = 40,
	Default = 12,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'How far above an obstacle to cross it.\nRaise this if it keeps clipping the tops of builds.'
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
	Tooltip = 'How close to close in on a player or a shop'
})
Shop = AutoFarm:CreateToggle({
	Name = 'Shop between beds',
	Default = true,
	Function = function(callback)
		if ShopTime then
			ShopTime.Object.Visible = callback
		end
	end,
	Tooltip = 'Fly to a shop npc and let AutoBuy restock after every bed'
})
ShopTime = AutoFarm:CreateSlider({
	Name = 'Shop for',
	Min = 1,
	Max = 15,
	Default = 5,
	Darker = true,
	Suffix = function(val)
		return val == 1 and 'second' or 'seconds'
	end,
	Tooltip = 'AutoBuy purchases one item every 0.2s, so allow a few seconds'
})
AntiSuffocate = AutoFarm:CreateToggle({
	Name = 'Anti Suffocate',
	Default = true,
	Tooltip = 'Rise out of any block we end up inside of, while still travelling'
})
AutoReset = AutoFarm:CreateToggle({
	Name = 'Auto reset',
	Default = true,
	Function = function(callback)
		if StuckTime then
			StuckTime.Object.Visible = callback
		end
	end,
	Tooltip = 'Respawn when the route stops making progress.\nSkipped when your own bed is gone, since dying then is elimination.'
})
StuckTime = AutoFarm:CreateSlider({
	Name = 'Reset after',
	Min = 1,
	Max = 15,
	Default = 8,
	Darker = true,
	Suffix = function(val)
		return val == 1 and 'second' or 'seconds'
	end
})
