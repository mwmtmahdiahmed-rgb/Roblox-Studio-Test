--!strict
-- ProceduralAnimation/Shared/AnimationConfigData

return function(Config, Private)

--=========================================================
-- [1] CONSTANTS
--=========================================================

Config.Version = "1.1.0"

Config.MaxJoints = 16
Config.MaxGestures = 4

Config.SendRate = 30.0
Config.JitterBufferDepth = 0.06
Config.LocalSmoothRate = 16.0
Config.RemoteSmoothRate = 24.0

Config.LodDistance = 160.0
Config.LodIkDistance = 45.0

Config.SanityRootThreshold = 16.0

Config.IkBlendRate = 7.0
Config.IkReachClamp = 0.985
Config.IkAngleLimitMin = -2.6
Config.IkAngleLimitMax = 2.6
Config.FootRayHeight = 2.6
Config.FootRayLength = 5.2
Config.FootAlignWeight = 0.85

Config.PreviewAnchorRoot = false
Config.ProfilingEnabled = false
Config.RequireOptionalJoints = false

Config.Locomotion = {
    IdleMax = 1.0,
    WalkMax = 9.0,
    RunMax = 22.0,
    BlendRate = 9.0,
}

-- Exponential low-pass cutoff (per second) applied to AssemblyLinearVelocity horizontal speed
-- before it drives the idle/walk/run blend. 0 disables the filter (raw velocity, the original
-- behaviour). New top-level keys only: existing config sub-tables are untouched.
Config.VelocityFilterRate = 12.0

-- Squash and stretch: a landing impulse is fed into a damped spring on the root vertical
-- offset, so landings dip and rebound slightly. Set Enabled = false to opt out entirely.
Config.SquashStretch = {
    Enabled = true,
    Strength = 2.4,
    Stiffness = 170.0,
    Damping = 14.0,
}

-- Head look-at: Neck joint aims toward a target set via Animator.SetLookAtTarget.
-- Smoothing is the exponential rate at which the head weight approaches its target; angle
-- limits reuse Config.IkAngleLimitMin/Max. Absent a target, this costs one table read per frame.
Config.LookAt = {
    Smoothing = 8.0,
}

-- Joint index constants. Integer keys only, so every joint lookup in the hot loop is numeric.
local JointIndex = {
    Waist = 1,
    Chest = 2,
    Neck = 3,
    LeftShoulder = 4,
    RightShoulder = 5,
    LeftElbow = 6,
    RightElbow = 7,
    LeftWrist = 8,
    RightWrist = 9,
    LeftHip = 10,
    RightHip = 11,
    LeftKnee = 12,
    RightKnee = 13,
    LeftAnkle = 14,
    RightAnkle = 15,
    Root = 16,
}
Config.JointIndex = JointIndex

Config.JointNames = {
    [1] = "Waist",
    [2] = "Chest",
    [3] = "Neck",
    [4] = "LeftShoulder",
    [5] = "RightShoulder",
    [6] = "LeftElbow",
    [7] = "RightElbow",
    [8] = "LeftWrist",
    [9] = "RightWrist",
    [10] = "LeftHip",
    [11] = "RightHip",
    [12] = "LeftKnee",
    [13] = "RightKnee",
    [14] = "LeftAnkle",
    [15] = "RightAnkle",
    [16] = "RootJoint",
}

-- Alternate Motor6D names accepted for a joint index (R6/R15 naming drift).
Config.JointAliases = {
    [16] = { "RootJoint", "Root" },
}

-- Chest is not part of the standard R15 rig. It is cached when present and skipped when absent,
-- so the framework never aborts setup on a vanilla R15 avatar. See Changelog entry 2.
Config.OptionalJoints = {
    [2] = true,
}

-- Integer ids for the easing lookup table in AnimationMath.
Config.EasingId = {
    Linear = 1,
    SineIn = 2,
    SineOut = 3,
    SineInOut = 4,
    BackIn = 5,
    BackOut = 6,
    BackInOut = 7,
    QuadIn = 8,
    QuadOut = 9,
    QuadInOut = 10,
    QuartIn = 11,
    QuartOut = 12,
    QuartInOut = 13,
    QuintIn = 14,
    QuintOut = 15,
    QuintInOut = 16,
    BounceIn = 17,
    BounceOut = 18,
    BounceInOut = 19,
    ElasticIn = 20,
    ElasticOut = 21,
    ElasticInOut = 22,
    ExponentialIn = 23,
    ExponentialOut = 24,
    ExponentialInOut = 25,
    CircularIn = 26,
    CircularOut = 27,
    CircularInOut = 28,
    CubicIn = 29,
    CubicOut = 30,
    CubicInOut = 31,
    Spring = 32,
    ElasticCustom = 33,
    BounceCustom = 34,
    AnticipateOvershoot = 35,
}

