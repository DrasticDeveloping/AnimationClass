local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalNetworkOwner = Players.LocalPlayer
local IsClient, IsServer = RunService:IsClient(), RunService:IsServer()

local Signal = require(game:GetService("ReplicatedStorage").Modules.Utility.Signal)
local AnimationData = require(script.Parent:WaitForChild("AnimationData"))
local NetworkHelper = require(script.Parent:WaitForChild("NetworkHelper"))

local AnimationLatencyUpdated = Signal.Wrap(RunService.PreAnimation)

local AnimationPlayedRemote = script.Parent:WaitForChild("AnimationPlayed")
local AnimationChangedRemote = script.Parent:WaitForChild("AnimationChanged")
local AnimationStoppedRemote = script.Parent:WaitForChild("AnimationStopped")

local function ClamptoAnimation(AnimationTrack, Number)
	return math.clamp(Number, 0.01, AnimationTrack.Length)
end

local function SearchForInDuration(TBL, Start, End)
	local Result = {}
	for _, Number in TBL do
		if Number >= Start and Number <= End then
			table.insert(Result, Number)
		end
	end
	return Result
end

local function FireSignals(SignalTable, SignalNames, ...)
	for SignalName, TimeStamps in SignalNames do
		local Signal = SignalTable[SignalName]
		
		if Signal then
			for i = 1, #TimeStamps do
				Signal:Fire(...)
			end
		end
	end	
end

