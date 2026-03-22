local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalNetworkOwner = Players.LocalPlayer
local IsServer, IsClient = RunService:IsServer(), RunService:IsClient()

local Config = require(script.Parent:WaitForChild("Config"))
local Signal = require(ReplicatedStorage.Modules.Utility.Signal)
local NetworkHelper = require(script.Parent:WaitForChild("NetworkHelper"))
local AnimationData = require(script.Parent:WaitForChild("AnimationData"))
local AnimationClass = require(script.Parent:WaitForChild("AnimationClass"))

local LoadAnimationRemote = script.Parent:WaitForChild("LoadAnimation")
local CreateAnimatorRemote = script.Parent:WaitForChild("CreateAnimator")
local AnimatorDestroyingRemote = script.Parent:WaitForChild("AnimatorDestroying")

local MaxConcurrentAnimations = Config.MaxConcurrentAnimations
local RemoteLatency = Config.RemoteDelay

local AnimationSearchQueue = {}

local AnimatorModule = {
	CreatedAnimators = {},
	
	AnimatorAdded = Signal.new(),
	AnimatorRemoving = Signal.new(),
}

local AnimatorClass = {
	UUID = false,
	Model = false,
	Animator = false,
	NetworkOwner = false,
	
	LoadedAnimations = false,
	AnimationQueue = false,
	
	AnimationPlayed = false,
	AnimationLoaded = false,
	AnimationQueued = false,
	Destroying = false,
	
	GetPlayingAnimationTracks = function(self)
		return self.Animator:GetPlayingAnimationTracks()
	end,

	StopPlayingAnimationTracks = function(self)
		for _, AnimationTrack in self:GetPlayingAnimationTracks() do
			AnimationTrack:Play(0, 0, 0)
		end
	end,

	GetPlayingAnimationFromId = function(self, Id, Yield)
		local AnimationId = type(Id) == "number" and Id or AnimationData.GetNumberId(Id)
		
		for _, AnimationTrack in self:GetPlayingAnimationTracks() do
			local CheckedAnimationId = AnimationData.GetNumberId(AnimationTrack.Animation.AnimationId)

			if CheckedAnimationId == AnimationId or (type(AnimationId) == "table" and AnimationId[CheckedAnimationId]) then
				return AnimationTrack
			end
		end

		if Yield then
			local AnimationQueue = self.AnimationQueue
			local Running = coroutine.running()
			
			local Queue = AnimationSearchQueue[self] or {}
			
			if type(AnimationId) == "table" then
				for Id in AnimationId do
					Queue[Id] = Queue[Id] or {}
					Queue[Id][Running] = true
				end
			end
			
			Queue[Running] = AnimationId
			AnimationSearchQueue[self] = Queue

			return coroutine.yield()
		end
	end,

	GetLoadedAnimation = function(self, Id, Yield)
		local LoadedAnimations = self.LoadedAnimations
		local NumberId = type(Id) == "number" and Id or AnimationData.GetNumberId(Id)
		
		if type(NumberId) ~= "table" then
			NumberId = {[NumberId]=true}
		end

		for AnimId in NumberId do
			if AnimId == nil or type(AnimId) == "string" then
				warn(AnimId, NumberId, Id, type(AnimId))
			else
				if LoadedAnimations[AnimId] then
					return LoadedAnimations[AnimId]
				end
			end
		end
		
		if Yield then
			local Running = coroutine.running()
			local Connection; Connection = self.AnimationLoaded:Connect(function(Animation)
				if NumberId[Animation.NumberId] and coroutine.status(Running) == "suspended" then
					task.spawn(Running, Animation)
				end
			end)
			return coroutine.yield()
		end
	end,

	LoadAnimation = function(self, Animation)
		if IsServer or LocalNetworkOwner == self.NetworkOwner then
			if Config.PreventDuplicateLoading then
				local NumberId = AnimationData.GetNumberId(Animation.AnimationId)
				if self.LoadedAnimations[NumberId] then
					warn("Animation is already loaded, returning loaded animation", self.LoadedAnimations[NumberId])
					warn(Animation, self.LoadedAnimations[NumberId].AnimationTrack.Animation)
					warn(debug.traceback())
					return self.LoadedAnimations[NumberId]
				end
			end

			local Animator = self.Animator
			local AnimationTrack = Animator:LoadAnimation(Animation)
			local Animation = AnimationClass.new(AnimationTrack, self, LocalNetworkOwner)

			self.LoadedAnimations[Animation.NumberId] = Animation
			self.AnimationLoaded:Fire(Animation)
			
			NetworkHelper.FireAll(LoadAnimationRemote, 				
				self.Model, 
				Animation.NumberId, 
				LocalNetworkOwner
			)
			
			-- There is a limit of 20 unique animations that can play at the same time
			-- Leave room for extra incase something else tries to load/play any anims
			while #self:GetPlayingAnimationTracks() >= MaxConcurrentAnimations do 
				task.wait(RemoteLatency)
			end
			
			Animation.AnimationTrack:Play(nil, 0.01, nil)
			--keeping this old code here incase it somehow breaks again
			--task.spawn(Animation.AnimationTrack.Play, Animation.AnimationTrack, nil, 0.01, nil)
			task.delay(RemoteLatency, Animation.AnimationTrack.Stop, Animation.AnimationTrack)
			
			return Animation
		else
			warn(":LoadAnimation() is disabled on this AnimatorClass")
		end
	end,

	Destroy = function(self)		
		AnimatorModule.AnimatorRemoving:Fire(self)
		self.Destroying:Fire()
		
		self.AnimationPlayed:DisconnectAll()
		self.AnimationLoaded:DisconnectAll()
		self.Destroying:DisconnectAll()
		
		for _, Animation in self.LoadedAnimations do
			Animation:Destroy()
		end
		
		if IsServer then
			AnimatorDestroyingRemote:FireAllClients(self.Model, self.UUID)
		end
	end,
}

