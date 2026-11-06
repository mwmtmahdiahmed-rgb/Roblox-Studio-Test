-- ProceduralAnimation/Shared/AnimationConfigCompile

return function(Config, Private)
local Clips = Private.Clips
local JointIndex = Config.JointIndex

--=========================================================
-- [3] COMPILE PASS
--=========================================================
-- Authoring tables are readable but use string field names. This pass flattens every clip into
-- parallel integer-indexed arrays once, so the render loop reads only numeric keys.

local function CompileClip(Source)
    local Compiled = {
        TrackCount = 0,
        TrackJoint = {},
        TrackKeyCount = {},
        TrackPhase = {},
        TrackX = {},
        TrackY = {},
        TrackZ = {},
        EasingId = Source.EasingId or Config.EasingId.Linear,
        Stride = Source.Stride or 6.0,
        Period = Source.Period or 1.0,
        Duration = Source.Duration or 0.0,
        VerticalPhases = Source.VerticalPhases,
        VerticalValues = Source.VerticalValues,
        VerticalKeyCount = 0,
    }

    local Tracks = Source.Tracks
    local TrackCount = 0
    for Joint = 1, Config.MaxJoints do
        local Track = Tracks[Joint]
        if Track then
            TrackCount += 1
            Compiled.TrackJoint[TrackCount] = Joint
            Compiled.TrackPhase[TrackCount] = Track.Phases
            Compiled.TrackX[TrackCount] = Track.X
            Compiled.TrackY[TrackCount] = Track.Y
            Compiled.TrackZ[TrackCount] = Track.Z
            Compiled.TrackKeyCount[TrackCount] = #Track.Phases
        end
    end
    Compiled.TrackCount = TrackCount

    if Source.VerticalPhases then
        Compiled.VerticalKeyCount = #Source.VerticalPhases
    end

    return Compiled
end

local CompiledJump = {}
CompiledJump[1] = CompileClip(Config.Jump.Anticipation)
CompiledJump[2] = CompileClip(Config.Jump.Launch)
CompiledJump[3] = CompileClip(Config.Jump.Airborne)
CompiledJump[4] = CompileClip(Config.Jump.Landing)
CompiledJump[5] = CompileClip(Config.Jump.Recovery)

local CompiledGestures = {
    Wave = CompileClip(Config.Gestures.Wave),
    Point = CompileClip(Config.Gestures.Point),
    Nod = CompileClip(Config.Gestures.Nod),
}

-- Compile wave presets for fast sampling.
local MathLib = require(script.Parent.AnimationMath)
local CompiledWaves = {}
-- Sorted names so the compiled table has a fixed, reproducible ordering independent of how
-- the authoring table happens to hash. Consumers iterate WaveOrder instead of pairs(), which
-- makes wave application order deterministic across client and server.
local WaveOrder = {}
for WaveName in pairs(Config.Waves) do
    WaveOrder[#WaveOrder + 1] = WaveName
end
table.sort(WaveOrder)
for Index = 1, #WaveOrder do
    local WaveName = WaveOrder[Index]
    CompiledWaves[WaveName] = MathLib.CompileWave(Config.Waves[WaveName])
end

Config.Compiled = {
    Idle = CompileClip(Clips.Idle),
    Walk = CompileClip(Clips.Walk),
    Run = CompileClip(Clips.Run),
    Jump = CompiledJump,
    Gestures = CompiledGestures,
    Waves = CompiledWaves,
    WaveOrder = WaveOrder,
}

-- Joint index helpers used by the animator without any string lookups.
Config.LegJointIndex = {
    Hip = { JointIndex.LeftHip, JointIndex.RightHip },
    Knee = { JointIndex.LeftKnee, JointIndex.RightKnee },
    Ankle = { JointIndex.LeftAnkle, JointIndex.RightAnkle },
}

Config.ArmJointIndex = {
    Shoulder = { JointIndex.LeftShoulder, JointIndex.RightShoulder },
    Elbow = { JointIndex.LeftElbow, JointIndex.RightElbow },
    Wrist = { JointIndex.LeftWrist, JointIndex.RightWrist },
}
end
