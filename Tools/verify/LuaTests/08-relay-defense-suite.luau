--!strict
--[[
    Tools/verify/LuaTests/08-relay-defense-suite.luau

    Relay defense: the server-side token-bucket rate limiter and the registered-player
    gate on the event channel. Buckets derive from Config.SendRate and read
    Constants.Clock, so every case is deterministic under the harness virtual clock.

    Suites share one VM and one set of remotes (ReplicatedStorage.Remotes persists
    across suites; re-initialising the module is idempotent), and the relay fires one
    FireClient per *other registered player*. Absolute ServerSentCount values therefore
    depend on how many players earlier suites registered, so the assertions here use
    probe deltas: fire one packet, measure the relay delta, then assert the burst
    behaviour relative to that probe. This is exact, never a timing tolerance.
]]

return function(Env, Kit)
local Suite = { Name = "relaydefense" }

local SHARED = "ReplicatedStorage.ProceduralAnimation.Shared."
local NETWORK_PATH = SHARED .. "AnimationNetwork"
local RECEIVE_PATH = SHARED .. "AnimationNetworkReceive"

local Network, Constants, Config, PoseRemote, EventRemote

local function FreshServer()
    Env.SetServerMode(true)
    Env.PurgeCache(NETWORK_PATH)
    Env.PurgeCache(RECEIVE_PATH)
    Env.PurgeCache(SHARED .. "Networking.Constants.NetworkConstants")
    Network = Env.Require(NETWORK_PATH)
    Constants = Env.Require(SHARED .. "Networking.Constants.NetworkConstants")
    Config = Env.Require(SHARED .. "AnimationConfig")
    Network.Init() -- idempotent; handlers already exist on the shared remotes
    PoseRemote = Env.GetRemote("PoseRemote")
    EventRemote = Env.GetRemote("EventRemote")
end

function Suite.Reset()
    FreshServer()
end

local function MakePoseBuffer(JointCount, Value)
    local PoseBuffer = buffer.create(Constants.MaxJoints * 12)
    for Joint = 1, JointCount do
        local Offset = (Joint - 1) * 12
        buffer.writef32(PoseBuffer, Offset, Value)
        buffer.writef32(PoseBuffer, Offset + 4, -Value)
        buffer.writef32(PoseBuffer, Offset + 8, Value * 0.5)
    end
    return PoseBuffer
end

function Suite.Body(Cases)
    Kit.Begin(Cases, "relaydefense.")

    FreshServer()

    local Sender = Env.CreatePlayer("DefenseSender", 201)
    local Receiver = Env.CreatePlayer("DefenseReceiver", 202)
    Env.AddPlayer(Sender)
    Env.AddPlayer(Receiver)
    Network.RegisterPlayer(Sender)
    Network.RegisterPlayer(Receiver)

    local SenderCharacter = Env.CreateCharacter("DefenseSenderCharacter", { IncludeChest = true })
    Env.SetCharacter(Sender, SenderCharacter)
    local RootPosition = _G.Vector3.new(0.0, 3.0, 0.0)
    local RootVelocity = _G.Vector3.new(0.0, 0.0, 0.0)
    local PoseBuffer = MakePoseBuffer(4, 0.25)
    local SendRate = math.floor(Config.SendRate)

    local NowSequence = 1000000 -- above anything earlier suites ever sent
    PoseRemote.Sender = Sender
    local function FirePose()
        NowSequence += 1
        Network.SendPose(NowSequence, 1, RootPosition, RootVelocity, PoseBuffer, 4)
    end
    local function PoseCount()
        return PoseRemote.ServerSentCount
    end

    -- Probe: one packet under the limit must relay. The probe delta is the reference
    -- relay cost for this VM (one FireClient per other registered player).
    local BeforeProbe = PoseCount()
    FirePose()
    local Probe = PoseCount() - BeforeProbe
    Kit.True("burst.probeRelays", Probe >= 1, "a registered sender under the limit relays")

    -- A burst of at most the send-rate capacity relays in full (probe consumed 1 token).
    local BeforeBurst = PoseCount()
    for _ = 1, SendRate - 1 do
        FirePose()
    end
    Kit.Equal("burst.underOrAtCapacityRelays", PoseCount(), BeforeBurst + Probe * (SendRate - 1))

    -- One packet past the capacity is dropped before any decode work happens.
    local BeforeOver = PoseCount()
    FirePose()
    Kit.Equal("burst.overCapacityDropped", PoseCount(), BeforeOver)

    -- Idle buckets clamp at the burst: a long idle refills to (and never past) capacity.
    Env.AdvanceClock(100.0)
    local BeforeIdle = PoseCount()
    for _ = 1, SendRate + 5 do
        FirePose()
    end
    Kit.Equal("refill.idleClampsAtBurst", PoseCount(), BeforeIdle + Probe * SendRate)

    -- Full-second refill restores exactly one burst of capacity.
    Env.AdvanceClock(1.0)
    local BeforeRefill = PoseCount()
    for _ = 1, SendRate do
        FirePose()
    end
    Kit.Equal("refill.fullSecondRestoresCapacity", PoseCount(), BeforeRefill + Probe * SendRate)

    -- Sequence gate is independent of tokens: a stale sequence is dropped even though
    -- the second advance just refilled every token.
    Env.AdvanceClock(1.0)
    local BeforeStale = PoseCount()
    Network.SendPose(1, 1, RootPosition, RootVelocity, PoseBuffer, 4)
    Kit.Equal("guard.sequenceGateIndependentOfTokens", PoseCount(), BeforeStale)

    --=========================================================
    -- EVENT RELAY GATE + LIMITER (same VM, fresh burst)
    --=========================================================
    local function EventCount()
        return EventRemote.ServerSentCount
    end
    EventRemote.Sender = Receiver

    -- Probe: a registered sender's event relays.
    local BeforeEventProbe = EventCount()
    EventRemote:FireServer(Config.EventId.ClipStart, 1)
    local EventProbe = EventCount() - BeforeEventProbe
    Kit.True("events.registeredRelays", EventProbe >= 1)

    -- A flood of exactly the burst relays; one event more is dropped.
    Env.AdvanceClock(1.0) -- refill to the burst first
    local BeforeFlood = EventCount()
    for _ = 1, SendRate do
        EventRemote:FireServer(Config.EventId.ClipStart, 1)
    end
    Kit.Equal("events.floodWithinBurstRelays", EventCount(), BeforeFlood + EventProbe * SendRate)
    EventRemote:FireServer(Config.EventId.ClipStart, 1)
    Kit.Equal("events.floodOverBurstDropped", EventCount(), BeforeFlood + EventProbe * SendRate)

    -- An unregistered sender's event is ignored, for the same reason poses are.
    local Unregistered = Env.CreatePlayer("DefenseUnregistered", 213)
    Env.AddPlayer(Unregistered)
    EventRemote.Sender = Unregistered
    local BeforeUnreg = EventCount()
    EventRemote:FireServer(Config.EventId.ClipStart, 1)
    Kit.Equal("events.unregisteredDropped", EventCount(), BeforeUnreg)

    -- An unregistered sender's pose is ignored even with a full bucket (registry gates first).
    PoseRemote.Sender = Unregistered
    local BeforeUnregPose = PoseCount()
    Env.AdvanceClock(1.0)
    Network.SendPose(NowSequence + 1, 1, RootPosition, RootVelocity, PoseBuffer, 4)
    Kit.Equal("poses.unregisteredDropped", PoseCount(), BeforeUnregPose)
end

return Suite
end
