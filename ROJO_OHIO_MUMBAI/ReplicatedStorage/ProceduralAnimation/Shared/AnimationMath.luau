-- ProceduralAnimation/Shared/AnimationMath
-- Aggregator. Sections [1]-[4] are in AnimationMathCore, [5]-[6] in AnimationMathCurves,
-- [7] in AnimationMathIk and [8] in AnimationMathWaves. Sub-modules require nothing,
-- so the require graph is acyclic; each is a factory populating the shared tables.

local MathLib = {}
local Private = {
    BezierCurves = {},
}

require(script.Parent.Math.Core.MathCore)(MathLib, Private)
require(script.Parent.Math.Curves.MathCurves)(MathLib, Private)
require(script.Parent.Math.IK.MathIK)(MathLib, Private)
require(script.Parent.Math.Waves.MathWaves)(MathLib, Private)

return MathLib