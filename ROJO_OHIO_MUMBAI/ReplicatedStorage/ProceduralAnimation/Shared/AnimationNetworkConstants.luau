-- ProceduralAnimation/Shared/AnimationNetworkConstants
-- Packet layout, buffer and math aliases, and quantization constants shared by
-- AnimationNetwork (send path + server relay) and AnimationNetworkReceive
-- (client jitter buffers). Pure data plus the two i16 packet helpers: no
-- remotes, no connections, no runtime state.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(script.Parent.AnimationConfig)

local Constants = {}

-- [1] CONSTANTS
local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

local BufferCreate = buffer.create
local BufferLen = buffer.len
local BufferCopy = buffer.copy
local BufferReadU8 = buffer.readu8
local BufferWriteU8 = buffer.writeu8
local BufferReadU16 = buffer.readu16
local BufferWriteU16 = buffer.writeu16
local BufferReadU32 = buffer.readu32
local BufferWriteU32 = buffer.writeu32
local BufferReadI16 = buffer.readi16
local BufferWriteI16 = buffer.writei16
local BufferReadF32 = buffer.readf32
local BufferWriteF32 = buffer.writef32

local Floor = math.floor
local Abs = math.abs
local Clamp = math.clamp
local Sqrt = math.sqrt
local Clock = os.clock
local TypeOf = typeof
local InstanceNew = Instance.new
local Vector3New = Vector3.new
local PlayersGetPlayers = Players.GetPlayers

local PacketPose = Config.Packet.Header
local PacketEvent = Config.Packet.Event
local SequenceModulus = Config.Packet.SequenceModulus

local HeaderOffset = 0
local SequenceOffset = 1
local TickOffset = 3
local RootPositionOffset = 7
local RootVelocityOffset = 13
local JointCountOffset = 19
local JointDataOffset = 20
local BytesPerJoint = 6
local MaxJoints = Config.MaxJoints
local SendBufferSize = JointDataOffset + MaxJoints * BytesPerJoint

local AngleQuantization = Config.Packet.AngleQuantization
local AngleDequantization = 1.0 / Config.Packet.AngleQuantization
local PositionScale = Config.Packet.PositionScale
local PositionInverse = 1.0 / Config.Packet.PositionScale
local VelocityScale = Config.Packet.VelocityScale

local PoseFloatLength = MaxJoints * 3 * 4
local MaxAngleRadians = math.pi * 1.05

-- [2] PACKET ENCODING
local function WriteClampedI16(PacketBuffer, Offset, Value)
    if Value ~= Value then
        Value = 0.0
    end
    if Value < -32767.0 then
        Value = -32767.0
    elseif Value > 32767.0 then
        Value = 32767.0
    end
    BufferWriteI16(PacketBuffer, Offset, Floor(Value + 0.5))
end

local function ReadClampedI16(PacketBuffer, Offset, Inverse)
    return BufferReadI16(PacketBuffer, Offset) * Inverse
end

Constants.IsServer = IsServer
Constants.IsClient = IsClient
Constants.BufferCreate = BufferCreate
Constants.BufferLen = BufferLen
Constants.BufferCopy = BufferCopy
Constants.BufferReadU8 = BufferReadU8
Constants.BufferWriteU8 = BufferWriteU8
Constants.BufferReadU16 = BufferReadU16
Constants.BufferWriteU16 = BufferWriteU16
Constants.BufferReadU32 = BufferReadU32
Constants.BufferWriteU32 = BufferWriteU32
Constants.BufferReadI16 = BufferReadI16
Constants.BufferWriteI16 = BufferWriteI16
Constants.BufferReadF32 = BufferReadF32
Constants.BufferWriteF32 = BufferWriteF32
Constants.Floor = Floor
Constants.Abs = Abs
Constants.Clamp = Clamp
Constants.Sqrt = Sqrt
Constants.Clock = Clock
Constants.TypeOf = TypeOf
Constants.InstanceNew = InstanceNew
Constants.Vector3New = Vector3New
Constants.PlayersGetPlayers = PlayersGetPlayers
Constants.PacketPose = PacketPose
Constants.PacketEvent = PacketEvent
Constants.SequenceModulus = SequenceModulus
Constants.HeaderOffset = HeaderOffset
Constants.SequenceOffset = SequenceOffset
Constants.TickOffset = TickOffset
Constants.RootPositionOffset = RootPositionOffset
Constants.RootVelocityOffset = RootVelocityOffset
Constants.JointCountOffset = JointCountOffset
Constants.JointDataOffset = JointDataOffset
Constants.BytesPerJoint = BytesPerJoint
Constants.MaxJoints = MaxJoints
Constants.SendBufferSize = SendBufferSize
Constants.AngleQuantization = AngleQuantization
Constants.AngleDequantization = AngleDequantization
Constants.PositionScale = PositionScale
Constants.PositionInverse = PositionInverse
Constants.VelocityScale = VelocityScale
Constants.PoseFloatLength = PoseFloatLength
Constants.MaxAngleRadians = MaxAngleRadians
Constants.WriteClampedI16 = WriteClampedI16
Constants.ReadClampedI16 = ReadClampedI16

return Constants
