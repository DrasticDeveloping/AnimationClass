-- Made by drastic, sometime in early 2025
-- Not for use in server authority
-- Not for use with animations that rely on character positioning/interpolation delay (like character movement anims)
-- additional features could be: disabling syncing on specific anims

-- Fixes a lot of edge cases with the default roblox animation system
-- Battle tested in live environments, should have minimal/0 bugs

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Utility = ReplicatedStorage.Modules.Utility

local LocalNetworkOwner = Players.LocalPlayer
local IsServer, IsClient = RunService:IsServer(), RunService:IsClient()

local Config = require(script:WaitForChild("Config"))
local Signal = require(Utility:WaitForChild("Signal"))
local AnimationData = require(script:WaitForChild("AnimationData"))
local NetworkHelper = require(script:WaitForChild("NetworkHelper"))
local AnimationClass = require(script:WaitForChild("AnimationClass"))
local AnimatorClass = require(script:WaitForChild("AnimatorClass"))

local GetAnimatorsRemote = script:WaitForChild("GetAnimators")
local AnimationPlayedRemote = script:WaitForChild("AnimationPlayed")
local AnimationStoppedRemote = script:WaitForChild("AnimationStopped")
local LoadAnimationRemote = script:WaitForChild("LoadAnimation")
local AnimationChangedRemote = script:WaitForChild("AnimationChanged")
local CreateAnimatorRemote = script:WaitForChild("CreateAnimator")
local AnimatorDestroyingRemote = script:WaitForChild("AnimatorDestroying")

local InitializedPlayers = Config.InitializedPlayers
local AnimatorModule = {
	CreatedAnimators = AnimatorClass.CreatedAnimators,
	
	new = AnimatorClass.new,
	WaitFor = AnimatorClass.WaitFor,
	
	AnimatorAdded = AnimatorClass.AnimatorAdded,
	AnimatorRemoving = AnimatorClass.AnimatorRemoving,
	AnimationLatencyUpdated = AnimationClass.AnimationLatencyUpdated,
}

local function CheckIfModel(Model)
	if typeof(Model) ~= "Instance" then return false end
	if not Model:IsA("Model") then return false end
	return true
end

local function AnimationLoadedEvent(Animator, NumberId, NetworkOwner)
	if type(NumberId) ~= "number" then return end
	
	local AnimationName = AnimationData.GetNumberId(NumberId)
	local AnimationTrack = Animator:GetPlayingAnimationFromId(AnimationName, true)	
	local Animation = AnimationClass.new(AnimationTrack, Animator, NetworkOwner)
	
	Animator.LoadedAnimations[Animation.NumberId] = Animation
	Animator.AnimationLoaded:Fire(Animation)
	
	if IsServer then
		NetworkHelper.FirePlayersExcept(LoadAnimationRemote, Animator.NetworkOwner, Animator.Model, NumberId)
	end
end

local function AnimationPlayedEvent(Animator, Animation, Timestamp, FadeIn, Weight, Speed)
	if type(Timestamp) ~= "number" then return end
	if type(FadeIn) ~= "number" then return end
	if type(Weight) ~= "number" then return end
	if type(Speed) ~= "number" then return end
	
	local AnimationTrack = Animation.AnimationTrack
	local PacketOffset = workspace:GetServerTimeNow() - Timestamp
	
	if IsServer then
		NetworkHelper.FirePlayersExcept(AnimationPlayedRemote, Animation.NetworkOwner, Animator.Model, Animation.NumberId, Timestamp, FadeIn, Weight, Speed)
	end
	
	if AnimationTrack.IsPlaying == false then
		local ChangedConnection, TimeoutDelay, Running, Result
		Running = coroutine.running()
		ChangedConnection = AnimationTrack:GetPropertyChangedSignal("IsPlaying"):Once(function()
			if TimeoutDelay and coroutine.status(TimeoutDelay) == "suspended" then
				task.cancel(TimeoutDelay)
				TimeoutDelay = nil
			end

			if coroutine.status(Running) == "suspended" then
				task.spawn(Running, true)
			end
			
			ChangedConnection = nil
		end)
		TimeoutDelay = task.delay(5, function()
			if ChangedConnection then
				ChangedConnection:Disconnect()
			end

			if coroutine.status(Running) == "suspended" then
				task.spawn(Running, false)
			end
			
			warn("TimeoutDelay reached, cancelling :Play() request.")
			TimeoutDelay = nil
		end)
		Result = coroutine.yield()
		if not Result then return end
	end
	
	Animation.Speed = Speed or Animation.Speed
	Animation.Weight = Weight or Animation.Weight
	
	Animation:TimePositionLatencyUpdate(Timestamp, 0)
	Animator.AnimationPlayed:Fire(Animation)
