--[[
    Tools/verify/LuaTests/02-config-suite.luau

    Behavioural tests for the configuration layer:
      AnimationConfig (aggregator), AnimationConfigData, AnimationConfigMotion,
      AnimationConfigCompile.

    The configuration is pure data plus a compile pass, so it can be exercised completely
    outside Roblox. These tests pin down the invariants the runtime depends on: every clip
    compiles into numeric keyed arrays, every joint id is inside MaxJoints, wave presets are
    compiled in a deterministic order, and the easing ids referenced by the data really exist.
]]

return function(Env, Kit)
local Suite = { Name = "config" }

local CONFIG_PATH = "ReplicatedStorage.ProceduralAnimation.Shared.AnimationConfig"

local Config = nil

function Suite.Reset()
    Config = Env.Require(CONFIG_PATH)
end

local function CheckTrackShape(Cases, Prefix, Clip, Name)
    local Missing = {}
    for Index = 1, Clip.TrackCount do
        local Joint = Clip.TrackJoint[Index]
        local Phases = Clip.TrackPhase[Index]
        local X = Clip.TrackX[Index]
        local Y = Clip.TrackY[Index]
        local Z = Clip.TrackZ[Index]
        local KeyCount = Clip.TrackKeyCount[Index]
        if type(Joint) ~= "number" or Joint < 1 or Joint > Config.MaxJoints then
            Missing[#Missing + 1] = Name .. ".joint=" .. tostring(Joint)
        end
        if type(Phases) ~= "table" or #Phases ~= KeyCount then
            Missing[#Missing + 1] = Name .. ".phasesCount"
        end
        if type(X) ~= "table" or #X ~= KeyCount or #Y ~= KeyCount or #Z ~= KeyCount then
            Missing[#Missing + 1] = Name .. ".valueCount"
        end
        for KeyIndex = 1, KeyCount do
            local Phase = Phases[KeyIndex]
            if type(Phase) ~= "number" or Phase < 0.0 or Phase > 1.0 then
                Missing[#Missing + 1] = Name .. ".phaseRange@" .. tostring(Phase)
                break
            end
        end
    end
    Kit.Check(Prefix .. "." .. Name, #Missing == 0, #Missing == 0 and (Clip.TrackCount .. " tracks") or table.concat(Missing, ", "))
end

function Suite.Body(Cases)
    Kit.Begin(Cases, "config.")

    local Data = Config

    --=========================================================
    -- [1] CONSTANTS
    --=========================================================

    Kit.Equal("version", Data.Version, "1.1.0")
    Kit.Equal("maxJoints", Data.MaxJoints, 16)
    Kit.Equal("maxGestures", Data.MaxGestures, 4)
    Kit.Greater("sendRate", Data.SendRate, 0.0)
    Kit.Greater("jitterBuffer", Data.JitterBufferDepth, 0.0)

    -- Joint indices must be a dense 1..MaxJoints mapping with no duplicate slot.
    local SlotOwner = {}
    local Duplicates = {}
    local OutOfRange = {}
    local JointCount = 0
    for Key, Slot in pairs(Data.JointIndex) do
        JointCount += 1
        if type(Slot) ~= "number" or Slot < 1 or Slot > Data.MaxJoints then
            OutOfRange[#OutOfRange + 1] = tostring(Key)
        elseif SlotOwner[Slot] then
            Duplicates[#Duplicates + 1] = tostring(Key) .. "/" .. SlotOwner[Slot]
        else
            SlotOwner[Slot] = tostring(Key)
        end
    end
    Kit.Equal("jointIndex.count", JointCount, 16, "16 named joints")
    Kit.Check("jointIndex.inRange", #OutOfRange == 0, #OutOfRange == 0 and "all slots 1..16" or table.concat(OutOfRange, ", "))
    Kit.Check("jointIndex.uniqueSlots", #Duplicates == 0, #Duplicates == 0 and "no duplicate slot" or table.concat(Duplicates, ", "))

    local NamesMatch = true
    for Key, Slot in pairs(Data.JointIndex) do
        local Name = Data.JointNames[Slot]
        if type(Name) ~= "string" then
            NamesMatch = false
        end
    end
    Kit.True("jointNames.present", NamesMatch, "every slot has a name")

    --=========================================================
    -- [2] EASING IDS
    --=========================================================

    local MathLib = Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationMath")
    local EasingFailures = {}
    local EasingIdCount = 0
    for Key, EasingId in pairs(Data.EasingId) do
        EasingIdCount += 1
        if type(EasingId) ~= "number" or EasingId < 1 or EasingId > MathLib.EasingCount then
            EasingFailures[#EasingFailures + 1] = tostring(Key) .. "=" .. tostring(EasingId)
        end
    end
    Kit.Check("easingId.allResolve", #EasingFailures == 0,
        #EasingFailures == 0 and (EasingIdCount .. " ids resolve inside AnimationMath.EasingCount=" .. MathLib.EasingCount)
            or table.concat(EasingFailures, ", "))

    --=========================================================
    -- [3] CLIP COMPILATION
    --=========================================================

    local Compiled = Data.Compiled
    Kit.NotNil("compiled.present", Compiled, "Config.Compiled exists after the compile pass")

    CheckTrackShape(Cases, "config", Compiled.Idle, "idle")
    CheckTrackShape(Cases, "config", Compiled.Walk, "walk")
    CheckTrackShape(Cases, "config", Compiled.Run, "run")

    Kit.Greater("compile.idleTracks", Compiled.Idle.TrackCount, 0)
    Kit.Greater("compile.walkTracks", Compiled.Walk.TrackCount, 0)
    Kit.Greater("compile.runTracks", Compiled.Run.TrackCount, 0)
    Kit.Near("compile.walkStride", Compiled.Walk.Stride, 6.4, 1e-9)
    Kit.Near("compile.runStride", Compiled.Run.Stride, 9.5, 1e-9)
    Kit.Near("compile.idlePeriod", Compiled.Idle.Period, 3.2, 1e-9)

    Kit.Equal("compile.jumpSegments", #Compiled.Jump, 5, "Anticipation..Recovery")
    local JumpNames = { "anticipation", "launch", "airborne", "landing", "recovery" }
    for Index = 1, #Compiled.Jump do
        CheckTrackShape(Cases, "config", Compiled.Jump[Index], "jump." .. JumpNames[Index])
    end

    local GestureNames = { "Wave", "Point", "Nod" }
    for Index = 1, #GestureNames do
        local Clip = Compiled.Gestures[GestureNames[Index]]
        Kit.NotNil("compiled.gesture." .. GestureNames[Index], Clip)
        if Clip then
            CheckTrackShape(Cases, "config", Clip, "gesture." .. GestureNames[Index])
        end
    end

    -- The compile pass must flatten string-keyed authoring tracks to integer keys only,
    -- because the render loop reads TrackJoint/TrackPhase/TrackX/Y/Z by index.
    local StringKeyFound = nil
    for TrackIndex = 1, Compiled.Run.TrackCount do
        if type(Compiled.Run.TrackJoint[TrackIndex]) ~= "number" then
            StringKeyFound = TrackIndex
        end
    end
    Kit.Nil("compile.integerKeysOnly", StringKeyFound, "TrackJoint holds joint ids, not names")

    -- Track order must be deterministic and ascending, so blending order never changes.
    local Ascending = true
    for TrackIndex = 2, Compiled.Run.TrackCount do
        if Compiled.Run.TrackJoint[TrackIndex] <= Compiled.Run.TrackJoint[TrackIndex - 1] then
            Ascending = false
        end
    end
    Kit.True("compile.ascendingJointOrder", Ascending, "tracks are emitted in joint-id order")

    --=========================================================
    -- [4] WAVE COMPILATION IS DETERMINISTIC
    --=========================================================

    Kit.NotNil("waves.compiled", Compiled.Waves)
    Kit.NotNil("waves.order", Compiled.WaveOrder)

    local OrderCount = #Compiled.WaveOrder
    Kit.Greater("waves.orderCount", OrderCount, 0, OrderCount .. " presets")
    local Sorted = true
    local Seen = {}
    for Index = 1, OrderCount do
        local Name = Compiled.WaveOrder[Index]
        if type(Name) ~= "string" or Compiled.Waves[Name] == nil then
            Sorted = false
        end
        if Seen[Name] then
            Sorted = false
        end
        Seen[Name] = true
        if Index > 1 and Compiled.WaveOrder[Index - 1] > Name then
            Sorted = false
        end
    end
    Kit.True("waves.orderSorted", Sorted, "WaveOrder is sorted and duplicate free")

    local WaveCount = 0
    for _ in pairs(Data.Waves) do
        WaveCount += 1
    end
    Kit.Equal("waves.everyPresetCompiled", OrderCount, WaveCount, "no preset is skipped")

    local Breathing = Compiled.Waves[Data and "Breathing" or ""]
    Kit.NotNil("waves.breathingCompiled", Breathing)
    if Breathing then
        Kit.Equal("waves.breathingHarmonics", Breathing.HarmonicCount, 2)
        Kit.Greater("waves.breathingNoise", Breathing.NoiseAmplitude, 0.0)
    end

    -- Recompiling the same data twice must give identical numbers: this is the property the
    -- historical non-determinism defect violated.
    local Recomputed = MathLib.CompileWave(Data.Waves.Breathing)
    local Deterministic = Recomputed.HarmonicCount == Breathing.HarmonicCount
        and math.abs(Recomputed.Harmonics[1] - Breathing.Harmonics[1]) < 1e-12
        and math.abs(Recomputed.Harmonics[2] - Breathing.Harmonics[2]) < 1e-12
        and math.abs(Recomputed.Harmonics[3] - Breathing.Harmonics[3]) < 1e-12
    Kit.True("waves.recompileStable", Deterministic, "CompileWave is a pure function of the preset")

    --=========================================================
    -- [5] FABRIK AND GESTURE DATA
    --=========================================================

    local Spine = Data.FabrikChains and Data.FabrikChains.Spine
    Kit.NotNil("fabrik.spine", Spine)
    if Spine then
        Kit.Greater("fabrik.spineJoints", #Spine.Joints, 1)
        Kit.Greater("fabrik.spineIterations", Spine.MaxIterations, 0)
        Kit.Greater("fabrik.spineTolerance", Spine.Tolerance, 0.0)
        local InRange = true
        for Index = 1, #Spine.Joints do
            local Joint = Spine.Joints[Index]
            if Joint < 1 or Joint > Data.MaxJoints then
                InRange = false
            end
        end
        Kit.True("fabrik.spineJointsInRange", InRange)
    end

    local GestureCount = 0
    for _ in pairs(Data.Gestures) do
        GestureCount += 1
    end
    Kit.Greater("gestures.count", GestureCount, 0, GestureCount .. " authored gestures")

    --=========================================================
    -- [6] OPTIONAL JOINT POLICY
    --=========================================================

    Kit.Equal("optionalJoints.chest", Data.OptionalJoints[Data.JointIndex.Chest], true,
        "Chest is the only stock-R15-absent joint")
    Kit.Equal("optionalJoints.requireFlag", Data.RequireOptionalJoints, false,
        "optional joints are tolerated by default")

    --=========================================================
    -- [7] PACKET CONSTANTS MIRROR THE NETWORK LAYOUT
    --=========================================================

    Kit.Equal("packet.header", Data.Packet.Header, 1)
    Kit.Equal("packet.event", Data.Packet.Event, 2)
    Kit.Equal("packet.sequenceModulus", Data.Packet.SequenceModulus, 65536)
    Kit.Near("packet.angleQuantization", Data.Packet.AngleQuantization, 32767 / math.pi, 1e-9)

    --=========================================================
    -- [8] JOINT GROUP HELPERS
    --=========================================================

    Kit.Equal("legGroups.hip", #Data.LegJointIndex.Hip, 2)
    Kit.Equal("legGroups.knee", #Data.LegJointIndex.Knee, 2)
    Kit.Equal("legGroups.ankle", #Data.LegJointIndex.Ankle, 2)
    Kit.Equal("armGroups.shoulder", #Data.ArmJointIndex.Shoulder, 2)
    Kit.Equal("armGroups.elbow", #Data.ArmJointIndex.Elbow, 2)
    Kit.Equal("armGroups.wrist", #Data.ArmJointIndex.Wrist, 2)

    -- Left/right pairs must be distinct joints, otherwise IK would drive one leg twice.
    Kit.Check("legGroups.pairsDistinct",
        Data.LegJointIndex.Hip[1] ~= Data.LegJointIndex.Hip[2]
            and Data.LegJointIndex.Knee[1] ~= Data.LegJointIndex.Knee[2]
            and Data.LegJointIndex.Ankle[1] ~= Data.LegJointIndex.Ankle[2],
        "left and right slots differ")
end

return Suite
end
