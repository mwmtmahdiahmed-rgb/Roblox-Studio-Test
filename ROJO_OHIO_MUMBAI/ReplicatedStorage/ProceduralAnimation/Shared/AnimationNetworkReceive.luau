-- ProceduralAnimation/Shared/AnimationNetworkReceive
-- Client receive path: per-player jitter buffer states, the pose decoder and the
-- render-time interpolation sampler. Split out of AnimationNetwork to stay under the
-- line cap. The factory takes the aggregator table as a parameter, so HasRemotePose,
-- SampleRemotePose and ReleaseRemotePose land on the public surface unchanged, and it
-- hands OnClientPose back through Private so ConnectClient can subscribe to it.

local Config = require(script.Parent.AnimationConfig)
local MathLib = require(script.Parent.AnimationMath)
local Constants = require(script.Parent.AnimationNetworkConstants)

local BufferCreate = Constants.BufferCreate
local BufferLen = Constants.BufferLen
local BufferCopy = Constants.BufferCopy
local BufferReadU8 = Constants.BufferReadU8
local BufferReadU16 = Constants.BufferReadU16
local BufferReadI16 = Constants.BufferReadI16
local BufferReadF32 = Constants.BufferReadF32
local BufferWriteF32 = Constants.BufferWriteF32
local Clock = Constants.Clock
local TypeOf = Constants.TypeOf
local PacketPose = Constants.PacketPose
local SequenceModulus = Constants.SequenceModulus
local HeaderOffset = Constants.HeaderOffset
local SequenceOffset = Constants.SequenceOffset
local JointCountOffset = Constants.JointCountOffset
local JointDataOffset = Constants.JointDataOffset
local BytesPerJoint = Constants.BytesPerJoint
local MaxJoints = Constants.MaxJoints
local AngleDequantization = Constants.AngleDequantization
local PoseFloatLength = Constants.PoseFloatLength

-- Per-player jitter buffer states, keyed by the source player.
local ReceiveStates = {}

return function(Network, Private)
--=========================================================
-- [8] RECEIVE PATH (client)
--=========================================================

local function CreateReceiveState()
    return {
        Previous = BufferCreate(PoseFloatLength),
        Current = BufferCreate(PoseFloatLength),
        PreviousTime = 0.0,
        CurrentTime = 0.0,
        LastSequence = -1,
        HasSequence = false,
        Valid = false,
    }
end

local function OnClientPose(SourcePlayer, Packet)
    if TypeOf(Packet) ~= "buffer" then
        return
    end
    if BufferLen(Packet) < JointDataOffset then
        return
    end
    if BufferReadU8(Packet, HeaderOffset) ~= PacketPose then
        return
    end

    local JointCount = BufferReadU8(Packet, JointCountOffset)
    if JointCount == 0 or JointCount > MaxJoints then
        return
    end

    -- The header checks above only guarantee the fixed prefix. A truncated packet still
    -- carries a plausible JointCount, so verify the payload length before any joint byte
    -- is read; otherwise the decode loop reads past the end of the buffer.
    if BufferLen(Packet) < JointDataOffset + JointCount * BytesPerJoint then
        return
    end

    local State = ReceiveStates[SourcePlayer]
    if not State then
        State = CreateReceiveState()
        ReceiveStates[SourcePlayer] = State
    end

    local Sequence = BufferReadU16(Packet, SequenceOffset)
    if State.HasSequence then
        local Delta = (Sequence - State.LastSequence) % SequenceModulus
        if Delta == 0 or Delta > 32768 then
            return
        end
    end
    State.LastSequence = Sequence
    State.HasSequence = true

    -- Shift current into previous, then decode the new packet into current.
    BufferCopy(State.Previous, 0, State.Current, 0, PoseFloatLength)
    State.PreviousTime = State.CurrentTime

    for Joint = 1, JointCount do
        local SourceOffset = JointDataOffset + (Joint - 1) * BytesPerJoint
        local DestOffset = (Joint - 1) * 12
        BufferWriteF32(State.Current, DestOffset, BufferReadI16(Packet, SourceOffset) * AngleDequantization)
        BufferWriteF32(State.Current, DestOffset + 4, BufferReadI16(Packet, SourceOffset + 2) * AngleDequantization)
        BufferWriteF32(State.Current, DestOffset + 8, BufferReadI16(Packet, SourceOffset + 4) * AngleDequantization)
    end

    State.CurrentTime = Clock()
    if not State.Valid then
        State.Valid = true
        State.PreviousTime = State.CurrentTime
    end
end

function Network.HasRemotePose(SourcePlayer)
    local State = ReceiveStates[SourcePlayer]
    return State ~= nil and State.Valid
end

function Network.SampleRemotePose(SourcePlayer, OutPoseBuffer)
    local State = ReceiveStates[SourcePlayer]
    if not State or not State.Valid then
        return false
    end

    local Now = Clock()
    local Span = State.CurrentTime - State.PreviousTime
    local RenderTime = Now - Config.JitterBufferDepth
    local Alpha = 0.0
    if Span > 0.0001 then
        Alpha = (RenderTime - State.PreviousTime) / Span
    end
    Alpha = MathLib.Clamp01(Alpha)

    local Offset = 0
    while Offset < PoseFloatLength do
        local From = BufferReadF32(State.Previous, Offset)
        local To = BufferReadF32(State.Current, Offset)
        BufferWriteF32(OutPoseBuffer, Offset, From + (To - From) * Alpha)
        Offset += 4
    end

    return true
end

function Network.ReleaseRemotePose(SourcePlayer)
    ReceiveStates[SourcePlayer] = nil
end

Private.OnClientPose = OnClientPose
Private.ReceiveStates = ReceiveStates
end
