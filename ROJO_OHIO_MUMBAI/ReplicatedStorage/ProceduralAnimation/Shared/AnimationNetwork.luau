-- ProceduralAnimation/Shared/AnimationNetwork
-- Owns every remote, the bindable event bus and the server relay for pose packets.
-- UnreliableRemoteEvent: per-frame pose packets.
-- RemoteEvent: one-shot events (setup, clip start, clip stop, landing, gesture start).
-- BindableEvent: same-side communication between the animator and this module.
--
-- Note on the bindable bus: BindableEvents do NOT replicate their connections, so each side
-- creates its own local bus instance. The server also parents a bus under Remotes for
-- discoverability; the client intentionally ignores that replicated copy and uses a local one.
--
-- Split for the line cap: the packet layout, the buffer and math aliases and the
-- quantization constants live in AnimationNetworkConstants, and the client jitter
-- buffers in AnimationNetworkReceive. Both are required below, so the public surface
-- and the packet layout are exactly what they were.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
-- Required by ConnectServer: Constants caches the unbound GetPlayers method, so the
-- service instance has to be passed as its first argument (PlayersGetPlayers(Players)).
local Players = game:GetService("Players")

local Config = require(script.Parent.AnimationConfig)
local Changelog = require(script.Parent.Changelog)
local Constants = require(script.Parent.Networking.Constants.NetworkConstants)

local Network = {}
local Private = {}

-- The receive module writes HasRemotePose, SampleRemotePose and ReleaseRemotePose
-- straight onto Network and returns OnClientPose through Private.
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

-- Enough for one decoded pose pair per player plus animation state.
local ReceiveStatePool = {}
local ReceiveStatePoolCount = 0

--=========================================================
-- [2] BUFFERS
--=========================================================

-- One send buffer, created once. Never re-created per frame.
local SendBuffer = BufferCreate(SendBufferSize)

-- Server relay bookkeeping. Array-indexed player list, swap-removed on leave.
local ServerPlayerStates = {}
local ServerPlayerCount = 0
local ServerPlayerList = {}

local Initialized = false
local PoseRemote = nil
local EventRemote = nil
local BusEvent = nil
local RemotesFolder = nil

--=========================================================
-- [3] EVENT BUS (local, same side)
--=========================================================

local BusListeners = {}
for EventId = 1, Config.MaxEventId do
    BusListeners[EventId] = {}
end

local function FireBus(EventId, Value)
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

function Network.BindLocal(EventId, Callback)
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

local function ResolveRemotes()
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

local function EnsureRemote(ClassName, Name)
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

function Network.SendPose(Sequence, TickMilliseconds, RootPosition, RootVelocity, PoseBuffer, JointCount)
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

function Network.SendEvent(EventId, Value)
    if not EventRemote then
        return
    end
    EventRemote:FireServer(EventId, Value)
end

--=========================================================
-- [7] SERVER RELAY + VALIDATION
--=========================================================

local function RegisterPlayerInternal(Player)
    if ServerPlayerStates[Player] then
        return
    end
    ServerPlayerStates[Player] = {
        LastSequence = -1,
        HasSequence = false,
        Warned = false,
        Received = 0,
        Dropped = 0,
    }
    ServerPlayerCount += 1
    ServerPlayerList[ServerPlayerCount] = Player
end

function Network.RegisterPlayer(Player)
    if not IsServer then
        return
    end
    RegisterPlayerInternal(Player)
end

function Network.UnregisterPlayer(Player)
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

local function ValidateAngles(Packet, JointCount)
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

local function RelayPose(SourcePlayer, Packet)
    for Index = 1, ServerPlayerCount do
        local Other = ServerPlayerList[Index]
        if Other ~= SourcePlayer then
            PoseRemote:FireClient(Other, SourcePlayer, Packet)
        end
    end
end

local function OnServerPose(Player, Packet)
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

local function OnServerEvent(Player, EventId, Value)
    if TypeOf(EventId) ~= "number" then
        return
    end
    if EventId < 1 or EventId > Config.MaxEventId then
        return
    end
    if TypeOf(Value) ~= "number" then
        Value = 0
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

local function ConnectServer()
    PoseRemote = EnsureRemote("UnreliableRemoteEvent", "PoseRemote")
    EventRemote = EnsureRemote("RemoteEvent", "EventRemote")
    BusEvent = EnsureRemote("BindableEvent", "AnimationBus")

    PoseRemote.OnServerEvent:Connect(OnServerPose)
    EventRemote.OnServerEvent:Connect(OnServerEvent)

    local CurrentPlayers = PlayersGetPlayers(Players)
    for Index = 1, #CurrentPlayers do
        RegisterPlayerInternal(CurrentPlayers[Index])
    end
end

local function ConnectClient()
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

    PoseRemote.OnClientEvent:Connect(OnClientPose)
    EventRemote.OnClientEvent:Connect(function(SourcePlayer, EventId, Value)
        if TypeOf(EventId) ~= "number" then
            return
        end
        if TypeOf(SourcePlayer) == "Instance" then
            FireBus(EventId, Value)
        end
    end)

    return true
end

function Network.Init()
    if Initialized then
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

function Network.IsReady()
    return Initialized
end

return Network