end

local function AnimationStoppedEvent(Animator, Animation, Timestamp, FadeOut)	
	if type(Timestamp) ~= "number" then return end
	if type(FadeOut) ~= "number" then return end
	
	local AnimationTrack = Animation.AnimationTrack
	local PacketOffset = workspace:GetServerTimeNow()-Timestamp
	
	AnimationTrack:Stop(FadeOut-PacketOffset)
	
	if IsServer then
		NetworkHelper.FirePlayersExcept(AnimationStoppedRemote, Animation.NetworkOwner, Animator.Model, Animation.NumberId, FadeOut)
	end
end

local function AnimationChangedEvent(Animation, AnimationData)
	local Animator = Animation.AnimatorClass
	local Speed, Timestamp, TimePosition, Looped, Weight, Priority = AnimationData.Speed, AnimationData.Timestamp, AnimationData.TimePosition, AnimationData.Looped, AnimationData.Weight, AnimationData.Priority
	
	if type(Speed) ~= nil and type(Speed) ~= "number" then return end
	if type(Timestamp) ~= nil and type(Timestamp) ~= "number" then return end
	if type(TimePosition) ~= nil and type(TimePosition) ~= "number" then return end
	if typeof(Priority) ~= nil and typeof(Priority) ~= "EnumItem" then return end
	if type(Weight) ~= nil and type(Weight) ~= "number" then return end
	
	--print(AnimationData)
	
	if Speed then
		Animation:SpeedLatencyUpdate(Timestamp, Speed, TimePosition)
	elseif TimePosition then
		Animation:TimePositionLatencyUpdate(Timestamp, TimePosition)
	elseif Looped ~= nil then
		Animation.Looped = Looped
		Animation.AnimationTrack.Looped = Looped
	elseif Weight then
		Animation.WeightTarget = Weight
		Animation.AnimationTrack:AdjustWeight(Weight)
	elseif Priority then
		Animation.Priority = Priority
		Animation.AnimationTrack.Priority = Priority
	end
end

if IsClient then	
	local Initialized = false
	local function EmptyFunction()end
	
	local function CreateAnimator(Model, Animator, UUID)
		if not AnimatorModule.CreatedAnimators[Model] then
			print(Model, Animator, UUID)
			AnimatorModule.new(Animator, UUID)
		end
	end

	local function DestroyAnimator(Model, UUID)
		local Animator = Model and AnimatorModule.CreatedAnimators[Model]

		if not Animator or not Model then
			for _, ActiveAnimator in AnimatorModule.CreatedAnimators do
				if ActiveAnimator.UUID == UUID then
					Animator = ActiveAnimator
					break
				end
			end
		end

		if Animator then
			Animator:Destroy()
		else
			warn("Animator not found")
		end
	end
	
	local function LoadAnimation(Model, NumberId, NetworkOwner)
		local Animator = AnimatorModule.WaitFor(Model)
		AnimationLoadedEvent(Animator, NumberId, NetworkOwner)
	end
	
	local function AnimationPlayed(Model, NumberId, ...)
		local Animator = AnimatorModule.WaitFor(Model)
		local Animation = Animator:GetLoadedAnimation(NumberId, true)
		
		while not Animation.AnimationTrack.IsPlaying do
			task.wait()
		end

		if Animation then
			AnimationPlayedEvent(Animator, Animation, ...)
		else
			warn("Animation not found")
		end
	end
	
	local function AnimationStopped(Model, NumberId, ...)
		local Animator = AnimatorModule.WaitFor(Model)
		local Animation = Animator:GetLoadedAnimation(NumberId, true)

		if Animation then
			AnimationStoppedEvent(Animator, Animation, ...)
		else
			warn("Animation not found")
		end
	end
	
	local function AnimationChanged(Model, NumberId, AnimationData)
		local Animator = AnimatorModule.WaitFor(Model)
		local Animation = Animator:GetLoadedAnimation(NumberId, true)

		if Animation then
			AnimationChangedEvent(Animation, AnimationData)
		else
			warn("Animation not found")
		end
	end
	
	local LoadedStuff, UUID = GetAnimatorsRemote:InvokeServer()
	for _, AnimatorData in LoadedStuff do
		local NewAnimator = AnimatorModule.new(AnimatorData.Animator, AnimatorData.UUID)
		
		for _, AnimationData in AnimatorData.LoadedAnimations do
			task.defer(AnimationLoadedEvent, NewAnimator, AnimationData.NumberId, AnimationData.NetworkOwner)
		end
	end
	
	Initialized = true
	Config.CurrentUUID = UUID
	
	CreateAnimatorRemote.OnClientEvent:Connect(CreateAnimator)
	AnimatorDestroyingRemote.OnClientEvent:Connect(DestroyAnimator)
	LoadAnimationRemote.OnClientEvent:Connect(LoadAnimation)
	AnimationPlayedRemote.OnClientEvent:Connect(AnimationPlayed)
	AnimationStoppedRemote.OnClientEvent:Connect(AnimationStopped)
	AnimationChangedRemote.OnClientEvent:Connect(AnimationChanged)
