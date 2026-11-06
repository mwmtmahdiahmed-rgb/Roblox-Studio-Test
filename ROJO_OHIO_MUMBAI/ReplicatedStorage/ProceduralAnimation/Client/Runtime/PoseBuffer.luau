-- ProceduralAnimation/Client/PoseBuffer
-- The per-joint pose buffer: a packed array of three f32s (X, Y, Z euler offsets in radians)
-- per joint, allocated once per character and rewritten every frame.
--
-- This is a leaf module. It depends on nothing but AnimationConfig, which means both
-- ClientPosePipeline (clip sampling, overlay blending) and ClientRigKinematics (FABRIK, waves, IK)
-- can require it directly without either one requiring the other.

local Config = require(script.Parent.Parent.Parent.Shared.AnimationConfig)

local MaxJoints = Config.MaxJoints

local PoseBytesPerJoint = 12
local PoseBufferLength = MaxJoints * PoseBytesPerJoint

local BufferReadF32 = buffer.readf32
local BufferWriteF32 = buffer.writef32

-- Adds an offset to one joint's entry. Used for additive layers that do not need to know what
-- the base pose already wrote.
local function WritePoseAdd(PoseBuffer, Joint, X, Y, Z)
    local Offset = (Joint - 1) * PoseBytesPerJoint
    BufferWriteF32(PoseBuffer, Offset, BufferReadF32(PoseBuffer, Offset) + X)
    BufferWriteF32(PoseBuffer, Offset + 4, BufferReadF32(PoseBuffer, Offset + 4) + Y)
    BufferWriteF32(PoseBuffer, Offset + 8, BufferReadF32(PoseBuffer, Offset + 8) + Z)
end

-- Blends a value into one joint's entry. Used where a layer has a weight and should replace
-- rather than accumulate (IK, gesture overrides).
local function WritePoseBlend(PoseBuffer, Joint, X, Y, Z, Weight)
    local Offset = (Joint - 1) * PoseBytesPerJoint
    local Inverse = 1.0 - Weight
    BufferWriteF32(PoseBuffer, Offset, BufferReadF32(PoseBuffer, Offset) * Inverse + X * Weight)
    BufferWriteF32(PoseBuffer, Offset + 4, BufferReadF32(PoseBuffer, Offset + 4) * Inverse + Y * Weight)
    BufferWriteF32(PoseBuffer, Offset + 8, BufferReadF32(PoseBuffer, Offset + 8) * Inverse + Z * Weight)
end

return {
    PoseBytesPerJoint = PoseBytesPerJoint,
    PoseBufferLength = PoseBufferLength,
    WritePoseAdd = WritePoseAdd,
    WritePoseBlend = WritePoseBlend,
}
