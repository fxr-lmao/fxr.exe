local AutoFarm
local FlySpeed
local BedHeight
local StopDistance
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
local overlapCheck = OverlapParams.new()

local function isEnemyBed(bed)
	return bed:GetAttribute('BedTeamId') ~= (lplr.Team and lplr.Team.Name or '')
end

local function isBroken(bed)
	return not bed.Parent or (bed:GetAttribute('HP') or 10) <= 0
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

local function liveEnemyBed(bed)
	return isEnemyBed(bed) and not isBroken(bed)
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
			resetProgress()

			AutoFarm:Clean(runService.PreSimulation:Connect(function(dt)
				if not entitylib.isAlive then
					phase, target = nil, nil
					resetProgress()
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
					resetProgress()
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
								resetProgress()
							end
							return
						end
					end
					shopUntil = nil
					setEnabled(AutoBuy, false)
					resetProgress()
				end

				if not target then
					target = nearest(beds, position, liveEnemyBed)
					resetProgress()
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
			phase, target, shopUntil = nil, nil, nil
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