elseif IsServer then
	LoadAnimationRemote.OnServerEvent:Connect(function(Player, Model, NumberId)
		if not CheckIfModel(Model) then return end
		if type(NumberId) ~= "number" then return end
		
		local Animator = AnimatorModule.WaitFor(Model)
		
		if Animator.NetworkOwner == Player then
			AnimationLoadedEvent(Animator, NumberId, Player)
		else
			warn("No.")
		end
	end)
	
	AnimationPlayedRemote.OnServerEvent:Connect(function(Player, Model, NumberId, ...)
		if not CheckIfModel(Model) then return end
		if type(NumberId) ~= "number" then return end
		
		local Animator = AnimatorModule.WaitFor(Model)

		local Animation = Animator:GetLoadedAnimation(NumberId)
		
		if Animation and Animator.NetworkOwner == Player then
			AnimationPlayedEvent(Animator, Animation, ...)
		else
			warn("Animation not found")
		end
	end)
	
	AnimationStoppedRemote.OnServerEvent:Connect(function(Player, Model, NumberId, ...)
		if not CheckIfModel(Model) then return end
		if type(NumberId) ~= "number" then return end
		
		local Animator = AnimatorModule.WaitFor(Model)
		local Animation = Animator:GetLoadedAnimation(NumberId, true)

		if Animation and Animator.NetworkOwner == Player then
			AnimationStoppedEvent(Animator, Animation, ...)
		else
			warn("Animation not found")
		end
	end)
	
	AnimationChangedRemote.OnServerEvent:Connect(function(Player, Model, NumberId, AnimationData)
		if not CheckIfModel(Model) then return end
		if type(NumberId) ~= "number" then return end
		
		local Animator = AnimatorModule.WaitFor(Model)
		local Animation = Animator:GetLoadedAnimation(NumberId, true)
		
		if Animation and Animator.NetworkOwner == Player then
			AnimationChangedEvent(Animation, AnimationData)
			
			for i,v in Players:GetPlayers() do
				if v == Player then continue end
				AnimationChangedRemote:FireClient(v, Model, NumberId, AnimationData)
			end
		else
			warn("Animation not found")
		end
	end)
	
	local PerAnimator, PerAnimation = {
		Model = false,
		Animator = false,
		LocalNetworkOwner = false,
		UUID = false,
		LoadedAnimations = false
	}, {
		NumberId = false,
		LocalNetworkOwner = false,
	}
	
	GetAnimatorsRemote.OnServerInvoke = function(Player)
		local Data = {}
		
		for _, Animator in AnimatorModule.CreatedAnimators do
			local NewData = table.clone(PerAnimator)
			NewData.Model = Animator.Model
			NewData.Animator = Animator.Animator
			NewData.UUID = Animator.UUID
			NewData.LocalNetworkOwner = Animator.LocalNetworkOwner
			NewData.LoadedAnimations = {}
			
			for NumberId, Animation in Animator.LoadedAnimations do
				local AnimationData = table.clone(PerAnimation)
				AnimationData.NumberId = Animation.NumberId
				AnimationData.LocalNetworkOwner = Animation.LocalNetworkOwner
				table.insert(NewData.LoadedAnimations, AnimationData)
			end
			
			table.insert(Data, NewData)
		end
		
		InitializedPlayers[Player] = true
		
		return Data, Config.CurrentUUID
	end
	
	Players.PlayerRemoving:Connect(function(Player)
		InitializedPlayers[Player]=nil
	end)
end

return AnimatorModule