-- Integer ids for the bindable event bus. No strings cross the bus.
Config.EventId = {
    Setup = 1,
    ClipStart = 2,
    ClipStop = 3,
    Landing = 4,
    GestureStart = 5,
}

Config.MaxEventId = 5

-- Packet layout constants mirrored by AnimationNetwork.
Config.Packet = {
    Header = 1,
    Event = 2,
    SequenceModulus = 65536,
    AngleQuantization = 32767 / math.pi,
    PositionScale = 64,
    VelocityScale = 64,
}

--=========================================================
-- [2] CLIP AUTHORING TABLES (data only)
--=========================================================

local function MakeTrack(Phases, XValues, YValues, ZValues)
    return {
        Phases = Phases,
        X = XValues,
        Y = YValues,
        Z = ZValues,
    }
end

local Clips = {}

Clips.Idle = {
    Period = 3.2,
    EasingId = Config.EasingId.SineInOut,
    Tracks = {
        [JointIndex.Waist] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { 0.0, 0.018, 0.0 },
            { 0.0, 0.012, 0.0 },
            { 0.0, -0.010, 0.0 }
        ),
        [JointIndex.Chest] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { 0.0, 0.034, 0.0 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0 }
        ),
        [JointIndex.Neck] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.0, 0.012, 0.0, -0.012, 0.0 },
            { 0.0, 0.045, 0.0, -0.045, 0.0 },
            { 0.0, -0.020, 0.0, 0.020, 0.0 }
        ),
        [JointIndex.LeftShoulder] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { 0.0, 0.020, 0.0 },
            { 0.0, 0.0, 0.0 },
            { 0.0, -0.030, 0.0 }
        ),
        [JointIndex.RightShoulder] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { 0.0, 0.020, 0.0 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.030, 0.0 }
        ),
    },
    VerticalPhases = { 0.0, 0.5, 1.0 },
    VerticalValues = { 0.0, -0.012, 0.0 },
}

Clips.Walk = {
    Stride = 6.4,
    Frequency = 1.0,
    EasingId = Config.EasingId.SineInOut,
    Tracks = {
        [JointIndex.Waist] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.05, 0.02, 0.05, 0.02, 0.05 },
            { 0.10, 0.0, -0.10, 0.0, 0.10 },
            { 0.0, 0.03, 0.0, -0.03, 0.0 }
        ),
        [JointIndex.Chest] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { 0.0, 0.025, 0.0 },
            { -0.09, 0.09, -0.09 },
            { 0.0, 0.0, 0.0 }
        ),
        [JointIndex.LeftHip] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { -0.42, -0.06, 0.42, 0.10, -0.42 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.02, 0.0, -0.02, 0.0, 0.02 }
        ),
        [JointIndex.RightHip] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.42, 0.10, -0.42, -0.06, 0.42 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { -0.02, 0.0, 0.02, 0.0, -0.02 }
        ),
        [JointIndex.LeftKnee] = MakeTrack(
            { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 },
            { 0.08, 0.30, 0.85, 0.40, 0.10, 0.08 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.RightKnee] = MakeTrack(
            { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 },
            { 0.40, 0.10, 0.08, 0.30, 0.85, 0.40 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.LeftAnkle] = MakeTrack(
            { 0.0, 0.35, 0.7, 1.0 },
            { 0.12, -0.10, 0.10, 0.12 },
            { 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.RightAnkle] = MakeTrack(
            { 0.0, 0.35, 0.7, 1.0 },
            { -0.10, 0.12, 0.12, -0.10 },
            { 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.LeftShoulder] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.32, 0.10, -0.32, -0.10, 0.32 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { -0.12, -0.12, -0.12, -0.12, -0.12 }
        ),
        [JointIndex.RightShoulder] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { -0.32, -0.10, 0.32, 0.10, -0.32 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.12, 0.12, 0.12, 0.12, 0.12 }
        ),
        [JointIndex.LeftElbow] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { -0.24, -0.42, -0.24 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0 }
        ),
        [JointIndex.RightElbow] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { -0.42, -0.24, -0.42 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0 }
        ),
    },
    VerticalPhases = { 0.0, 0.25, 0.5, 0.75, 1.0 },
    VerticalValues = { 0.03, -0.03, 0.03, -0.03, 0.03 },
}

