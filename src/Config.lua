-- For any settings/data that multiple modules need access to

return {
	InitializedPlayers = {},
	CurrentUUID = 0,
	RemoteDelay = 1/20,
	MaxConcurrentAnimations = 15,


	AlwaysResetAnimationSpeed = false,
	PreventDuplicateLoading = true,
	MimicNativeStopMethod = false,
	DestroyAnimatorUponModelDestroying = true,
}