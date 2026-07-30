local ChaseSpeed
local CatchupDistance
local CatchupDelay
local overParams = RaycastParams.new()
overParams.RespectCanCollide = true

local function clampVec(vec, max)
	if vec.Magnitude > max then
		return vec.Unit == vec.Unit and vec.Unit * max or Vector3.zero
	end

	return vec
end

AnticheatBypass = vape.Categories.Blatant:CreateModule({
	Name = 'AnticheatBypass',
	Function = function(callback)
		if callback then
			bypassRoot = Instance.new('Part')
			bypassRoot.CanCollide = false
			bypassRoot.CanQuery = false
			bypassRoot.Size = Vector3.new(2, 2, 1)
			bypassRoot.Material = Enum.Material.SmoothPlastic
			bypassRoot.Transparency = 1
			bypassRoot.Parent = workspace.CurrentCamera
			AnticheatBypass:Clean(bypassRoot)

			local oldcf, oldvelo
			local bindKey = game:GetService('HttpService'):GenerateGUID(true)
			runService:BindToRenderStep(bindKey, 0, function()
				if entitylib.isAlive and oldcf then
					entitylib.character.RootPart.CFrame = oldcf
				end
			end)

			AnticheatBypass:Clean(function()
				runService:UnbindFromRenderStep(bindKey)
			end)

			for _, connection in {entitylib.Events.LocalAdded, replicatedStorage.GameEvents.BedWarsRemotes.AntiCheat_Strike.OnClientEvent} do
				AnticheatBypass:Clean(connection:Connect(function()
					oldcf = nil
				end))
			end

			local tpTimer = 0
			local fallTimer = 0
			AnticheatBypass:Clean(runService.Heartbeat:Connect(function(dt)
				if entitylib.isAlive then
					local root = entitylib.character.RootPart
					if not oldcf then
						bypassRoot.CFrame = root.CFrame
					end
					oldcf = root.CFrame

					local chase = entitylib.character.Humanoid.WalkSpeed * ChaseSpeed.Value
					local diff = (oldcf.Position - bypassRoot.Position) * Vector3.new(1, 0, 1)
					local united = diff.Unit
					united = united == united and diff.Magnitude > 0.1 and united * chase or Vector3.zero
					bypassRoot.AssemblyLinearVelocity = Vector3.new(united.X, 0, united.Z)
					bypassRoot.CFrame = CFrame.lookAlong(Vector3.new(bypassRoot.Position.X, root.Position.Y, bypassRoot.Position.Z), root.CFrame.LookVector)
					if diff.Magnitude > CatchupDistance.Value and (os.clock() - tpTimer) > CatchupDelay.Value then
						bypassRoot.CFrame += clampVec(diff, chase)
						tpTimer = os.clock()
					end

					overParams.CollisionGroup = root.CollisionGroup
					overParams.FilterDescendantsInstances = {lplr.Character, gameCamera}
					local flyCheck = workspace:Raycast(bypassRoot.Position, Vector3.new(0, -8, 0), overParams)
					if not flyCheck then
						if fallTimer == 0 then
							fallTimer = os.clock()
						end
						bypassRoot.CFrame -= Vector3.new(0, ((os.clock() - fallTimer) % 1) * 10, 0)
					else
						fallTimer = 0
					end

					root.CFrame = bypassRoot.CFrame
					if root.AssemblyLinearVelocity.Magnitude < 0.1 then
						root.AssemblyLinearVelocity += Vector3.new(0, -0.1, 0)
					end
				else
					bypassRoot.CFrame = CFrame.new()
					bypassRoot.AssemblyLinearVelocity = Vector3.zero
				end
			end))
		else
			bypassRoot = nil
		end
	end,
	Tooltip = 'Using various methods to bypass the Anticheat.'
})
ChaseSpeed = AnticheatBypass:CreateSlider({
	Name = 'Chase Speed',
	Min = 1,
	Max = 10,
	Default = 1,
	Decimal = 10,
	Suffix = 'x walkspeed',
	Tooltip = 'How fast the fake root is allowed to follow you.\nRaise this to stop setbacks at high speeds, lower it if the anticheat starts striking.'
})
CatchupDistance = AnticheatBypass:CreateSlider({
	Name = 'Catchup Distance',
	Min = 1,
	Max = 30,
	Default = 6,
	Suffix = function(val)
		return val == 1 and 'stud' or 'studs'
	end,
	Tooltip = 'How far the fake root may drift behind you before it teleports to catch up'
})
CatchupDelay = AnticheatBypass:CreateSlider({
	Name = 'Catchup Delay',
	Min = 0,
	Max = 2,
	Default = 0.75,
	Decimal = 100,
	Suffix = function(val)
		return val == 1 and 'second' or 'seconds'
	end,
	Tooltip = 'Minimum time between catchup teleports.\nLower means the fake root keeps up with faster movement.'
})