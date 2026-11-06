--!strict
-- ProceduralAnimation/Client/Runtime/PlayerTracker
-- Player lifecycle tracking for the client runtime.
--
-- Owns three things that used to be inlined in ProceduralAnimator and leaked connections:
--   1. the global Players.PlayerAdded / PlayerRemoving subscriptions,
--   2. per-player CharacterAdded / CharacterRemoving subscriptions,
--   3. the release of all of the above on Destroy.
--
-- Split out of ProceduralAnimator to respect the 500-line limit, and because this is the one
-- place where "who is connected to what" is decided. Keeping it in one module means the leak
-- class that Phase 4 targets can be audited by reading a single file.
--
-- No OOP: this is a factory returning plain functions closed over the caller's dependencies.

return function(Dependencies)
local Players = Dependencies.Players
local Connections = Dependencies.Connections
local SetupCharacter = Dependencies.SetupCharacter
local TeardownCharacter = Dependencies.TeardownCharacter

local PlayersGetPlayers = Players.GetPlayers

local Tracker = {}

-- Global lifecycle connections, and per-player trackers keyed by Player.
local LifecycleConnections = Connections.New()
local PlayerConnections = {}

-- Stops tracking a player and disconnects their two character signals.
function Tracker.UntrackPlayer(Player)
    local PlayerTracker = PlayerConnections[Player]
    if PlayerTracker then
        Connections.DisconnectAll(PlayerTracker)
        PlayerConnections[Player] = nil
    end
end

-- Starts tracking a remote player's character lifetime. Idempotent: tracking the same player
-- twice releases the previous connections first, so a rejoin cannot double-subscribe.
function Tracker.TrackPlayer(Player)
    if Player == Players.LocalPlayer then
        return
    end

    Tracker.UntrackPlayer(Player)

    local PlayerTracker = Connections.New()
    PlayerConnections[Player] = PlayerTracker

    Connections.Add(PlayerTracker, Player.CharacterAdded:Connect(function(Character)
        task.defer(function()
            SetupCharacter(Character)
        end)
    end))
    Connections.Add(PlayerTracker, Player.CharacterRemoving:Connect(function(Character)
        TeardownCharacter(Character)
    end))

    if Player.Character then
        SetupCharacter(Player.Character)
    end
end

-- Subscribes to the global player signals and adopts everyone already present.
-- Safe to call once; repeated calls would double-subscribe, so the animator guards it with its
-- own Initialized flag.
function Tracker.Start()
    local CurrentPlayers = PlayersGetPlayers(Players)
    for Index = 1, #CurrentPlayers do
        Tracker.TrackPlayer(CurrentPlayers[Index])
    end

    Connections.Add(LifecycleConnections, Players.PlayerAdded:Connect(Tracker.TrackPlayer))

    Connections.Add(LifecycleConnections, Players.PlayerRemoving:Connect(function(Player)
        Tracker.UntrackPlayer(Player)
        if Player.Character then
            TeardownCharacter(Player.Character)
        end
    end))
end

-- Releases every global and per-player connection. Idempotent.
function Tracker.Stop()
    for Player in pairs(PlayerConnections) do
        Tracker.UntrackPlayer(Player)
    end
    Connections.DisconnectAll(LifecycleConnections)
end

-- How many global connections are live. The harness asserts this reaches zero after Destroy.
function Tracker.CountLiveConnections()
    return Connections.Count(LifecycleConnections)
end

return Tracker
end
