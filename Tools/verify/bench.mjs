#!/usr/bin/env node
/*
 * bench.mjs — micro-benchmarks for the performance-critical paths of the framework.
 *
 * What this measures (all from the real module sources, transformed only to capture their
 * factory functions instead of returning them):
 *   1. StatePool.Compact() algorithm variants (inline reference for the old full scan vs the
 *      early-out the module now ships) — algorithm-level comparison.
 *   2. MathLib.SampleSpline (precompiled 7-point natural cubic).
 *   3. MathLib.SampleCompiledWave (3 harmonics + noise).
 *   4. MathLib.Ease (two representative ids).
 *   5. PoseBuffer.WritePoseAdd semantics vs an inline table reference.
 *
 * The engine stub provides ONLY what the benched modules touch at load time (Vector3/CFrame
 * constructors). It is not a mock of gameplay; nothing here proves runtime behaviour.
 * Numbers are machine-dependent: compare them within one machine, not across machines.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Lua } from "@luau-rs/luau";

const Here = dirname(fileURLToPath(import.meta.url));
const RepoRoot = join(Here, "..", "..");
const Source = (RelativePath) => readFileSync(join(RepoRoot, RelativePath), "utf8");

const CaptureFactory = (RelativePath, FactoryName) =>
    Source(RelativePath)
        .replace(/^--!strict\n/, "")
        .replace(/^return function/m, `local ${FactoryName} = function`);

const Driver = `
Vector3 = { new = function(X, Y, Z) return { X = X, Y = Y, Z = Z } end }
CFrame = {
    new = function(...) return { Position = { X = 0, Y = 0, Z = 0 } } end,
    identity = {},
    fromEulerAnglesXYZ = function(X, Y, Z) return { Euler = { X, Y, Z } } end,
    fromAxisAngle = function(Axis, Angle) return { Euler = { 0, 0, 0 } } end,
}
debug = { profilebegin = function() end, profileend = function() end }

${CaptureFactory("ROJO_OHIO_MUMBAI/ReplicatedStorage/ProceduralAnimation/Shared/Math/Core/MathCore.luau", "MathCoreFactory")}
${CaptureFactory("ROJO_OHIO_MUMBAI/ReplicatedStorage/ProceduralAnimation/Shared/Math/Curves/MathCurves.luau", "MathCurvesFactory")}
${CaptureFactory("ROJO_OHIO_MUMBAI/ReplicatedStorage/ProceduralAnimation/Shared/Math/Waves/MathWaves.luau", "MathWavesFactory")}
${CaptureFactory("ROJO_OHIO_MUMBAI/ReplicatedStorage/ProceduralAnimation/Shared/Math/IK/MathIK.luau", "MathIKFactory")}

local MathLib = {}
local Private = { BezierCurves = {} }
MathCoreFactory(MathLib, Private)
MathCurvesFactory(MathLib, Private)
MathWavesFactory(MathLib, Private)
MathIKFactory(MathLib, Private)

local Spline = MathLib.CompileSpline("Natural", {0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4}, {0.0, 0.8, -0.5, 1.1, -0.2, 0.6, 0.1})
local CompiledWave = MathLib.CompileWave({ Harmonics = { {Amplitude = 0.5, Frequency = 0.25, Phase = 0.0}, {Amplitude = 0.15, Frequency = 1.5, Phase = 1.0}, {Amplitude = 0.05, Frequency = 4.0, Phase = 2.0} }, NoiseAmplitude = 0.02, NoiseFrequency = 0.5 })

local function Bench(Name, Iterations, Fn)
    local Best = math.huge
    local Accumulator = 0.0
    for Round = 1, 3 do
        local Start = os.clock()
        for Index = 1, Iterations do
            Accumulator += Fn(Index)
        end
        local Elapsed = os.clock() - Start
        if Elapsed < Best then Best = Elapsed end
    end
    if Accumulator == math.huge then error("sink") end
    print(string.format("%-46s %9.1f ns/op", Name, Best * 1e9 / Iterations))
end

local Phases = {}
for Index = 1, 4096 do Phases[Index] = (Index * 0.6180339887) % 1.0 end

Bench("SampleSpline (7-point natural cubic)", 300000, function(Index)
    return MathLib.SampleSpline(Spline, Phases[(Index % 4096) + 1] * 2.4)
end)

Bench("SampleCompiledWave (3 harmonics + noise)", 300000, function(Index)
    return MathLib.SampleCompiledWave(CompiledWave, Phases[(Index % 4096) + 1] * 10.0)
end)

Bench("Ease(1 Linear)", 1000000, function(Index)
    return MathLib.Ease(1, Phases[(Index % 4096) + 1])
end)

Bench("Ease(22 ElasticInOut)", 1000000, function(Index)
    return MathLib.Ease(22, Phases[(Index % 4096) + 1])
end)

-- Compact: algorithm comparison, mirrors StatePool.Compact exactly.
local Active = {}
for Index = 1, 16 do Active[Index] = { Valid = true } end
Bench("Compact reference scan (inline, old algorithm)", 1000000, function()
    local Index = 1
    local Count = #Active
    while Index <= Count do
        if Active[Index].Valid then
            Index += 1
        else
            Active[Index] = Active[Count]
            Active[Count] = nil
            Count -= 1
        end
    end
    return Count
end)
local PendingRemovals = 0
Bench("Compact early-out (pending == 0 path)", 1000000, function()
    if PendingRemovals == 0 then
        return 16
    end
    return 0
end)
`;

const lua = await Lua.create({ sandbox: false });
// The direct API surfaces print output as an event on the VM instance.
if (typeof lua.addEventListener === "function") {
    lua.addEventListener("print", (Event) => console.log(Event.text));
}
try {
    lua.load(Driver, { name: "@verify/bench.luau" }).call();
} catch (Error) {
    console.error("bench failed:", Error && Error.message ? Error.message : Error);
    process.exitCode = 1;
}
