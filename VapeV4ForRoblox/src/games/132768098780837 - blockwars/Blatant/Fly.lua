local Fly
run(function()
	local Value
	local Keys
	local TouchButtons
	local Platform = Instance.new('Part')
	Platform.CanQuery = false
	Platform.Anchored = true
	Platform.Size = Vector3.new(4, 1, 4)
	Platform.Transparency = 1
	Platform.Parent = nil

	local touchGui = Instance.new('ScreenGui')
	touchGui.Name = 'VapeFlyButtons'
	touchGui.ResetOnSpawn = false
	touchGui.DisplayOrder = 10
	touchGui.Parent = nil

	local function createTouchButton(text, position)
		local button = Instance.new('ImageButton')
		button.Name = text
		button.Size = UDim2.fromOffset(70, 60)
		button.Position = position
		button.AnchorPoint = Vector2.new(1, 1)
		button.BackgroundColor3 = Color3.new(0, 0, 0)
		button.BackgroundTransparency = 0.45
		button.AutoButtonColor = false
		button.Image = ''
		button.Parent = touchGui

		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = button

		local label = Instance.new('TextLabel')
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = text
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 18
		label.Font = Enum.Font.GothamBold
		label.Parent = button

		return button
	end

	local upButton = createTouchButton('UP', UDim2.new(1, -100, 1, -220))
	local downButton = createTouchButton('DOWN', UDim2.new(1, -100, 1, -150))

	local function bindTouchButton(button, setter)
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				setter(true)
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				setter(false)
			end
		end)
	end
	bindTouchButton(upButton, function(pressed)
		up = pressed and 1 or 0
	end)
	bindTouchButton(downButton, function(pressed)
		down = pressed and -1 or 0
	end)

	Fly = vape.Categories.Blatant:CreateModule({
		Name = 'Fly',
		Function = function(callback)
			if Platform then
				Platform.Parent = callback and gameCamera or nil
			end

			if callback then
				if not AnticheatBypass.Enabled then
					AnticheatBypass:Toggle()
				end

				Fly:Clean(runService.PreSimulation:Connect(function(dt)
					if entitylib.isAlive then
						applySpeed(Value.Value, dt)
						Platform.CFrame = down ~= 0 and CFrame.identity or entitylib.character.RootPart.CFrame + Vector3.new(0, -(entitylib.character.HipHeight + 0.5), 0)
					end
				end))

				up, down = 0, 0
				for _, v in {'InputBegan', 'InputEnded'} do
					Fly:Clean(inputService[v]:Connect(function(input)
						if not inputService:GetFocusedTextBox() then
							local divided = Keys.Value:split('/')
							if input.KeyCode == Enum.KeyCode[divided[1]] then
								up = v == 'InputBegan' and 1 or 0
							elseif input.KeyCode == Enum.KeyCode[divided[2]] then
								down = v == 'InputBegan' and -1 or 0
							end
						end
					end))
				end

				if inputService.TouchEnabled then
					pcall(function()
						local jumpButton = lplr.PlayerGui.TouchGui.TouchControlFrame.JumpButton
						Fly:Clean(jumpButton:GetPropertyChangedSignal('ImageRectOffset'):Connect(function()
							up = jumpButton.ImageRectOffset.X == 146 and 1 or 0
						end))
					end)

					touchGui.Parent = TouchButtons.Enabled and ((gethui and gethui()) or coreGui) or nil
				end
			else
				touchGui.Parent = nil
			end
		end,
		ExtraText = function()
			return 'BlockWars'
		end,
		Tooltip = 'Makes you go zoom.'
	})
	Keys = Fly:CreateDropdown({
		Name = 'Keys',
		List = {'Space/LeftControl', 'Space/LeftShift', 'E/Q', 'Space/Q', 'ButtonA/ButtonL2'},
		Tooltip = 'The key combination for going up & down'
	})
	TouchButtons = Fly:CreateToggle({
		Name = 'Touch Buttons',
		Default = true,
		Function = function(callback)
			if Fly.Enabled and inputService.TouchEnabled then
				touchGui.Parent = callback and ((gethui and gethui()) or coreGui) or nil
			end
		end,
		Tooltip = 'Shows on-screen UP/DOWN buttons for flying on touch devices'
	})
	Value = Fly:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 38,
		Default = 38,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)