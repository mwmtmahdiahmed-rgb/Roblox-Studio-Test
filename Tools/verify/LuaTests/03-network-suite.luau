--[[
    Tools/verify/LuaTests/03-network-suite.luau

    Behavioural tests for the networking layer:
      AnimationNetwork, AnimationNetworkConstants, AnimationNetworkReceive.

    The suite runs the module twice inside one VM: once in server mode to exercise the send
    path, validation and relay, then again in client mode to exercise the jitter buffer and
    the render-time sampler. That is possible because the harness can purge a module from the
    require cache and re-require it under a different RunService identity.

    The packet codec is checked byte by byte against the documented layout, so any change to
    the wire format is caught rather than silently accepted.
]]

return function(Env, Kit)
local Suite = { Name = "network" }

local SHARED = "ReplicatedStorage.ProceduralAnimation.Shared."
local NETWORK_PATH = SHARED .. "AnimationNetwork"
local RECEIVE_PATH = SHARED .. "AnimationNetworkReceive"

local Network = nil
local Constants = nil
local Config = nil

local function FreshServer()
    Env.SetServerMode(true)
    Env.PurgeCache(NETWORK_PATH)
    Env.PurgeCache(RECEIVE_PATH)
    Env.PurgeCache(SHARED .. "AnimationNetworkConstants")
    Network = Env.Require(NETWORK_PATH)
    Constants = Env.Require(SHARED .. "AnimationNetworkConstants")
    Config = Env.Require(SHARED .. "AnimationConfig")
    Network.Init()
    return Network
end

local function FreshClient()
    Env.SetServerMode(false)
    Env.PurgeCache(NETWORK_PATH)
    Env.PurgeCache(RECEIVE_PATH)
    Env.PurgeCache(SHARED .. "AnimationNetworkConstants")
    Network = Env.Require(NETWORK_PATH)
    Constants = Env.Require(SHARED .. "AnimationNetworkConstants")
    return Network
end

function Suite.Reset()
    Config = Env.Require(SHARED .. "AnimationConfig")
    Constants = Env.Require(SHARED .. "AnimationNetworkConstants")
    FreshServer()
end

local function MakePoseBuffer(JointCount, ValuePerJoint)
    local PoseBuffer = buffer.create(Constants.MaxJoints * 12)
    for Joint = 1, JointCount do
        local Offset = (Joint - 1) * 12
        buffer.writef32(PoseBuffer, Offset, ValuePerJoint)
        buffer.writef32(PoseBuffer, Offset + 4, -ValuePerJoint)
        buffer.writef32(PoseBuffer, Offset + 8, ValuePerJoint * 0.5)
    end
    return PoseBuffer
end

