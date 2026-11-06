-- ProceduralAnimation/Shared/AnimationMath
-- Aggregator. Sections [1]-[4] are in AnimationMathCore, [5]-[6] in AnimationMathCurves,
-- [7] in AnimationMathIk and [8] in AnimationMathWaves. Sub-modules require nothing,
-- so the require graph is acyclic; each is a factory populating the shared tables.

local MathLib = {}
local Private = {
    BezierCurves = {},
}

require(script.Parent.AnimationMathCore)(MathLib, Private)
require(script.Parent.AnimationMathCurves)(MathLib, Private)
require(script.Parent.AnimationMathIk)(MathLib, Private)
require(script.Parent.AnimationMathWaves)(MathLib, Private)

return MathLib