Clips.Run = {
    Stride = 9.5,
    Frequency = 1.0,
    EasingId = Config.EasingId.SineInOut,
    Tracks = {
        [JointIndex.Waist] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.16, 0.12, 0.16, 0.12, 0.16 },
            { 0.16, 0.0, -0.16, 0.0, 0.16 },
            { 0.0, 0.05, 0.0, -0.05, 0.0 }
        ),
        [JointIndex.Chest] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { 0.03, 0.06, 0.03 },
            { -0.16, 0.16, -0.16 },
            { 0.0, 0.0, 0.0 }
        ),
        [JointIndex.Neck] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { -0.10, -0.06, -0.10 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0 }
        ),
        [JointIndex.LeftHip] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { -0.85, -0.10, 0.75, 0.20, -0.85 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.05, 0.0, -0.05, 0.0, 0.05 }
        ),
        [JointIndex.RightHip] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.75, 0.20, -0.85, -0.10, 0.75 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { -0.05, 0.0, 0.05, 0.0, -0.05 }
        ),
        [JointIndex.LeftKnee] = MakeTrack(
            { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 },
            { 0.20, 0.75, 1.65, 0.90, 0.25, 0.20 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.RightKnee] = MakeTrack(
            { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 },
            { 0.90, 0.25, 0.20, 0.75, 1.65, 0.90 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.LeftAnkle] = MakeTrack(
            { 0.0, 0.35, 0.7, 1.0 },
            { 0.25, -0.20, 0.20, 0.25 },
            { 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.RightAnkle] = MakeTrack(
            { 0.0, 0.35, 0.7, 1.0 },
            { -0.20, 0.25, 0.25, -0.20 },
            { 0.0, 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0, 0.0 }
        ),
        [JointIndex.LeftShoulder] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { 0.60, 0.20, -0.60, -0.20, 0.60 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { -0.20, -0.20, -0.20, -0.20, -0.20 }
        ),
        [JointIndex.RightShoulder] = MakeTrack(
            { 0.0, 0.25, 0.5, 0.75, 1.0 },
            { -0.60, -0.20, 0.60, 0.20, -0.60 },
            { 0.0, 0.0, 0.0, 0.0, 0.0 },
            { 0.20, 0.20, 0.20, 0.20, 0.20 }
        ),
        [JointIndex.LeftElbow] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { -0.75, -1.15, -0.75 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0 }
        ),
        [JointIndex.RightElbow] = MakeTrack(
            { 0.0, 0.5, 1.0 },
            { -1.15, -0.75, -1.15 },
            { 0.0, 0.0, 0.0 },
            { 0.0, 0.0, 0.0 }
        ),
    },
    VerticalPhases = { 0.0, 0.25, 0.5, 0.75, 1.0 },
    VerticalValues = { 0.06, -0.04, 0.06, -0.04, 0.06 },
}