function Suite.Body(Cases)
    Kit.Begin(Cases, "network.")

    --=========================================================
    -- [1] PACKET LAYOUT
    --=========================================================

    Kit.Equal("layout.headerOffset", Constants.HeaderOffset, 0)
    Kit.Equal("layout.sequenceOffset", Constants.SequenceOffset, 1)
    Kit.Equal("layout.tickOffset", Constants.TickOffset, 3)
    Kit.Equal("layout.rootPositionOffset", Constants.RootPositionOffset, 7)
    Kit.Equal("layout.rootVelocityOffset", Constants.RootVelocityOffset, 13)
    Kit.Equal("layout.jointCountOffset", Constants.JointCountOffset, 19)
    Kit.Equal("layout.jointDataOffset", Constants.JointDataOffset, 20)
    Kit.Equal("layout.bytesPerJoint", Constants.BytesPerJoint, 6, "3 x int16 Euler")
    Kit.Equal("layout.sendBufferSize", Constants.SendBufferSize, 20 + 16 * 6, "116 bytes for 16 joints")
    Kit.Less("layout.underUnreliableLimit", Constants.SendBufferSize, 900, "well inside the unreliable payload cap")
    Kit.Equal("layout.packetPose", Constants.PacketPose, 1)
    Kit.Equal("layout.packetEvent", Constants.PacketEvent, 2)
    Kit.Equal("layout.sequenceModulus", Constants.SequenceModulus, 65536)

    Kit.Near("quantisation.roundTrip", Constants.ReadClampedI16(
        (function()
            local Scratch = buffer.create(2)
            Constants.WriteClampedI16(Scratch, 0, 1.25 * Constants.AngleQuantization)
            return Scratch
        end)(), 0, Constants.AngleDequantization), 1.25, 1e-4, "i16 angle encode/decode")

    local ClampScratch = buffer.create(2)
    Constants.WriteClampedI16(ClampScratch, 0, 1e9)
    Kit.Equal("quantisation.clampsHigh", buffer.readi16(ClampScratch, 0), 32767)
    Constants.WriteClampedI16(ClampScratch, 0, -1e9)
    Kit.Equal("quantisation.clampsLow", buffer.readi16(ClampScratch, 0), -32767)
    Constants.WriteClampedI16(ClampScratch, 0, 0.0 / 0.0)
    Kit.Equal("quantisation.nanBecomesZero", buffer.readi16(ClampScratch, 0), 0, "NaN is rejected, not encoded")

    --=========================================================
    -- [2] SERVER INITIALISATION
    --=========================================================

    Kit.True("server.init", Network.IsReady())
    Kit.True("server.isServer", Constants.IsServer)

    local PoseRemote = Env.GetRemote("PoseRemote")
    local EventRemote = Env.GetRemote("EventRemote")
    local BusRemote = Env.GetRemote("AnimationBus")
    Kit.NotNil("server.poseRemote", PoseRemote, "UnreliableRemoteEvent under ProceduralAnimation/Remotes")
    Kit.NotNil("server.eventRemote", EventRemote, "RemoteEvent under ProceduralAnimation/Remotes")
    Kit.NotNil("server.bus", BusRemote, "BindableEvent under ProceduralAnimation/Remotes")
    if PoseRemote then
        Kit.Equal("server.poseRemoteClass", PoseRemote.ClassName, "UnreliableRemoteEvent")
    end

    -- Init is idempotent: a second call must not attach a second set of handlers.
    local HandlerCountBefore = PoseRemote and PoseRemote.OnServerEvent.Count or -1
    Network.Init()
    local HandlerCountAfter = PoseRemote and PoseRemote.OnServerEvent.Count or -1
    Kit.Equal("server.initIdempotent", HandlerCountAfter, HandlerCountBefore, "no duplicate OnServerEvent")

    --=========================================================
    -- [3] C2S SEND PATH + DECODE
    --=========================================================

    local Sender = Env.CreatePlayer("Sender", 101)
    local Receiver = Env.CreatePlayer("Receiver", 102)
    Env.AddPlayer(Sender)
    Env.AddPlayer(Receiver)
    Network.RegisterPlayer(Sender)
    Network.RegisterPlayer(Receiver)

    local SenderCharacter = Env.CreateCharacter("SenderCharacter", { IncludeChest = true })
    Env.SetCharacter(Sender, SenderCharacter)
    local ReceiverCharacter = Env.CreateCharacter("ReceiverCharacter", { IncludeChest = true })
    Env.SetCharacter(Receiver, ReceiverCharacter)

    -- Put both characters at the origin so the server-side root sanity check passes.
    local RootPosition = _G.Vector3.new(0.0, 3.0, 0.0)
    local RootVelocity = _G.Vector3.new(1.5, 0.0, -2.5)

    local JointCount = 16
    local PoseBuffer = MakePoseBuffer(JointCount, 0.5)

    PoseRemote.Sender = Sender
    Network.SendPose(7, 1234, RootPosition, RootVelocity, PoseBuffer, JointCount)

    local Packet = PoseRemote.LastClientPayload and PoseRemote.LastClientPayload[1] or nil
    Kit.NotNil("send.packetPresent", Packet)
    if Packet then
        Kit.Equal("send.packetType", typeof(Packet), "buffer")
        Kit.Equal("send.packetLength", buffer.len(Packet), Constants.SendBufferSize)
        Kit.Equal("send.header", buffer.readu8(Packet, 0), Constants.PacketPose)
        Kit.Equal("send.sequence", buffer.readu16(Packet, 1), 7)
        Kit.Equal("send.tick", buffer.readu32(Packet, 3), 1234)
        Kit.Equal("send.jointCount", buffer.readu8(Packet, 19), JointCount)

        local RootX = buffer.readi16(Packet, 7) * Constants.PositionInverse
        Kit.Near("send.rootX", RootX, 0.0, 0.02)
        local VelocityZ = buffer.readi16(Packet, 17) * Constants.PositionInverse
        Kit.Near("send.rootVelocityZ", VelocityZ, -2.5, 0.03, "velocity scale 64")

        local FirstJointX = buffer.readi16(Packet, Constants.JointDataOffset) * Constants.AngleDequantization
        Kit.Near("send.firstJointX", FirstJointX, 0.5, 1e-4)
        local FirstJointY = buffer.readi16(Packet, Constants.JointDataOffset + 2) * Constants.AngleDequantization
        Kit.Near("send.firstJointY", FirstJointY, -0.5, 1e-4)
        local FirstJointZ = buffer.readi16(Packet, Constants.JointDataOffset + 4) * Constants.AngleDequantization
        Kit.Near("send.firstJointZ", FirstJointZ, 0.25, 1e-4)

        local LastJointOffset = Constants.JointDataOffset + (JointCount - 1) * Constants.BytesPerJoint
        local LastJointX = buffer.readi16(Packet, LastJointOffset) * Constants.AngleDequantization
        Kit.Near("send.lastJointX", LastJointX, 0.5, 1e-4, "the 16th joint fits inside the buffer")
    end

    -- The server relays to every player except the sender.
    Kit.Equal("relay.sentOnce", PoseRemote.ServerSentCount, 1)
    Kit.Equal("relay.targetIsOtherPlayer", PoseRemote.LastServerTarget, Receiver)
    Kit.Nil("relay.notEchoedToSender", (function()
        for Index = 1, PoseRemote.ServerFireHistoryCount do
            if PoseRemote.ServerFireHistory[Index][1] == Sender then
                return true
            end
        end
        return nil
    end)(), "sender never receives its own pose back")

    --=========================================================
    -- [4] PACKET VALIDATION (defect N-01 regression guards)
    --=========================================================

    local SentBefore = PoseRemote.ServerSentCount

    -- (a) A packet whose declared JointCount needs more bytes than were sent must be dropped
    --     before any joint byte is read. Without the length check this decodes past the end.
    local Truncated = buffer.create(Constants.JointDataOffset + 2)
    buffer.writeu8(Truncated, 0, Constants.PacketPose)
    buffer.writeu16(Truncated, 1, 8)
    buffer.writeu32(Truncated, 3, 1)
    buffer.writeu8(Truncated, 19, 16)
    Kit.Guard("validation.truncatedPacketDoesNotThrow", function()
        PoseRemote.Sender = Sender
        PoseRemote:FireServer(Truncated)
        return true
    end)
    Kit.Equal("validation.truncatedPacketDropped", PoseRemote.ServerSentCount, SentBefore,
        "a packet shorter than JointDataOffset + JointCount * BytesPerJoint is rejected")

    -- (b) Header mismatch.
    local WrongHeader = buffer.create(Constants.SendBufferSize)
    buffer.writeu8(WrongHeader, 0, 99)
    PoseRemote:FireServer(WrongHeader)
    Kit.Equal("validation.wrongHeaderDropped", PoseRemote.ServerSentCount, SentBefore)

    -- (c) JointCount above MaxJoints.
    local TooManyJoints = buffer.create(Constants.SendBufferSize)
    buffer.writeu8(TooManyJoints, 0, Constants.PacketPose)
    buffer.writeu8(TooManyJoints, 19, Constants.MaxJoints + 1)
    PoseRemote:FireServer(TooManyJoints)
    Kit.Equal("validation.jointCountOverflowDropped", PoseRemote.ServerSentCount, SentBefore)

    -- (d) Zero joints.
    local NoJoints = buffer.create(Constants.SendBufferSize)
    buffer.writeu8(NoJoints, 0, Constants.PacketPose)
    buffer.writeu8(NoJoints, 19, 0)
    PoseRemote:FireServer(NoJoints)
    Kit.Equal("validation.zeroJointCountDropped", PoseRemote.ServerSentCount, SentBefore)

    -- (e) Stale / out of order sequence numbers.
    PoseRemote.Sender = Sender
    local SequencePose = MakePoseBuffer(4, 0.1)
    Network.SendPose(20, 1, RootPosition, RootVelocity, SequencePose, 4)
    local AfterFresh = PoseRemote.ServerSentCount
    Network.SendPose(20, 2, RootPosition, RootVelocity, SequencePose, 4)
    Kit.Equal("validation.replayedSequenceDropped", PoseRemote.ServerSentCount, AfterFresh,
        "a repeated sequence number is dropped")
    Network.SendPose(19, 3, RootPosition, RootVelocity, SequencePose, 4)
    Kit.Equal("validation.olderSequenceDropped", PoseRemote.ServerSentCount, AfterFresh,
        "an out of order sequence number is dropped")
    Network.SendPose(21, 4, RootPosition, RootVelocity, SequencePose, 4)
    Kit.Equal("validation.forwardSequenceAccepted", PoseRemote.ServerSentCount, AfterFresh + 1)

    -- (f) A non-buffer payload from a client must not throw.
    Kit.Guard("validation.nonBufferIgnored", function()
        PoseRemote:FireServer("definitely not a buffer")
        PoseRemote:FireServer(nil)
        return true
    end)

    -- (g) Root position sanity: a teleport-sized offset is rejected.
    local BeforeTeleport = PoseRemote.ServerSentCount
    local TeleportPacket = buffer.create(Constants.SendBufferSize)
    buffer.writeu8(TeleportPacket, 0, Constants.PacketPose)
    buffer.writeu16(TeleportPacket, 1, 40)
    buffer.writeu32(TeleportPacket, 3, 1)
    -- root position at 900 studs on X, far beyond Config.SanityRootThreshold
    buffer.writei16(TeleportPacket, 7, math.floor(900 * Constants.PositionScale))
    buffer.writeu8(TeleportPacket, 19, 4)
    PoseRemote:FireServer(TeleportPacket)
    Kit.Equal("validation.teleportRejected", PoseRemote.ServerSentCount, BeforeTeleport,
        "root offset beyond SanityRootThreshold is not relayed")

    --=========================================================
    -- [5] S2C EVENT RELAY
    --=========================================================

    local EventCountBefore = EventRemote.ServerSentCount
    EventRemote.Sender = Sender
    EventRemote:FireServer(Config.EventId.ClipStart, 1)
    Kit.Equal("events.relayed", EventRemote.ServerSentCount, EventCountBefore + 1)
    Kit.Equal("events.target", EventRemote.LastServerTarget, Receiver)

    local EventsBeforeInvalid = EventRemote.ServerSentCount
    EventRemote:FireServer(0, 1)
    EventRemote:FireServer(999, 1)
    EventRemote:FireServer("bad", 1)
    Kit.Equal("events.rejectsOutOfRangeIds", EventRemote.ServerSentCount, EventsBeforeInvalid,
        "only ids inside 1..MaxEventId are relayed")

    --=========================================================
    -- [6] PLAYER REGISTRY
    --=========================================================

    local Third = Env.CreatePlayer("Third", 103)
    Env.AddPlayer(Third)
    Network.RegisterPlayer(Third)
    Network.RegisterPlayer(Third)
    Kit.Guard("registry.doubleRegisterSafe", function()
        Network.UnregisterPlayer(Third)
        return true
    end)
    Network.UnregisterPlayer(Third)
    Kit.Guard("registry.doubleUnregisterSafe", function()
        Network.UnregisterPlayer(Third)
        return true
    end)

    -- An unregistered player's pose must not be relayed.
    local Unregistered = Env.CreatePlayer("Unregistered", 104)
    Env.AddPlayer(Unregistered)
    local BeforeUnregistered = PoseRemote.ServerSentCount
    PoseRemote.Sender = Unregistered
    Network.SendPose(50, 1, RootPosition, RootVelocity, SequencePose, 4)
    Kit.Equal("registry.unregisteredDropped", PoseRemote.ServerSentCount, BeforeUnregistered)

    --=========================================================
    -- [7] CLIENT RECEIVE PATH
    --=========================================================

    FreshClient()
    Network.Init()
    Kit.True("client.init", Network.IsReady())
    Kit.True("client.isClient", not Constants.IsServer)

    local ClientPoseRemote = Env.GetRemote("PoseRemote")
    Kit.NotNil("client.poseRemoteReplicated", ClientPoseRemote)

    -- No pose yet for this player.
    local OutPose = buffer.create(Constants.MaxJoints * 12)
    Kit.False("client.noPoseBeforePacket", Network.HasRemotePose(Sender))
    Kit.False("client.sampleWithoutPose", Network.SampleRemotePose(Sender, OutPose))

    -- Deliver real encoded packets through the remote, exactly as the server would.
    -- The jitter buffer is a two-packet window: the first packet populates Current while
    -- Previous still holds the zeroed allocation, so sampling only becomes meaningful once a
    -- second packet has shifted the window. That is the documented JitterBufferDepth latency.
    local ClientReceiveRemote = Env.GetRemote("PoseRemote")
    Kit.NotNil("client.receiveRemote", ClientReceiveRemote)

    PoseRemote.Sender = Sender
    local ClientJointCount = 4
    local FirstPose = MakePoseBuffer(ClientJointCount, 0.75)
    Network.SendPose(1, 1000, RootPosition, RootVelocity, FirstPose, ClientJointCount)
    local FirstPacket = PoseRemote.LastClientPayload[1]
    ClientReceiveRemote:FireClient(Receiver, Sender, FirstPacket)
    Kit.True("client.firstPacketAccepted", Network.HasRemotePose(Sender))

    Env.AdvanceClock(1.0 / 30.0)
    local SecondPose = MakePoseBuffer(ClientJointCount, 1.25)
    Network.SendPose(2, 1033, RootPosition, RootVelocity, SecondPose, ClientJointCount)
    local SecondPacket = PoseRemote.LastClientPayload[1]
    ClientReceiveRemote:FireClient(Receiver, Sender, SecondPacket)

    -- Sample inside the interpolation window: render time is shifted back by JitterBufferDepth.
    Env.AdvanceClock(Config.JitterBufferDepth * 0.5)
    local Sampled = Network.SampleRemotePose(Sender, OutPose)
    Kit.True("client.sampleSucceeds", Sampled)
    local SampledX = buffer.readf32(OutPose, 0)
    Kit.True("client.interpolatesBetweenPackets", SampledX >= 0.74 and SampledX <= 1.26,
        string.format("sampled %.4f between 0.75 and 1.25", SampledX))
    local SampledY = buffer.readf32(OutPose, 4)
    Kit.True("client.interpolatesNegatedAxis", SampledY <= -0.74 and SampledY >= -1.26,
        string.format("sampled %.4f between -1.25 and -0.75", SampledY))

    -- Only the declared joint count is written; the remainder of the pose buffer is untouched.
    local UnwrittenOffset = ClientJointCount * 12
    Kit.Near("client.unwrittenJointsStayZero", buffer.readf32(OutPose, UnwrittenOffset), 0.0, 0.0,
        "4 joints decoded, joint 5 onwards still zero")

    -- Sampling is clamp-guarded at both ends of the window.
    Env.AdvanceClock(10.0)
    local LateSample = Network.SampleRemotePose(Sender, OutPose)
    local LateX = buffer.readf32(OutPose, 0)
    Kit.True("client.lateSampleHoldsLatest", LateSample and math.abs(LateX - 1.25) < 0.05,
        string.format("held %.4f once the window elapsed", LateX))

    -- A truncated packet from the server must be dropped, not decoded past the buffer end.
    local ClientTruncated = buffer.create(Constants.JointDataOffset + 3)
    buffer.writeu8(ClientTruncated, 0, Constants.PacketPose)
    buffer.writeu16(ClientTruncated, 1, 3)
    buffer.writeu8(ClientTruncated, 19, 16)
    local AcceptedBefore = Network.HasRemotePose(Sender)
    Kit.Guard("client.truncatedPacketDoesNotThrow", function()
        ClientReceiveRemote:FireClient(Receiver, Sender, ClientTruncated)
        return true
    end)
    Kit.True("client.stateSurvivesMalformedPacket", Network.HasRemotePose(Sender) == AcceptedBefore)

    -- Release removes the receive state entirely.
    Network.ReleaseRemotePose(Sender)
    Kit.False("client.releaseDropsState", Network.HasRemotePose(Sender))
    local ReleasedSample = Network.SampleRemotePose(Sender, OutPose)
    Kit.False("client.sampleAfterRelease", ReleasedSample)
end

return Suite
end
