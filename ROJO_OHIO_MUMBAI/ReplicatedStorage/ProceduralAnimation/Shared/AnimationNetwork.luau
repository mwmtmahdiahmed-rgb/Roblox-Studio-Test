--!strict
-- ProceduralAnimation/Shared/AnimationNetwork
-- Owns every remote, the bindable event bus and the server relay.
-- (UnreliableRemoteEvent: poses; RemoteEvent: one-shots; BindableEvent: same-side bus.)
-- Split for the line cap: packet layout + math aliases live in AnimationNetworkConstants,
-- client jitter buffers in AnimationNetworkReceive; public surface and packet layout unchanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Constants caches the unbound GetPlayers method; pass the service instance (PlayersGetPlayers(Players)).
local Players = game:GetService("Players")

local Config = require(script.Parent.AnimationConfig)
local Changelog = require(script.Parent.Changelog)
local Connections = require(script.Parent.Utilities.Connections)
local Constants = require(script.Parent.Networking.Constants.NetworkConstants)

local Network: { [string]: any } = {}
local Private: { [string]: any } = {}

-- NetworkReceive writes HasRemotePose/SampleRemotePose/ReleaseRemotePose onto Network.
require(script.Parent.Networking.Receive.NetworkReceive)(Network, Private)
local OnClientPose = Private.OnClientPose

local IsServer = Constants.IsServer
local IsClient = Constants.IsClient
local BufferCreate = Constants.BufferCreate
local BufferLen = Constants.BufferLen
local BufferReadU8 = Constants.BufferReadU8
local BufferWriteU8 = Constants.BufferWriteU8
local BufferReadU16 = Constants.BufferReadU16
local BufferWriteU16 = Constants.BufferWriteU16
local BufferWriteU32 = Constants.BufferWriteU32
local BufferReadI16 = Constants.BufferReadI16
local BufferReadF32 = Constants.BufferReadF32
local Abs = Constants.Abs
local Sqrt = Constants.Sqrt
local TypeOf = Constants.TypeOf
local InstanceNew = Constants.InstanceNew
local PlayersGetPlayers = Constants.PlayersGetPlayers
local PacketPose = Constants.PacketPose
local SequenceModulus = Constants.SequenceModulus
local HeaderOffset = Constants.HeaderOffset
local SequenceOffset = Constants.SequenceOffset
local TickOffset = Constants.TickOffset
local RootPositionOffset = Constants.RootPositionOffset
local RootVelocityOffset = Constants.RootVelocityOffset
local JointCountOffset = Constants.JointCountOffset
local JointDataOffset = Constants.JointDataOffset
local BytesPerJoint = Constants.BytesPerJoint
local MaxJoints = Constants.MaxJoints
local SendBufferSize = Constants.SendBufferSize
local AngleQuantization = Constants.AngleQuantization
local AngleDequantization = Constants.AngleDequantization
local PositionScale = Constants.PositionScale
local PositionInverse = Constants.PositionInverse
local VelocityScale = Constants.VelocityScale
local MaxAngleRadians = Constants.MaxAngleRadians
local WriteClampedI16 = Constants.WriteClampedI16
local ReadClampedI16 = Constants.ReadClampedI16
local Clock = Constants.Clock

--=========================================================
-- [2] BUFFERS
--=========================================================

local SendBuffer = BufferCreate(SendBufferSize) -- created once at load, reused every frame

-- Server relay bookkeeping: array-indexed player list, swap-removed on leave.
local ServerPlayerStates: { [any]: any } = {}
local ServerPlayerCount = 0
local ServerPlayerList: { [number]: any } = {}

local Initialized = false
local Shutdown = false
local PoseRemote: any = nil
local EventRemote: any = nil

-- Connections are recorded here so Shutdown can release them all.
local ConnectionTracker = Connections.New()
local BusEvent: any = nil
local RemotesFolder: any = nil

--=========================================================
-- [3] EVENT BUS (local, same side)
--=========================================================

local BusListeners: { [number]: { (any) -> () } } = {}
for EventId = 1, Config.MaxEventId do
    BusListeners[EventId] = {}
end

local function FireBus(EventId: number, Value: any): ()
    if BusEvent then
        BusEvent:Fire(EventId, Value)
    end
    local List = BusListeners[EventId]
    if List then
        for Index = 1, #List do
            List[Index](Value)
        end
    end
end
Network.FireBus = FireBus