-- Jump is a segmented clip. Each segment owns its duration, easing and tracks.
Config.Jump = {
    Anticipation = {
        Duration = 0.14,
        EasingId = Config.EasingId.QuadOut,
        Tracks = {
            [JointIndex.LeftHip] = MakeTrack({ 0.0, 1.0 }, { 0.0, 0.55 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightHip] = MakeTrack({ 0.0, 1.0 }, { 0.0, 0.55 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftKnee] = MakeTrack({ 0.0, 1.0 }, { 0.0, 1.10 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightKnee] = MakeTrack({ 0.0, 1.0 }, { 0.0, 1.10 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftAnkle] = MakeTrack({ 0.0, 1.0 }, { 0.0, -0.35 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightAnkle] = MakeTrack({ 0.0, 1.0 }, { 0.0, -0.35 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.Waist] = MakeTrack({ 0.0, 1.0 }, { 0.0, 0.30 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftShoulder] = MakeTrack({ 0.0, 1.0 }, { 0.0, -0.55 }, { 0.0, 0.0 }, { 0.0, -0.10 }),
            [JointIndex.RightShoulder] = MakeTrack({ 0.0, 1.0 }, { 0.0, -0.55 }, { 0.0, 0.0 }, { 0.0, 0.10 }),
        },
        VerticalPhases = { 0.0, 1.0 },
        VerticalValues = { 0.0, -0.42 },
    },
    Launch = {
        Duration = 0.10,
        EasingId = Config.EasingId.AnticipateOvershoot,
        Tracks = {
            [JointIndex.LeftHip] = MakeTrack({ 0.0, 1.0 }, { 0.55, -0.25 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightHip] = MakeTrack({ 0.0, 1.0 }, { 0.55, -0.25 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftKnee] = MakeTrack({ 0.0, 1.0 }, { 1.10, 0.10 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightKnee] = MakeTrack({ 0.0, 1.0 }, { 1.10, 0.10 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftAnkle] = MakeTrack({ 0.0, 1.0 }, { -0.35, 0.30 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightAnkle] = MakeTrack({ 0.0, 1.0 }, { -0.35, 0.30 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.Waist] = MakeTrack({ 0.0, 1.0 }, { 0.30, -0.06 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftShoulder] = MakeTrack({ 0.0, 1.0 }, { -0.55, -2.20 }, { 0.0, 0.0 }, { 0.0, -0.30 }),
            [JointIndex.RightShoulder] = MakeTrack({ 0.0, 1.0 }, { -0.55, -2.20 }, { 0.0, 0.0 }, { 0.0, 0.30 }),
        },
        VerticalPhases = { 0.0, 1.0 },
        VerticalValues = { -0.42, 0.10 },
    },
    Airborne = {
        Duration = 0.0,
        EasingId = Config.EasingId.SineInOut,
        Tracks = {
            [JointIndex.LeftHip] = MakeTrack({ 0.0, 1.0 }, { -0.55, -0.35 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightHip] = MakeTrack({ 0.0, 1.0 }, { -0.20, -0.45 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftKnee] = MakeTrack({ 0.0, 1.0 }, { 1.30, 1.05 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightKnee] = MakeTrack({ 0.0, 1.0 }, { 0.70, 0.95 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftAnkle] = MakeTrack({ 0.0, 1.0 }, { 0.22, 0.18 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightAnkle] = MakeTrack({ 0.0, 1.0 }, { 0.10, 0.18 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.Waist] = MakeTrack({ 0.0, 1.0 }, { -0.08, -0.10 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftShoulder] = MakeTrack({ 0.0, 1.0 }, { -2.20, -2.35 }, { 0.0, 0.0 }, { 0.0, -0.35 }),
            [JointIndex.RightShoulder] = MakeTrack({ 0.0, 1.0 }, { -2.20, -2.35 }, { 0.0, 0.0 }, { 0.0, 0.35 }),
            [JointIndex.LeftElbow] = MakeTrack({ 0.0, 1.0 }, { -0.55, -0.70 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightElbow] = MakeTrack({ 0.0, 1.0 }, { -0.55, -0.70 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
        },
        VerticalPhases = { 0.0, 1.0 },
        VerticalValues = { 0.10, 0.06 },
    },
    Landing = {
        Duration = 0.16,
        EasingId = Config.EasingId.BounceOut,
        Tracks = {
            [JointIndex.LeftHip] = MakeTrack({ 0.0, 1.0 }, { -0.55, 0.70 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightHip] = MakeTrack({ 0.0, 1.0 }, { -0.20, 0.70 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftKnee] = MakeTrack({ 0.0, 1.0 }, { 1.30, 1.25 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightKnee] = MakeTrack({ 0.0, 1.0 }, { 0.70, 1.25 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftAnkle] = MakeTrack({ 0.0, 1.0 }, { 0.22, -0.40 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightAnkle] = MakeTrack({ 0.0, 1.0 }, { 0.10, -0.40 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.Waist] = MakeTrack({ 0.0, 1.0 }, { -0.08, 0.35 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftShoulder] = MakeTrack({ 0.0, 1.0 }, { -2.35, 0.60 }, { 0.0, 0.0 }, { 0.0, -0.25 }),
            [JointIndex.RightShoulder] = MakeTrack({ 0.0, 1.0 }, { -2.35, 0.60 }, { 0.0, 0.0 }, { 0.0, 0.25 }),
        },
        VerticalPhases = { 0.0, 1.0 },
        VerticalValues = { 0.06, -0.48 },
    },
    Recovery = {
        Duration = 0.26,
        EasingId = Config.EasingId.Spring,
        Tracks = {
            [JointIndex.LeftHip] = MakeTrack({ 0.0, 1.0 }, { 0.70, 0.0 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightHip] = MakeTrack({ 0.0, 1.0 }, { 0.70, 0.0 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftKnee] = MakeTrack({ 0.0, 1.0 }, { 1.25, 0.08 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightKnee] = MakeTrack({ 0.0, 1.0 }, { 1.25, 0.08 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftAnkle] = MakeTrack({ 0.0, 1.0 }, { -0.40, 0.0 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.RightAnkle] = MakeTrack({ 0.0, 1.0 }, { -0.40, 0.0 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.Waist] = MakeTrack({ 0.0, 1.0 }, { 0.35, 0.0 }, { 0.0, 0.0 }, { 0.0, 0.0 }),
            [JointIndex.LeftShoulder] = MakeTrack({ 0.0, 1.0 }, { 0.60, 0.0 }, { 0.0, 0.0 }, { 0.0, -0.12 }),
            [JointIndex.RightShoulder] = MakeTrack({ 0.0, 1.0 }, { 0.60, 0.0 }, { 0.0, 0.0 }, { 0.0, 0.12 }),
        },
        VerticalPhases = { 0.0, 1.0 },
        VerticalValues = { -0.48, 0.0 },
    },
}

Config.Clips = Clips
Private.Clips = Clips
Private.MakeTrack = MakeTrack
end
