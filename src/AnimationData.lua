local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

local BlacklistedAnimations = {
	FallAnim = true,
	IdleAnim = true,
	Animation1 = true,
	Animation2 = true,
	JumpAnim = true,
	ClimbAnim = true,
	SitAnim = true,
	RunAnim = true,
	ToolNoneAnim = true,
	WalkAnim = true,
	ToolNonAnim = true,
	ToolLungeAnim = true,
	ToolSlashAnim = true,
	WaveAnim = true,
	Swim = true,
	SwimIdle = true,
	LaughAnim = true,
	PointAnim = true,
	ToyPose = true,
	CheerAnim = true,
	Animation3 = true,
}

local AnimationData = {}
local IdCache, DataCache = {}, {}
local GsubCache = {}

function AnimationData.GetNumberId(AnimationId: string)
	if IdCache[AnimationId] then
		return IdCache[AnimationId]
	else
		local id = GsubCache[AnimationId] or string.gsub(AnimationId, "%S", function(a) 
			return tonumber(a) and a or ""
		end)
		
		local numberId = tonumber(id)

		if not numberId then
			return warn("No Id found for", AnimationId)
		else
			GsubCache[AnimationId] = numberId
			return numberId
		end
	end
end

function AnimationData.GetNameFromId(AnimationId: string | number)
	return IdCache[AnimationData.GetNumberId(AnimationId)]
end

function AnimationData.GetIdFromName(AnimationName: string)
	return IdCache[AnimationName] or warn("Animation not found")
end

function AnimationData.GetCachedData(AnimationId: string | number)
	return DataCache[type(AnimationId) == "number" and AnimationId or AnimationData.GetNumberId(AnimationId)]
end

local function GetAnimationData(Animation: Animation)
	local NumberId = AnimationData.GetNumberId(Animation.AnimationId)
	if DataCache[NumberId] then return end

	IdCache[NumberId] = Animation.Name
	IdCache[Animation.Name] = IdCache[Animation.Name] or {}
	IdCache[Animation.Name][NumberId] = true
	
	local KeyframeSequence = KeyframeSequenceProvider:GetKeyframeSequenceAsync(Animation.AnimationId)

	local Index = 1
	local MarkerCache, KeyframeCache = {}, {}
	local Children = KeyframeSequence:GetChildren()

	while Index <= #Children do
		if not Children[Index]:IsA("Keyframe") then
			table.remove(Children, Index)
		else
			Index += 1
		end
	end

	table.sort(Children, function(a1, a2)
		return a1.Time < a2.Time
	end)

	for _, Keyframe: Keyframe in Children do
		local Markers = Keyframe:GetMarkers()

		if #Markers > 0 then
			for _, Marker in Markers do
				MarkerCache[Marker.Name] = MarkerCache[Marker.Name] or {}
				table.insert(MarkerCache[Marker.Name], Keyframe.Time)
			end
		end

		if Keyframe.Name ~= "Keyframe" then
			KeyframeCache[Keyframe.Name] = KeyframeCache[Keyframe.Name] or {}
			table.insert(KeyframeCache[Keyframe.Name], Keyframe.Time)
		end
	end

	local RetrievedData = {
		Markers = MarkerCache,
		Keyframes = KeyframeCache,
	}

	DataCache[NumberId] = RetrievedData
end

local Yield = 0
local function CheckIfAnimation(v)
	if v:IsA("Animation") then
		if BlacklistedAnimations[v.Name] then
			return
		end
		
		task.spawn(function()
			Yield+=1
			xpcall(GetAnimationData, warn, v)
			Yield-=1
		end)
	end
end

game.DescendantAdded:Connect(CheckIfAnimation)

local a = os.clock()
for _, Obj in game:GetDescendants() do
	CheckIfAnimation(Obj)
end

warn("AnimationData Initialized", os.clock()-a)
print(IdCache, DataCache)


AnimationData.DataCache = DataCache
AnimationData.IdCache = IdCache

return AnimationData