local AnimationClass = {
	AnimationTrack = false,
	NetworkOwner = false,
	NumberId = false,
	LatencyQueue = false,
	
	AnimatorClass = false,
	KeyframeSignals = false,
	MarkerSignals = false,
	
	Looped = false,
	IsPlaying = false,
	Length = false,
	WeightTarget = false,
	Speed = false,
	Priority = false,
	
	Stopped = false,
	Ended = false,
	DidLoop = false,
	KeyframeReachedSignal = false,
	
	Play = function(self, FadeIn, Weight, Speed)
		self.AnimationTrack:Play(FadeIn, Weight, Speed)
		self.AnimatorClass.AnimationPlayed:Fire(self)
		
		Weight = Weight or 1
		Speed = Speed or 1
		FadeIn = FadeIn or 0.1
		
		self.WeightTarget = Weight
		self.Speed = Speed
		
		if IsServer or self.NetworkOwner == LocalNetworkOwner then
			NetworkHelper.FireAll(AnimationPlayedRemote, 				
				self.AnimatorClass.Model, 
				self.NumberId, 
				workspace:GetServerTimeNow(), 
				FadeIn, 
				Weight, 
				Speed
			)
		else
			warn("womp womp")
		end		
	end,
	Stop = function(self, FadeOut)		
		self.AnimationTrack:Stop(FadeOut)

		NetworkHelper.FireAll(AnimationStoppedRemote, 
			self.AnimatorClass.Model, 
			self.NumberId, 
			workspace:GetServerTimeNow(), 
			FadeOut or 0.1
		)
	end,
	
	GetTimeOfKeyframe = function(self, KeyframeName)
		return self.AnimationTrack:GetTimeOfKeyframe(KeyframeName)
	end,
	GetTimeOfMarker = function(self, MarkerName)
		local Metadata = self:GetMetadata().Markers
		
		if Metadata[MarkerName] then
			return Metadata[MarkerName][1]
		else
			warn("Marker doesnt exist")
		end
	end,
	
	GetMarkerReachedSignal = function(self, MarkerName)
		local MarkerSignals = self.MarkerSignals
		
		if not MarkerSignals[MarkerName] then
			local MarkerReachedSignal = self.AnimationTrack:GetMarkerReachedSignal(MarkerName)
			MarkerSignals[MarkerName] = Signal.Wrap(MarkerReachedSignal)
		end
		
		return MarkerSignals[MarkerName]
	end,
	KeyframeReached = function(self, KeyframeName)
		local KeyframeSignals = self.KeyframeSignals
		KeyframeSignals[KeyframeName] = KeyframeSignals[KeyframeName] or Signal.new()
		return KeyframeSignals[KeyframeName]
	end,

	AdjustWeight = function(self, Weight)
		if type(Weight) == "number" and Weight > 0 then
			self.WeightTarget = Weight
			self.AnimationTrack:AdjustWeight(Weight)
			if self.NetworkOwner ~= LocalNetworkOwner then
				NetworkHelper.FireAll(AnimationChangedRemote, self.AnimatorClass.Model, self.NumberId, {
					Weight = Weight
				})
				--warn("Improper behavior is to be expected when setting Looped/Weight on non network owned animations (TODO: Fix)")
			end
		else
			warn("Invalid weight provided")
		end
	end,
	AdjustSpeed = function(self, Speed)
		if Speed and type(Speed) == "number" then
			self.Speed = Speed
			self.AnimationTrack:AdjustSpeed(Speed)
			
			if IsServer or self.NetworkOwner == LocalNetworkOwner then
				NetworkHelper.FireAll(AnimationChangedRemote, self.AnimatorClass.Model, self.NumberId, {
					Speed = Speed,
					TimePosition = self.AnimationTrack.TimePosition,
					Timestamp = workspace:GetServerTimeNow(),
				})
				
				self.LatencyQueue.Speed = nil
			end
		else
			warn("Invalid speed provided")
		end
	end,
	AdjustLooped = function(self, Looped)
		if type(Looped) == "boolean" then
			self.Looped = Looped
			self.AnimationTrack.Looped = Looped
			if self.NetworkOwner ~= LocalNetworkOwner then
				NetworkHelper.FireAll(AnimationChangedRemote, self.AnimatorClass.Model, self.NumberId, {
					Looped = Looped
				})
				--warn("Improper behavior is to be expected when setting Looped/Weight on non network owned animations (TODO: Fix)")
			end
		else
			warn("Invalid looped value provided")
		end
	end,
	AdjustTimePosition = function(self, TimePosition)
		self:SetTimePosition(TimePosition)
	end,
	AdjustPriority = function(self, Priority)
		if typeof(Priority) == "EnumItem" then
			self.Priority = Priority
			self.AnimationTrack.Priority = Priority
			
			if self.NetworkOwner ~= LocalNetworkOwner then
				NetworkHelper.FireAll(AnimationChangedRemote, self.AnimatorClass.Model, self.NumberId, {
					Priority = Priority
				})
			end
		else
			warn("Invalid Priority provided")
		end
	end,
	
	SetTimePosition = function(self, TimePosition)
		if TimePosition and type(TimePosition) == "number" and math.clamp(TimePosition, 0, self.AnimationTrack.Length) == TimePosition then
			self.AnimationTrack.TimePosition = TimePosition
			
			if IsServer or self.NetworkOwner == LocalNetworkOwner then
				NetworkHelper.FireAll(AnimationChangedRemote, self.AnimatorClass.Model, self.NumberId, {
					Timestamp = workspace:GetServerTimeNow(),
					TimePosition = TimePosition,
				})

				self.LatencyQueue.TimePosition = nil
			end
		else
			warn("Invalid timeposition provided")
		end
	end,
	GetTimePosition = function(self)
		return self.AnimationTrack.TimePosition
	end,
	
	SpeedLatencyUpdate = function(self, Timestamp, Speed, TimePosition)
		local CurrentTime = workspace:GetServerTimeNow()
		local LatencyQueue = self.LatencyQueue
		local SpeedQueue = LatencyQueue.Speed
		local TimePositionQueue = LatencyQueue.TimePosition
		
		if TimePositionQueue then
			local PacketOffset = CurrentTime-TimePositionQueue.Timestamp
			local TimeOffset = PacketOffset*self.Speed
			
			local CurrentTimePosition = self:GetTimePosition()
			local LatencyCompensatedTimePosition = TimePositionQueue.TimePosition+TimeOffset
			local Markers = self:GetMarkersInDuration(CurrentTimePosition, LatencyCompensatedTimePosition)
			local Keyframes = self:GetKeyframesInDuration(CurrentTimePosition, LatencyCompensatedTimePosition)

			self.AnimationTrack.TimePosition = LatencyCompensatedTimePosition
			LatencyQueue.TimePosition = nil
			
			if Markers then
				FireSignals(self.MarkerSignals, Markers)
			end

			if Keyframes then
				FireSignals(self.KeyframeSignals, Keyframes)
			end
		end
		
		LatencyQueue.Speed = {
			Timestamp = Timestamp,
			TimePosition = TimePosition,
			Speed = Speed,
		}
		
		self:LatencyUpdateStepped()
	end,
	TimePositionLatencyUpdate = function(self, Timestamp, TimePosition)		
		local LatencyQueue = self.LatencyQueue
		local TimePositionQueue = LatencyQueue.TimePosition
		local CurrentTime = workspace:GetServerTimeNow()
		
		if TimePositionQueue then
			local PacketOffset = CurrentTime - TimePositionQueue.Timestamp
			local SpeedCompensatedOffset = PacketOffset * self.Speed
			
			local CurrentTimePosition = self:GetTimePosition()
			local LatencyCompensatedTimePosition = SpeedCompensatedOffset + TimePositionQueue.TimePosition
			local Markers = self:GetMarkersInDuration(CurrentTimePosition, LatencyCompensatedTimePosition)
			local Keyframes = self:GetKeyframesInDuration(CurrentTimePosition, LatencyCompensatedTimePosition)
			
			if Markers then
				FireSignals(self.MarkerSignals, Markers)
			end
			
			if Keyframes then
				FireSignals(self.KeyframeSignals, Keyframes)
			end
		end
		
		if LatencyQueue.Speed then
			LatencyQueue.Speed = nil
		end
		
		LatencyQueue.TimePosition = {
			Timestamp = Timestamp,
			TimePosition = TimePosition,
		}
		
		self.AnimationTrack.TimePosition = TimePosition
		self:LatencyUpdateStepped()
	end,
	
	LatencyUpdateStepped = function(self)
		local AnimationTrack = self.AnimationTrack
		local LatencyQueue = self.LatencyQueue
		
		if not self.LatencyUpdateConnection then
			self.LatencyUpdateConnection = AnimationLatencyUpdated:Connect(function()
				local CurrentTime = workspace:GetServerTimeNow()
				local TimePositionUpdate = LatencyQueue.TimePosition
				local SpeedUpdate = LatencyQueue.Speed
				
				if TimePositionUpdate then
					local Timestamp = TimePositionUpdate.Timestamp
					local TimePosition = TimePositionUpdate.TimePosition

					local PacketOffset = CurrentTime-Timestamp
					local TimeOffset = PacketOffset*self.Speed
					
					local ExpectedTimePosition = ClamptoAnimation(AnimationTrack, TimePosition + TimeOffset)
					local CurrentTimePosition = ClamptoAnimation(AnimationTrack, self:GetTimePosition())
					local NewSpeed = ExpectedTimePosition/CurrentTimePosition
										
					if math.abs(ExpectedTimePosition-CurrentTimePosition) < 0.01 then
						LatencyQueue.TimePosition = nil
					else
						self.AnimationTrack:AdjustSpeed(NewSpeed)
					end
				end
				
				if SpeedUpdate then
					local Timestamp = SpeedUpdate.Timestamp
				end
				
				if not SpeedUpdate and not TimePositionUpdate then
					self.LatencyUpdateConnection:Disconnect()
					self.LatencyUpdateConnection = nil
					AnimationTrack:AdjustSpeed(self.Speed)
				end
			end)
		end
	end,
	
	GetMetadata = function(self)
		return AnimationData.DataCache[self.NumberId]
	end,
	GetMarkersInDuration = function(self, Start, End)
		local Markers = self:GetMetadata().Markers
		local Result, HasResult = {}, false
		for MarkerName, MarkerData in Markers do
			local Matches = SearchForInDuration(MarkerData, Start, End)
			if #Matches > 0 then
				Result[MarkerName] = Matches
				HasResult = true
			end
		end
		return HasResult and Result or false
	end,
	GetKeyframesInDuration = function(self, Start, End)
		local Keyframes = self:GetMetadata().Keyframes
		local Result, HasResult = {}, false
		for KeyframeName, KeyframeData in Keyframes do
			local Matches = SearchForInDuration(KeyframeData, Start, End)
			if #Matches > 0 then
				Result[KeyframeName] = Matches
				HasResult = true
			end
		end
		return HasResult and Result or false
	end,
	Destroy = function(self)
		for i,v in self.MarkerSignals do
			v:Destroy()
		end
		
		for i,v in self.KeyframeSignals do
			v:Destroy()
		end
		
		self.Stopped:Destroy()
		self.DidLoop:Destroy()
		self.Ended:Destroy()
		self.KeyframeReachedSignal:Destroy()
	end,
}

