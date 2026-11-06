--[[
    Tools/verify/LuaTests/01-math-suite.luau

    Behavioural tests for the mathematical layer:
      AnimationMathCore, AnimationMathCurves, AnimationMathIk, AnimationMathWaves and the
      AnimationMath aggregator.

    These run the real module source inside the real Luau VM. Nothing is re-implemented here;
    the expectations are independent mathematical properties (known easing values, spline
    reproduction of its own control points, FABRIK reachability, noise determinism) so a
    regression in the module shows up as a failure rather than as agreement with a copy.
]]

return function(Env, Kit)
local Suite = { Name = "math" }

local MATH_PATH = "ReplicatedStorage.ProceduralAnimation.Shared.AnimationMath"

local MathLib = nil

function Suite.Reset()
    MathLib = Env.Require(MATH_PATH)
end

function Suite.Body(Cases)
    Kit.Begin(Cases, "math.")

    local Math = MathLib

    --=========================================================
    -- [1] AGGREGATOR SURFACE
    --=========================================================

    Kit.NotNil("aggregator.Loaded", Math, "aggregator returns a table")

    local ExpectedExports = {
        "Ease", "Clamp01", "SmoothFactor", "ShortestAngle",
        "LerpNumber", "LerpVector3", "LerpCFrame", "SlerpCFrame",
        "BezierQuadratic", "BezierCubic", "BezierQuadraticDerivative", "BezierCubicDerivative",
        "RegisterBezierCurve", "GetSamplerCount",
        "CompileSpline", "SampleSpline",
        "SolveFabrik",
        "Noise1D", "SampleWave", "CompileWave", "SampleCompiledWave",
    }
    local Missing = {}
    for Index = 1, #ExpectedExports do
        local Name = ExpectedExports[Index]
        if type(Math[Name]) ~= "function" then
            Missing[#Missing + 1] = Name
        end
    end
    Kit.Check("exports.allPresent", #Missing == 0, #Missing > 0 and ("missing: " .. table.concat(Missing, ", ")) or "22/22 present")

    local Phase1Exports = { "CompileWave", "SampleWave", "SampleCompiledWave", "Noise1D", "SolveFabrik" }
    local Phase1Missing = {}
    for Index = 1, #Phase1Exports do
        if type(Math[Phase1Exports[Index]]) ~= "function" then
            Phase1Missing[#Phase1Missing + 1] = Phase1Exports[Index]
        end
    end
    Kit.Check("exports.phase1FivePresent", #Phase1Missing == 0,
        #Phase1Missing > 0 and ("missing: " .. table.concat(Phase1Missing, ", ")) or "CompileWave, SampleWave, SampleCompiledWave, Noise1D, SolveFabrik")

    -- The historical defect was FABRIK and wave definitions nested inside Ease. If that were
    -- still true the exports above would be nil, so the pair of checks below record the
    -- concrete evidence: Escape at a known value AND the nested symbols absent.
    local EaseAtHalf = Math.Ease(1, 0.5)
    Kit.Near("exports.easeLinearAtHalf", EaseAtHalf, 0.5, 1e-12, "Ease(1, 0.5)")

    --=========================================================
    -- [2] SCALAR HELPERS
    --=========================================================

    Kit.Near("clamp01.below", Math.Clamp01(-3.5), 0.0, 0.0)
    Kit.Near("clamp01.inside", Math.Clamp01(0.42), 0.42, 0.0)
    Kit.Near("clamp01.above", Math.Clamp01(9.0), 1.0, 0.0)

    Kit.Near("lerp.numberStart", Math.LerpNumber(2.0, 10.0, 0.0), 2.0, 0.0)
    Kit.Near("lerp.numberEnd", Math.LerpNumber(2.0, 10.0, 1.0), 10.0, 0.0)
    Kit.Near("lerp.numberMid", Math.LerpNumber(2.0, 10.0, 0.25), 4.0, 1e-12)

    Kit.Near("smoothFactor.zeroDt", Math.SmoothFactor(16.0, 0.0), 0.0, 0.0)
    Kit.Near("smoothFactor.largeDt", Math.SmoothFactor(16.0, 10.0), 1.0, 1e-9)

    -- Frame-rate independence: two half-steps must land close to one full step.
    local FullStep = Math.SmoothFactor(9.0, 1 / 30)
    local HalfA = Math.SmoothFactor(9.0, 1 / 60)
    local Composite = HalfA + (1.0 - HalfA) * HalfA
    Kit.Near("smoothFactor.frameRateIndependent", Composite, FullStep, 1e-9, "two 1/60 steps vs one 1/30 step")

    Kit.Near("shortestAngle.wrapUp", Math.ShortestAngle(0.0, math.pi * 1.5), -math.pi * 0.5, 1e-9)
    Kit.Near("shortestAngle.wrapDown", Math.ShortestAngle(math.pi * 1.5, 0.0), math.pi * 0.5, 1e-9)
    Kit.Near("shortestAngle.identity", Math.ShortestAngle(1.0, 1.0), 0.0, 0.0)

    --=========================================================
    -- [3] EASING TABLE
    --=========================================================

    Kit.Equal("easing.count", Math.EasingCount, 35, "ids 1..35 registered by AnimationMathCore")

    -- Every registered easing must be finite and pinned at both ends of the unit interval.
    local EndpointFailures = {}
    for EasingId = 1, Math.EasingCount do
        local AtZero = Math.Ease(EasingId, 0.0)
        local AtOne = Math.Ease(EasingId, 1.0)
        if AtZero ~= AtZero or AtOne ~= AtOne then
            EndpointFailures[#EndpointFailures + 1] = EasingId .. ":NaN"
        elseif math.abs(AtZero) > 1e-6 then
            EndpointFailures[#EndpointFailures + 1] = EasingId .. ":f(0)=" .. tostring(AtZero)
        elseif math.abs(AtOne - 1.0) > 1e-6 then
            EndpointFailures[#EndpointFailures + 1] = EasingId .. ":f(1)=" .. tostring(AtOne)
        end
    end
    Kit.Check("easing.endpoints", #EndpointFailures == 0,
        #EndpointFailures == 0 and "35/35 ease from 0 to 1" or table.concat(EndpointFailures, ", "))

    Kit.Near("easing.sineInQuarter", Math.Ease(2, 0.5), 1.0 - math.cos(math.pi * 0.25), 1e-12)
    Kit.Near("easing.quadInQuarter", Math.Ease(8, 0.5), 0.25, 1e-12)
    Kit.Near("easing.cubicInHalf", Math.Ease(29, 0.5), 0.125, 1e-12)
    Kit.Near("easing.bounceOutOne", Math.Ease(18, 1.0), 1.0, 1e-12)
    Kit.Near("easing.unknownIdFallsThrough", Math.Ease(0, 0.37), 0.37, 0.0, "unknown id returns alpha")
    Kit.Near("easing.unknownNegativeId", Math.Ease(-5, 0.8), 0.8, 0.0)

    -- Monotonic sampling: easing must never escape into wild values across the interval.
    local OutOfRange = {}
    for EasingId = 1, Math.EasingCount do
        for Step = 0, 40 do
            local Value = Math.Ease(EasingId, Step / 40)
            if Value ~= Value or Value == math.huge or Value == -math.huge then
                OutOfRange[#OutOfRange + 1] = EasingId .. "@" .. Step
            elseif math.abs(Value) > 12.0 then
                OutOfRange[#OutOfRange + 1] = EasingId .. "@" .. Step .. "=" .. tostring(Value)
            end
        end
    end
    Kit.Check("easing.finite", #OutOfRange == 0,
        #OutOfRange == 0 and "35 easings x 41 samples all finite and bounded" or table.concat(OutOfRange, ", "))

    --=========================================================
    -- [4] VECTOR AND CFRAME LERP
    --=========================================================

    local Vector3 = _G.Vector3
    local CFrame = _G.CFrame

    local From = Vector3.new(1.0, 2.0, 3.0)
    local To = Vector3.new(5.0, 6.0, 7.0)
    local Mid = Math.LerpVector3(From, To, 0.5)
    Kit.Near("lerpVector3.x", Mid.X, 3.0, 1e-12)
    Kit.Near("lerpVector3.y", Mid.Y, 4.0, 1e-12)
    Kit.Near("lerpVector3.z", Mid.Z, 5.0, 1e-12)
    local Start = Math.LerpVector3(From, To, 0.0)
    Kit.Near("lerpVector3.alphaZero", Start.X, 1.0, 1e-12)

    local CF0 = CFrame.new(0.0, 0.0, 0.0)
    local CF1 = CFrame.fromEulerAnglesXYZ(0.0, math.pi * 0.5, 0.0) + Vector3.new(10.0, 0.0, 0.0)
    -- REGRESSION GUARD (defect F-01): when the rotations are nearly identical, LerpCFrame routes
    -- to SlerpCFrame, which rebuilds the CFrame from the source position and therefore drops the
    -- translation. Position must interpolate regardless of which rotation path is taken.
    local CFMid = Math.LerpCFrame(CF0, CF1, 0.5)
    Kit.Near("lerpCFrame.translation", CFMid.Position.X, 5.0, 1e-9, "identical rotations must still translate")
    local CFEnd = Math.LerpCFrame(CF0, CF1, 1.0)
    Kit.True("lerpCFrame.alphaOne", CFEnd == CF1, "alpha 1 returns the target untouched")

    -- SlerpCFrame must preserve rotation magnitude (unit quaternion) and hit its endpoints.
    local SlerpMid = Math.SlerpCFrame(CF0, CFrame.fromEulerAnglesXYZ(0.0, math.pi * 0.5, 0.0), 0.5)
    local XAxis = SlerpMid.XVector
    local AxisLength = math.sqrt(XAxis.X * XAxis.X + XAxis.Y * XAxis.Y + XAxis.Z * XAxis.Z)
    Kit.Near("slerpCFrame.orthonormal", AxisLength, 1.0, 1e-6, "rotation columns stay unit length")
    Kit.Near("slerpCFrame.halfAngle", math.atan2(SlerpMid.ZVector.X, SlerpMid.XVector.X), math.pi * 0.25, 1e-6)

    local SlerpStart = Math.SlerpCFrame(CF0, CF1, 0.0)
    Kit.True("slerpCFrame.alphaZero", SlerpStart == CF0)
    local SlerpEnd = Math.SlerpCFrame(CF0, CF1, 1.0)
    Kit.True("slerpCFrame.alphaOne", SlerpEnd == CF1)

    -- Nearly identical rotations take the small-angle fallback; it must stay stable, not NaN.
    local TinyRotation = CFrame.fromEulerAnglesXYZ(0.0, 1e-7, 0.0)
    local TinyMid = Math.SlerpCFrame(CF0, TinyRotation, 0.5)
    local TinyAxis = TinyMid.XVector
    Kit.Near("slerpCFrame.smallAngleStable", math.sqrt(TinyAxis.X * TinyAxis.X + TinyAxis.Y * TinyAxis.Y + TinyAxis.Z * TinyAxis.Z), 1.0, 1e-9)

    --=========================================================
    -- [5] BEZIER
    --=========================================================

    Kit.Near("bezier.quadraticEndpoints.start", Math.BezierQuadratic(0.0, 5.0, 10.0, 0.0), 0.0, 1e-12)
    Kit.Near("bezier.quadraticEndpoints.finish", Math.BezierQuadratic(0.0, 5.0, 10.0, 1.0), 10.0, 1e-12)
    Kit.Near("bezier.quadraticMid", Math.BezierQuadratic(0.0, 5.0, 10.0, 0.5), 5.0, 1e-12, "de Casteljau at t=0.5")
    Kit.Near("bezier.cubicMid", Math.BezierCubic(0.0, 0.0, 10.0, 10.0, 0.5), 5.0, 1e-12)
    Kit.Near("bezier.quadraticDerivativeMid", Math.BezierQuadraticDerivative(0.0, 5.0, 10.0, 0.5), 10.0, 1e-12)
    Kit.Near("bezier.cubicDerivativeMid", Math.BezierCubicDerivative(0.0, 0.0, 10.0, 10.0, 0.5), 15.0, 1e-12)

    -- Argument alignment: a quadratic whose control points are symmetric must be evaluated
    -- with (P0, P1, P2, Alpha) in that order, not (P0, P1, Alpha, P2). If the arguments were
    -- misaligned, the t=0.5 value below would not equal the analytic 6.25.
    -- Argument alignment: if the arguments were misaligned the t=0.5 value would not equal the
    -- analytic de Casteljau midpoint 0.25*P0 + 0.5*P1 + 0.25*P2 = 3.75.
    Kit.Near("bezier.argumentOrder", Math.BezierQuadratic(0.0, 2.5, 10.0, 0.5), 3.75, 1e-12,
        "0.25*0 + 0.5*2.5 + 0.25*10")

    --=========================================================
    -- [6] SPLINES
    --=========================================================

    local Times = { 0.0, 1.0, 2.0, 3.0 }
    local Values = { 0.0, 4.0, 2.0, 8.0 }

    local Catmull = Math.CompileSpline("CatmullRom", Times, Values)
    Kit.Equal("spline.catmull.count", Catmull.Count, 4)
    Kit.Near("spline.catmull.firstKey", Math.SampleSpline(Catmull, 0.0), 0.0, 1e-9)
    Kit.Near("spline.catmull.lastKey", Math.SampleSpline(Catmull, 3.0), 8.0, 1e-9)
    Kit.Near("spline.catmull.interiorKey1", Math.SampleSpline(Catmull, 1.0), 4.0, 1e-9, "interpolant reproduces control points")
    Kit.Near("spline.catmull.interiorKey2", Math.SampleSpline(Catmull, 2.0), 2.0, 1e-9)
    Kit.Near("spline.catmull.clampBelow", Math.SampleSpline(Catmull, -5.0), 0.0, 1e-9)
    Kit.Near("spline.catmull.clampAbove", Math.SampleSpline(Catmull, 99.0), 8.0, 1e-9)

    local Natural = Math.CompileSpline("Natural", Times, Values)
    Kit.Near("spline.natural.firstKey", Math.SampleSpline(Natural, 0.0), 0.0, 1e-9)
    Kit.Near("spline.natural.lastKey", Math.SampleSpline(Natural, 3.0), 8.0, 1e-9)
    Kit.Near("spline.natural.interiorReproduced", Math.SampleSpline(Natural, 1.0), 4.0, 1e-6, "C2 spline passes through its knots")

    local Single = Math.CompileSpline("CatmullRom", { 0.0 }, { 3.5 })
    Kit.Near("spline.singleKey", Math.SampleSpline(Single, 0.5), 3.5, 1e-12)
    local Empty = Math.CompileSpline("CatmullRom", {}, {})
    Kit.Near("spline.emptyReturnsZero", Math.SampleSpline(Empty, 1.0), 0.0, 0.0)

    -- Sampling must be allocation free in practice: repeated calls return identical values.
    local RepeatA = Math.SampleSpline(Catmull, 1.37)
    local RepeatB = Math.SampleSpline(Catmull, 1.37)
    Kit.Equal("spline.deterministic", RepeatA, RepeatB)

    --=========================================================
    -- [7] FABRIK
    --=========================================================

    local Lengths = { 1.0, 1.0, 1.0 }
    local Positions = {
        Vector3.new(0.0, 0.0, 0.0),
        Vector3.new(1.0, 0.0, 0.0),
        Vector3.new(2.0, 0.0, 0.0),
        Vector3.new(3.0, 0.0, 0.0),
    }
    local Target = Vector3.new(0.0, 3.0, 0.0)
    Math.SolveFabrik(Positions, Lengths, Target, 0.01, 16)
    local RootAfter = Positions[1]
    local EndAfter = Positions[4]
    Kit.Near("fabrik.rootPinned.x", RootAfter.X, 0.0, 1e-6, "root stays at the origin")
    Kit.Near("fabrik.rootPinned.y", RootAfter.Y, 0.0, 1e-6)
    local ReachError = math.sqrt(
        (EndAfter.X - Target.X) ^ 2 + (EndAfter.Y - Target.Y) ^ 2 + (EndAfter.Z - Target.Z) ^ 2
    )
    Kit.Less("fabrik.reachesTarget", ReachError, 0.05, string.format("end effector error %.6g", ReachError))

    -- Bone lengths are preserved by the solve.
    local SumAfter = 0.0
    for Index = 1, 3 do
        local A = Positions[Index]
        local B = Positions[Index + 1]
        SumAfter += math.sqrt((B.X - A.X) ^ 2 + (B.Y - A.Y) ^ 2 + (B.Z - A.Z) ^ 2)
    end
    Kit.Near("fabrik.lengthPreserved", SumAfter, 3.0, 1e-4)

    -- An unreachable target stretches the chain straight toward it, still conserving length.
    local FarPositions = {
        Vector3.new(0.0, 0.0, 0.0),
        Vector3.new(1.0, 0.0, 0.0),
        Vector3.new(2.0, 0.0, 0.0),
        Vector3.new(3.0, 0.0, 0.0),
    }
    Math.SolveFabrik(FarPositions, Lengths, Vector3.new(0.0, 0.0, 50.0), 0.01, 16)
    local FarEnd = FarPositions[4]
    local FarDistance = math.sqrt(FarEnd.X * FarEnd.X + FarEnd.Y * FarEnd.Y + FarEnd.Z * FarEnd.Z)
    Kit.Near("fabrik.unreachableStretches", FarDistance, 3.0, 1e-4, "chain ends 3 studs out, its total length")

    local ZeroLengths = {}
    local ZeroPositions = { Vector3.new(0.0, 0.0, 0.0) }
    local ZeroOk = Kit.Guard("fabrik.emptyChainNoError", function()
        Math.SolveFabrik(ZeroPositions, ZeroLengths, Vector3.new(1.0, 1.0, 1.0), 0.01, 10)
        return true
    end)
    Kit.True("fabrik.emptyChainReturnsCleanly", ZeroOk)

    --=========================================================
    -- [8] NOISE AND WAVES
    --=========================================================

    local NoiseA = Math.Noise1D(12.34)
    local NoiseB = Math.Noise1D(12.34)
    Kit.Equal("noise.deterministic", NoiseA, NoiseB)
    Kit.Check("noise.inRange", NoiseA >= -1.01 and NoiseA <= 1.01, string.format("Noise1D = %.6f", NoiseA))
    -- One-dimensional value noise interpolates between lattice points, so a single pair of
    -- integer inputs can legitimately share a value. Variety is asserted over a grid instead.
    local DistinctValues = {}
    local DistinctCount = 0
    for Step = 0, 40 do
        local Sample = Math.Noise1D(Step * 0.37)
        local Key = string.format("%.6f", Sample)
        if not DistinctValues[Key] then
            DistinctValues[Key] = true
            DistinctCount += 1
        end
    end
    Kit.Greater("noise.varies", DistinctCount, 20, DistinctCount .. " distinct values over 41 samples")
    local NoiseFinite = true
    for Index = 1, 200 do
        local Value = Math.Noise1D(Index * 0.37 - 20.0)
        if Value ~= Value or math.abs(Value) > 1.01 then
            NoiseFinite = false
        end
    end
    Kit.True("noise.finiteOverRange", NoiseFinite)

    local Wave = {
        Harmonics = {
            { Amplitude = 0.5, Frequency = 0.25, Phase = 0.0 },
            { Amplitude = 0.25, Frequency = 0.5, Phase = math.pi * 0.5 },
        },
        NoiseAmplitude = 0.05,
        NoiseFrequency = 1.5,
    }
    local Compiled = Math.CompileWave(Wave)
    Kit.Equal("wave.compiledHarmonicCount", Compiled.HarmonicCount, 2)
    Kit.Near("wave.compiledFlatAmplitude", Compiled.Harmonics[1], 0.5, 0.0, "flat layout [Amp, Freq, Phase, ...]")
    Kit.Near("wave.compiledFlatFrequency", Compiled.Harmonics[2], 0.25, 0.0)
    Kit.Near("wave.compiledFlatPhase", Compiled.Harmonics[6], math.pi * 0.5, 0.0)
    Kit.Near("wave.compiledNoiseAmplitude", Compiled.NoiseAmplitude, 0.05, 0.0)

    local Direct = Math.SampleWave(Wave, 1.25)
    local Fast = Math.SampleCompiledWave(Compiled, 1.25)
    Kit.Near("wave.compiledMatchesDirect", Fast, Direct, 1e-12, "CompileWave + SampleCompiledWave == SampleWave")

    local DeterminismOk = true
    for Index = 1, 50 do
        local T = Index * 0.137
        if Math.SampleCompiledWave(Compiled, T) ~= Math.SampleCompiledWave(Compiled, T) then
            DeterminismOk = false
        end
    end
    Kit.True("wave.samplingDeterministic", DeterminismOk)

    local EmptyWave = Math.CompileWave({ Harmonics = {} })
    Kit.Near("wave.emptyIsZero", Math.SampleCompiledWave(EmptyWave, 3.0), 0.0, 0.0)

    --=========================================================
    -- [9] BEZIER REGISTRY
    --=========================================================

    local BaseCount = Math.GetSamplerCount()
    local QuadraticId = Math.RegisterBezierCurve(1, 0.0, 0.5, 1.0)
    Kit.Check("bezier.registerReturnsId", QuadraticId >= BaseCount + 1, "id = " .. tostring(QuadraticId))
    Kit.Near("bezier.registeredQuadraticStart", Math.Ease(QuadraticId, 0.0), 0.0, 1e-12)
    Kit.Near("bezier.registeredQuadraticEnd", Math.Ease(QuadraticId, 1.0), 1.0, 1e-12)
    Kit.Near("bezier.registeredQuadraticMid", Math.Ease(QuadraticId, 0.5), 0.5, 1e-12)

    local CubicId = Math.RegisterBezierCurve(2, 0.0, 0.0, 1.0, 1.0)
    Kit.Near("bezier.registeredCubicMid", Math.Ease(CubicId, 0.5), 0.5, 1e-12)
    Kit.Equal("bezier.invalidKindRejected", Math.RegisterBezierCurve(9, 0.0, 0.0, 0.0), 0)
end

return Suite
end
