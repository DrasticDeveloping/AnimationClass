local RunService = game:GetService("RunService")
local IsClient, IsServer = RunService:IsClient(), RunService:IsServer()

local Config = require(script.Parent:WaitForChild("Config"))
local InitializedPlayers = Config.InitializedPlayers

return {
	FireAll = function(Remote, ...)
		if IsServer then
			for Player, _ in InitializedPlayers do
				Remote:FireClient(Player, ...)
			end
		elseif IsClient then
			Remote:FireServer(...)
		end
	end,
	
	FirePlayersExcept = function(Remote, Exclusion, ...)
		for Player, _ in InitializedPlayers do
			if Player == Exclusion then continue end
			Remote:FireClient(Player, ...)
		end
	end,
}