local AnimationModule = {
	AnimationLatencyUpdated = AnimationLatencyUpdated
}

function AnimationModule.new(AnimationTrack: AnimationTrack, AnimatorClass, NetworkOwner)
	local self = table.clone(AnimationClass)
	
	self.AnimationTrack = AnimationTrack
	self.NumberId = AnimationData.GetNumberId(AnimationTrack.Animation.AnimationId)
	self.NetworkOwner = NetworkOwner
	self.LatencyQueue = {}
	
	self.AnimatorClass = AnimatorClass
	
	self.KeyframeSignals = {}
	self.MarkerSignals = {}
	
	self.Stopped = Signal.Wrap(AnimationTrack.Stopped)
	self.DidLoop = Signal.Wrap(AnimationTrack.DidLoop)
	self.Ended = Signal.Wrap(AnimationTrack.Ended)
	self.KeyframeReachedSignal = Signal.Wrap(AnimationTrack.KeyframeReached)
	
	self.KeyframeReachedSignal:Connect(function(KeyframeName)
		if self.KeyframeSignals[KeyframeName] then
			self.KeyframeSignals[KeyframeName]:Fire()
		end
	end)
	
	self.ProbablyShouldStoreThisIncaseSomeStupidBugHappens = {
		IsPlayingConnection = AnimationTrack:GetPropertyChangedSignal("IsPlaying"):Connect(function()
			self.IsPlaying = AnimationTrack.IsPlaying
		end)
	}
	
	local Name = AnimationData.GetNumberId(self.NumberId)
	AnimationTrack.Name = Name
	AnimationTrack.Animation.Name = Name
	
	
	task.spawn(function()
		-- Wait for AnimationTrack data to load
		while true do
			self.Speed = AnimationTrack.Speed
			self.Length = AnimationTrack.Length
			self.WeightTarget = AnimationTrack.WeightTarget
			self.IsPlaying = AnimationTrack.IsPlaying
			self.Looped = AnimationTrack.Looped
			self.Priority = AnimationTrack.Priority
						
			if AnimationTrack.Length > 0 then
				break
			end 
			
			task.wait()
		end
	end)
	
	return self
end

return AnimationModule