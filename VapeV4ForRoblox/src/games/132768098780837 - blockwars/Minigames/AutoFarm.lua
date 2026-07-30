local AutoFarm
local FarmKills
local FlySpeed
local ClimbSpeed
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
local cruise, stage
local routeIgnore
local overlapCheck = OverlapParams.new()
local pathCheck = RaycastParams.new()
pathCheck.RespectCanCollide = true

-- How far above a goal the router may climb before it admits the route is
-- hopeless and lets the stuck timer respawn us.
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

-- Whatever we are flying at has to be ignored, or the ray stops on the target
-- itself and every trip reads as obstructed. Chasing a player was the bad case:
-- their own body blocked the line, so the router never flew direct.
local function blocked(from, to)
	pathCheck.FilterDescendantsInstances = {lplr.Character, gameCamera, routeIgnore}
	return workspace:Raycast(from, to - from, pathCheck) ~= nil
end

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

local function madeProgress()
	progressed = os.clock()
end

local function resetRoute()
	closest, progressed, cruise, stage = nil, os.clock(), nil, nil
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

-- The bypass masks its drift to Vector3.new(1, 0, 1) and copies our Y straight
-- onto the decoy, so only sideways travel spends its catch up budget. Vertical
-- gets its own faster allowance because nothing is clamping it.
local function moveFlat(root, direction, dt)
	local distance = direction.Magnitude
	if distance < 0.01 then return end
	root.CFrame += direction.Unit * math.min(FlySpeed.Value * dt, distance)
end

local function moveVertical(root, amount, dt)
	local limit = ClimbSpeed.Value * dt
	root.CFrame += Vector3.new(0, math.clamp(amount, -limit, limit), 0)
end

-- Straight lines walk into buildings, so the route climbs over them: rise to a
-- cruise height, cross at that height, drop onto the goal. The stages are
-- explicit because deciding afresh each frame made the descent climb straight
-- back up again, which is what the bouncing was.
local function flyTo(goal, dt)
	local root = entitylib.character.RootPart
	root.AssemblyLinearVelocity = Vector3.zero

	-- Never while dropping or parked -- there the rise only fights the descent.
	if stage ~= 'descend' and stage ~= 'hold' and insideBlock(root) then
		moveVertical(root, math.huge, dt)
		madeProgress()
	end

	local position = root.Position
	local delta = goal - position
	if delta.Magnitude < 0.1 then
		stage, cruise = nil, nil
		return
	end

	-- Parked on top of a defence. Sink further as Breaker eats through it.
	if stage == 'hold' then
		if insideBlock(root) then
			moveVertical(root, math.huge, dt)
			madeProgress()
			return
		end
		stage = 'descend'
	end

	if not stage then
		if not blocked(position, goal) then
			moveFlat(root, Vector3.new(delta.X, 0, delta.Z), dt)
			moveVertical(root, delta.Y, dt)
			return
		end
		-- Clearance goes above the goal, never above wherever we already are.
		-- Adding it to our own height ratchets: every re-plan while chasing a
		-- moving target set a cruise higher than the last, and it just climbed.
		cruise = math.max(goal.Y + Clearance.Value, position.Y)
		stage = 'climb'
	end

	if stage == 'climb' then
		if position.Y < cruise - 1 then
			moveVertical(root, cruise - position.Y, dt)
			madeProgress()
			return
		end
		stage = 'cruise'
	end

	if stage == 'cruise' then
		local flat = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
		if flat.Magnitude > 2 then
			local ahead = position + flat.Unit * math.min(flat.Magnitude, 12)
			if blocked(position, ahead) then
				-- Not high enough. Past the ceiling stop raising and stop
				-- feeding the timer, so auto reset takes it instead of looping.
				if cruise < goal.Y + CEILING then
					cruise += Clearance.Value
					stage = 'climb'
					madeProgress()
				end
				return
			end
			moveFlat(root, flat, dt)
			return
		end
		stage = 'descend'
	end

	-- Dropping onto the goal, and never climbing back out of it.
	if insideBlock(root) then
		-- As deep as we get without burying ourselves, which is the top of the
		-- defence -- exactly where Breaker wants to be looking down from.
		stage = 'hold'
		madeProgress()
		return
	end
	moveFlat(root, Vector3.new(delta.X, 0, delta.Z), dt)
	moveVertical(root, delta.Y, dt)
	if delta.Magnitude < 2 then
		stage, cruise = nil, nil
	end
end

local function setEnabled(module, wanted)
	if module and module.Enabled ~= wanted then
		module:Toggle()
	end
end

-- Close on whoever is nearest and let Killaura do the rest. Once they die
-- entitylib stops returning them and the next call picks the next group up.
local function huntPlayers(position, beds, dt)
	local enemy = entitylib.EntityPosition({
		Range = math.huge,
		Part = 'RootPart',
		Players = true,
		NPCs = true
	})
	if not enemy then
		routeIgnore = nil
		madeProgress()
		return
	end

	routeIgnore = enemy.Character
	local goal = enemy.RootPart.Position
	local distance = (goal - position).Magnitude
	if distance > StopDistance.Value then
		checkStuck(distance, beds)
		flyTo(goal, dt)
	else
		madeProgress()
		stage, cruise = nil, nil
		entitylib.character.RootPart.AssemblyLinearVelocity = Vector3.zero
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

				-- Kills only. Skip beds and shopping entirely and keep moving
				-- from one target to the next.
				if FarmKills.Enabled then
					phase = 'Kills'
					setEnabled(Breaker, false)
					setEnabled(AutoBuy, false)
					if target or shopUntil then
						target, shopUntil = nil, nil
						resetRoute()
					end
					huntPlayers(position, beds, dt)
					return
				end

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
							routeIgnore = shop

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
					routeIgnore = target
					-- Sit above the bed rather than inside the defence, which
					-- keeps Breaker's line of sight pointed down at the cover.
					local goal = target.Position + Vector3.new(0, BedHeight.Value, 0)
					checkStuck((goal - position).Magnitude, beds)
					flyTo(goal, dt)
					return
				end

				phase = 'Players'
				setEnabled(Breaker, false)
				huntPlayers(position, beds, dt)
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
		-- The text gui concatenates this unconditionally, so returning nil
		-- errors mid render and the whole module stops being drawn.
		return phase or 'Idle'
	end,
	Tooltip = 'Flies to every enemy bed and breaks it, restocks between beds, then hunts down whoever is left.'
})
FarmKills = AutoFarm:CreateToggle({
	Name = 'Farm kills',
	Function = function(callback)
		if ShopTime then
			Shop.Object.Visible = not callback
			ShopTime.Object.Visible = not callback and Shop.Enabled
			BedHeight.Object.Visible = not callback
		end
		if AutoFarm.Enabled then
			target, shopUntil = nil, nil
			resetRoute()
		end
	end,
	Tooltip = 'Ignore beds entirely and just chase players for the kill count'
})
FlySpeed = AutoFarm:CreateSlider({
	Name = 'Fly speed',
	Min = 1,
	Max = 38,
	Default = 18,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'Sideways travel only, which is the part the bypass has to cover.\nIt keeps up with roughly 37 studs, so past that you get set back.'
})
ClimbSpeed = AutoFarm:CreateSlider({
	Name = 'Climb speed',
	Min = 1,
	Max = 38,
	Default = 38,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'Up and down travel. The bypass copies our height across untouched,\nso this does not spend any of its catch up budget.'
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