function AnimatorModule.new(Animator: Animator, UUID)
	local Model = Animator:FindFirstAncestorOfClass("Model")
	local NetworkOwner = Players:GetPlayerFromCharacter(Model)
	
	local self = table.clone(AnimatorClass)
	
	if not UUID then
		Config.CurrentUUID+= 1
		UUID = Config.CurrentUUID
	end
	
	self.UUID = UUID
	self.Model = Model
	self.Animator = Animator
	self.NetworkOwner = NetworkOwner

	self.LoadedAnimations = {}

	self.AnimationPlayed = Signal.new()
	self.AnimationLoaded = Signal.new()
	self.Destroying = Signal.new()

	if IsServer then
		CreateAnimatorRemote:FireAllClients(Model, Animator, type(UUID) ~= "number" and UUID or nil)
	end

	AnimatorModule.CreatedAnimators[Model] = self
	AnimatorModule.AnimatorAdded:Fire(self)
		
	if IsServer and Config.DestroyAnimatorUponModelDestroying then
		Model.Destroying:Once(function()
			self:Destroy()
		end)
	end

	return self
end

function AnimatorModule.WaitFor(Model)
	if AnimatorModule.CreatedAnimators[Model] then
		return AnimatorModule.CreatedAnimators[Model]
	end

	local Running, Connection = coroutine.running(), nil
	Connection = AnimatorModule.AnimatorAdded:Connect(function(Animator)
		if Animator.Model == Model and coroutine.status(Running) == "suspended" then
			task.spawn(Running, Animator)
			Connection:Disconnect()
		end
	end)

	return coroutine.yield()
end

local function ClearEmptyTable(ParentTable, Index)
	local Done = true
	local Table = ParentTable[Index]
	
	for _ in Table do
		Done = false
	end
	
	if Done then
		ParentTable[Index] = nil
	end
end

-- Native .AnimationPlayed on Animator instances is unreliable, so polling is required
RunService.PreAnimation:Connect(function(dt)
	local AnimationsFound = {}
	
	for AnimatorClass, SearchQueue in AnimationSearchQueue do
		local PlayingAnimationTracks = AnimatorClass:GetPlayingAnimationTracks()
		
		for _, AnimationTrack in PlayingAnimationTracks do
			local AnimationId = AnimationTrack.Animation.AnimationId
			local NumberId = AnimationData.GetNumberId(AnimationId)
			local SearchInfo = SearchQueue[NumberId]
			
			if SearchInfo then
				for Thread in SearchInfo do
					local SearchesRelatedToThread = SearchQueue[Thread]
					
					if SearchesRelatedToThread then
						SearchesRelatedToThread = type(SearchesRelatedToThread) == "table" and SearchesRelatedToThread or {[SearchesRelatedToThread]=true}

						for AnimationId in SearchesRelatedToThread do
							local SearchInfo = SearchQueue[AnimationId]
							
							if SearchInfo then
								SearchInfo[Thread] = nil
								ClearEmptyTable(SearchQueue, AnimationId)
							else
								warn("SearchInfo is nil.")
							end
						end
						
						SearchQueue[Thread] = nil
						task.spawn(Thread, AnimationTrack)
					else
						warn("SearchesRelatedToThread is nil.")
					end
				end
				
				SearchInfo[NumberId] = nil
			end
		end
		
		ClearEmptyTable(AnimationSearchQueue, AnimatorClass)
	end
end)

return AnimatorModule