function Network.BindLocal(EventId: number, Callback: (any) -> ()): ()
    local List = BusListeners[EventId]
    if not List then
        Changelog.Log("BindLocal: unknown event id " .. tostring(EventId))
        return
    end
    List[#List + 1] = Callback
end

--=========================================================
-- [5] REMOTE RESOLUTION
--=========================================================

local function ResolveRemotes(): boolean
    local Root = ReplicatedStorage:FindFirstChild("ProceduralAnimation")
    if not Root and IsClient then
        Root = ReplicatedStorage:WaitForChild("ProceduralAnimation", 15)
    end
    if not Root then
        return false
    end

    RemotesFolder = Root:FindFirstChild("Remotes")
    if not RemotesFolder and IsServer then
        RemotesFolder = InstanceNew("Folder")
        RemotesFolder.Name = "Remotes"
        RemotesFolder.Parent = Root
    end
    if not RemotesFolder and IsClient then
        RemotesFolder = Root:WaitForChild("Remotes", 15)
    end

    return RemotesFolder ~= nil
end

local function EnsureRemote(ClassName: string, Name: string): any
    local Existing = RemotesFolder:FindFirstChild(Name)
    if Existing then
        return Existing
    end
    local Created = InstanceNew(ClassName)
    Created.Name = Name
    Created.Parent = RemotesFolder
    return Created
end

--=========================================================
-- [6] SEND PATH (client)
--=========================================================

function Network.SendPose(Sequence: number, TickMilliseconds: number, RootPosition: any, RootVelocity: any, PoseBuffer: buffer, JointCount: number): ()
    if not PoseRemote then
        return
    end
    if JointCount > MaxJoints then
        JointCount = MaxJoints
    end

    local Packet = SendBuffer
    BufferWriteU8(Packet, HeaderOffset, PacketPose)
    BufferWriteU16(Packet, SequenceOffset, Sequence)
    BufferWriteU32(Packet, TickOffset, TickMilliseconds)

    WriteClampedI16(Packet, RootPositionOffset, RootPosition.X * PositionScale)
    WriteClampedI16(Packet, RootPositionOffset + 2, RootPosition.Y * PositionScale)
    WriteClampedI16(Packet, RootPositionOffset + 4, RootPosition.Z * PositionScale)

    WriteClampedI16(Packet, RootVelocityOffset, RootVelocity.X * VelocityScale)
    WriteClampedI16(Packet, RootVelocityOffset + 2, RootVelocity.Y * VelocityScale)
    WriteClampedI16(Packet, RootVelocityOffset + 4, RootVelocity.Z * VelocityScale)

    BufferWriteU8(Packet, JointCountOffset, JointCount)

    for Joint = 1, JointCount do
        local SourceOffset = (Joint - 1) * 12
        local DestOffset = JointDataOffset + (Joint - 1) * BytesPerJoint
        WriteClampedI16(Packet, DestOffset, BufferReadF32(PoseBuffer, SourceOffset) * AngleQuantization)
        WriteClampedI16(Packet, DestOffset + 2, BufferReadF32(PoseBuffer, SourceOffset + 4) * AngleQuantization)
        WriteClampedI16(Packet, DestOffset + 4, BufferReadF32(PoseBuffer, SourceOffset + 8) * AngleQuantization)
    end

    PoseRemote:FireServer(Packet)
end

function Network.SendEvent(EventId: number, Value: number): ()
    if not EventRemote then
        return
    end
    EventRemote:FireServer(EventId, Value)
end

--=========================================================
-- [7] SERVER RELAY + VALIDATION
--=========================================================

-- Server rate limiting: one token bucket per sender, derived from Config.SendRate (no new
-- config keys). Pose packets burst up to SendRate and refill at SendRate/second; the event
-- channel bursts the same and refills at half that (events are supposed to be rare). Idle
-- buckets never accumulate beyond the burst. Deterministic under the harness virtual clock.
local RatePoseBurst, RatePoseRefill = Config.SendRate, Config.SendRate
local RateEventBurst, RateEventRefill = Config.SendRate, Config.SendRate / 2

local function TakeToken(Bucket: any, Burst: number, Refill: number, Now: number): boolean
    local Elapsed = Now - Bucket.LastRefill
    if Elapsed > 0 then
        local Refilled = Bucket.Tokens + Elapsed * Refill
        Bucket.Tokens = Refilled > Burst and Burst or Refilled
        Bucket.LastRefill = Now
    end
    if Bucket.Tokens < 1 then
        return false
    end
    Bucket.Tokens -= 1
    return true
end

local function RegisterPlayerInternal(Player: any): ()
    if ServerPlayerStates[Player] then
        return
    end
    ServerPlayerStates[Player] = {
        LastSequence = -1,
        HasSequence = false,
        Warned = false,
        Received = 0,
        Dropped = 0,
        PoseRate = { Tokens = RatePoseBurst, LastRefill = Clock() },
        EventRate = { Tokens = RateEventBurst, LastRefill = Clock() },
    }
    ServerPlayerCount += 1
    ServerPlayerList[ServerPlayerCount] = Player
end

function Network.RegisterPlayer(Player: any): ()
    if not IsServer then
        return
    end
    RegisterPlayerInternal(Player)
end

function Network.UnregisterPlayer(Player: any): ()
    if not IsServer then
        return
    end
    if not ServerPlayerStates[Player] then
        return
    end
    ServerPlayerStates[Player] = nil
    for Index = 1, ServerPlayerCount do
        if ServerPlayerList[Index] == Player then
            ServerPlayerList[Index] = ServerPlayerList[ServerPlayerCount]
            ServerPlayerList[ServerPlayerCount] = nil
            ServerPlayerCount -= 1
            break
        end
    end
end

local function ValidateAngles(Packet: buffer, JointCount: number): boolean
    for Joint = 1, JointCount do
        local Offset = JointDataOffset + (Joint - 1) * BytesPerJoint
        local X = BufferReadI16(Packet, Offset) * AngleDequantization
        local Y = BufferReadI16(Packet, Offset + 2) * AngleDequantization
        local Z = BufferReadI16(Packet, Offset + 4) * AngleDequantization
        if X ~= X or Y ~= Y or Z ~= Z then
            return false
        end
        if Abs(X) > MaxAngleRadians or Abs(Y) > MaxAngleRadians or Abs(Z) > MaxAngleRadians then
            return false
        end
    end
    return true
end

local function RelayPose(SourcePlayer: any, Packet: buffer): ()
    for Index = 1, ServerPlayerCount do
        local Other = ServerPlayerList[Index]
        if Other ~= SourcePlayer then
            PoseRemote:FireClient(Other, SourcePlayer, Packet)
        end
    end
end

local function OnServerPose(Player: any, Packet: any): ()
    if TypeOf(Packet) ~= "buffer" then
        return
    end
    if BufferLen(Packet) < JointDataOffset then
        return
    end
    if BufferReadU8(Packet, HeaderOffset) ~= PacketPose then
        return
    end

    local State = ServerPlayerStates[Player]
    if not State then
        return
    end

    -- Rate limit before any decode work; floods cost the server almost nothing.
    if not TakeToken(State.PoseRate, RatePoseBurst, RatePoseRefill, Clock()) then
        State.Dropped += 1
        return
    end

    local Sequence = BufferReadU16(Packet, SequenceOffset)
    if State.HasSequence then
        local Delta = (Sequence - State.LastSequence) % SequenceModulus
        if Delta == 0 or Delta > 32768 then
            -- Stale or out-of-order packet: drop it silently.
            State.Dropped += 1
            return
        end
    end

    local JointCount = BufferReadU8(Packet, JointCountOffset)
    if JointCount == 0 or JointCount > MaxJoints then
        return
    end

    -- Bound the declared joint count by the bytes actually received. A client can send a
    -- header with a large JointCount and a short payload; without this the relay would
    -- read past the buffer end in ValidateAngles and in every downstream reader.
    if BufferLen(Packet) < JointDataOffset + JointCount * BytesPerJoint then
        State.Dropped += 1
        return
    end

    if not ValidateAngles(Packet, JointCount) then
        State.Dropped += 1
        return
    end

    local RootX = ReadClampedI16(Packet, RootPositionOffset, PositionInverse)
    local RootY = ReadClampedI16(Packet, RootPositionOffset + 2, PositionInverse)
    local RootZ = ReadClampedI16(Packet, RootPositionOffset + 4, PositionInverse)

    -- Sanity threshold on the client root position: never relay a teleport.
    local Character = Player.Character
    if Character then
        local RootPart = Character:FindFirstChild("HumanoidRootPart")
        if RootPart then
            local ServerPosition = RootPart.Position
            local OffsetX = ServerPosition.X - RootX
            local OffsetY = ServerPosition.Y - RootY
            local OffsetZ = ServerPosition.Z - RootZ
            local Distance = Sqrt(OffsetX * OffsetX + OffsetY * OffsetY + OffsetZ * OffsetZ)
            if Distance > Config.SanityRootThreshold then
                if not State.Warned then
                    State.Warned = true
                    Changelog.Log("Root position rejected for " .. Player.Name)
                end
                State.Dropped += 1
                return
            end
        end
    end

    State.LastSequence = Sequence
    State.HasSequence = true
    State.Received += 1

    RelayPose(Player, Packet)
end

local function OnServerEvent(Player: any, EventId: any, Value: any): ()
    if TypeOf(EventId) ~= "number" then
        return
    end
    if EventId < 1 or EventId > Config.MaxEventId then
        return
    end
    if TypeOf(Value) ~= "number" then
        Value = 0
    end
    -- Match the pose path: unregistered senders are ignored; spam is throttled to half rate.
    local State = ServerPlayerStates[Player]
    if not State then
        return
    end
    if not TakeToken(State.EventRate, RateEventBurst, RateEventRefill, Clock()) then
        State.Dropped += 1
        return
    end
    for Index = 1, ServerPlayerCount do
        local Other = ServerPlayerList[Index]
        if Other ~= Player then
            EventRemote:FireClient(Other, Player, EventId, Value)
        end
    end
end

--=========================================================
-- [9] INIT
--=========================================================

local function ConnectServer(): ()
    PoseRemote = EnsureRemote("UnreliableRemoteEvent", "PoseRemote")
    EventRemote = EnsureRemote("RemoteEvent", "EventRemote")
    BusEvent = EnsureRemote("BindableEvent", "AnimationBus")

    Connections.Add(ConnectionTracker, PoseRemote.OnServerEvent:Connect(OnServerPose))
    Connections.Add(ConnectionTracker, EventRemote.OnServerEvent:Connect(OnServerEvent))

    local CurrentPlayers = PlayersGetPlayers(Players)
    for Index = 1, #CurrentPlayers do
        RegisterPlayerInternal(CurrentPlayers[Index])
    end
end

local function ConnectClient(): boolean
    PoseRemote = RemotesFolder:WaitForChild("PoseRemote", 15)
    EventRemote = RemotesFolder:WaitForChild("EventRemote", 15)
    if not PoseRemote or not EventRemote then
        Changelog.Log("AnimationNetwork: remotes were not replicated to the client")
        return false
    end

    -- Local bus instance: bindable connections are per-side and never replicate.
    local LocalBus = InstanceNew("BindableEvent")
    LocalBus.Name = "AnimationBusLocal"
    BusEvent = LocalBus

    Connections.Add(ConnectionTracker, PoseRemote.OnClientEvent:Connect(OnClientPose))
    Connections.Add(ConnectionTracker, EventRemote.OnClientEvent:Connect(function(SourcePlayer, EventId, Value)
        if TypeOf(EventId) ~= "number" then
            return
        end
        if TypeOf(SourcePlayer) == "Instance" then
            FireBus(EventId, Value)
        end
    end))

    return true
end

function Network.Init(): ()
    if Initialized then
        return
    end
    if Shutdown then
        -- Init is one-shot per module load. A shutdown device cannot be revived because the
        -- jitter-buffer state it depended on has been released; the caller must reload the module.
        Changelog.Log("AnimationNetwork: Init ignored, module was shut down")
        return
    end

    if not ResolveRemotes() then
        Changelog.Log("AnimationNetwork: ReplicatedStorage.ProceduralAnimation is missing")
        return
    end

    local Ok = true
    if IsServer then
        ConnectServer()
    elseif IsClient then
        Ok = ConnectClient()
    end

    if not Ok then
        return
    end

    Initialized = true
end

function Network.IsReady(): boolean
    return Initialized and not Shutdown
end

-- Releases every engine connection and returns the module to an inert state. Safe to call twice.
-- Deliberately does not destroy the remotes: they are created once and shared, and destroying
-- them would break a subsequent re-Init on the other side of the session.
function Network.Shutdown(): ()
    if Shutdown then
        return
    end
    Shutdown = true
    Initialized = false

    Connections.DisconnectAll(ConnectionTracker)

    for Index = ServerPlayerCount, 1, -1 do
        local Player = ServerPlayerList[Index]
        if Player then
            Network.ReleaseRemotePose(Player)
        end
        ServerPlayerList[Index] = nil
    end
    ServerPlayerCount = 0

    Changelog.Log("AnimationNetwork shut down")
end

return Network
