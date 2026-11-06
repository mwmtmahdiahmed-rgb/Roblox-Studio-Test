-- ProceduralAnimation/Shared/AnimationConfig
-- Aggregator. [1]-[2] constants and clip authoring live in AnimationConfigData,
-- [2.5]-[2.6] waves/fabrik/Gestures in AnimationConfigMotion, and the [3] compile
-- pass in AnimationConfigCompile. Sub-modules require nothing except the compile
-- pass, which requires AnimationMath; the require graph stays acyclic.

local Config = {}
local Private = {}

require(script.Parent.Config.Data.ConfigData)(Config, Private)
require(script.Parent.Config.Data.ConfigMotion)(Config, Private)
require(script.Parent.Config.Compile.ConfigCompile)(Config, Private)

return Config