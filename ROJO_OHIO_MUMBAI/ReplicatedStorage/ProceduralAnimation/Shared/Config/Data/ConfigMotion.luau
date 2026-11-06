-- ProceduralAnimation/Shared/AnimationConfigMotion

return function(Config, Private)
local JointIndex = Config.JointIndex
local MakeTrack = Private.MakeTrack

--=========================================================
-- [2.5] WAVE PRESETS (layered harmonics for idle animation)
--=========================================================

Config.Waves = {
    Breathing = {
        Harmonics = {
            { Amplitude = 0.015, Frequency = 0.4, Phase = 0.0 },
            { Amplitude = 0.008, Frequency = 0.8, Phase = 1.2 },
        },
        NoiseAmplitude = 0.003,
        NoiseFrequency = 0.6,
    },
    HeadSway = {
        Harmonics = {
            { Amplitude = 0.025, Frequency = 0.3, Phase = 0.0 },
            { Amplitude = 0.012, Frequency = 0.6, Phase = 0.8 },
        },
        NoiseAmplitude = 0.005,
        NoiseFrequency = 0.4,
    },
    BodyBob = {
        Harmonics = {
            { Amplitude = 0.010, Frequency = 0.5, Phase = 0.0 },
            { Amplitude = 0.005, Frequency = 1.0, Phase = 1.5 },
        },
        NoiseAmplitude = 0.002,
        NoiseFrequency = 0.5,
    },
}

--=========================================================
-- [2.6] FABRIK CHAINS (for spine and other multi-bone chains)
--=========================================================

Config.FabrikChains = {
    Spine = {
        Joints = { JointIndex.Waist, JointIndex.Chest, JointIndex.Neck },
        Tolerance = 0.01,
        MaxIterations = 10,
        Weight = 0.6,
    },
}

Config.Gestures = {
    Wave = {
        Duration = 1.0,
        EasingId = Config.EasingId.SineInOut,
        Tracks = {
            [JointIndex.RightShoulder] = MakeTrack(
                { 0.0, 0.25, 0.5, 0.75, 1.0 },
                { 0.0, -2.30, -2.30, -2.30, 0.0 },
                { 0.0, 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.30, 0.30, 0.30, 0.0 }
            ),
            [JointIndex.RightElbow] = MakeTrack(
                { 0.0, 0.25, 0.5, 0.75, 1.0 },
                { 0.0, -0.55, -0.95, -0.55, 0.0 },
                { 0.0, 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.35, -0.35, 0.35, 0.0 }
            ),
            [JointIndex.RightWrist] = MakeTrack(
                { 0.0, 0.25, 0.5, 0.75, 1.0 },
                { 0.0, 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.35, -0.35, 0.35, 0.0 },
                { 0.0, 0.0, 0.0, 0.0, 0.0 }
            ),
        },
    },
    Point = {
        Duration = 1.2,
        EasingId = Config.EasingId.QuadOut,
        Tracks = {
            [JointIndex.RightShoulder] = MakeTrack(
                { 0.0, 0.2, 0.8, 1.0 },
                { 0.0, -1.45, -1.45, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.25, 0.25, 0.0 }
            ),
            [JointIndex.RightElbow] = MakeTrack(
                { 0.0, 0.2, 0.8, 1.0 },
                { 0.0, -0.10, -0.10, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 }
            ),
            [JointIndex.Chest] = MakeTrack(
                { 0.0, 0.2, 0.8, 1.0 },
                { 0.0, 0.0, 0.0, 0.0 },
                { -0.22, -0.30, -0.30, -0.22 },
                { 0.0, 0.0, 0.0, 0.0 }
            ),
        },
    },
    Nod = {
        Duration = 0.9,
        EasingId = Config.EasingId.SineInOut,
        Tracks = {
            [JointIndex.Neck] = MakeTrack(
                { 0.0, 0.3, 0.6, 1.0 },
                { 0.0, 0.30, -0.10, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 }
            ),
            [JointIndex.Waist] = MakeTrack(
                { 0.0, 0.3, 0.6, 1.0 },
                { 0.0, 0.10, -0.04, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 },
                { 0.0, 0.0, 0.0, 0.0 }
            ),
        },
    },
}
end
