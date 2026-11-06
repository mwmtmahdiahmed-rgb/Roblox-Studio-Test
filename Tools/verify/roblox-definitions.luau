--!strict
-- roblox-definitions.luau
-- Partial hand-written Roblox API surface for the offline type checker.
--
-- WHY THIS FILE EXISTS
-- The verification harness runs the real Luau type checker (@luau-rs/luau) over the project
-- with no Roblox SDK present, so every Roblox global (`game`, `script`, `Vector3`, ...) comes
-- back as "Unknown global". That noise buried the diagnostics that actually mattered, and the
-- moment real checking was switched on it surfaced four genuine defects (an uninitialised
-- function upvalue, an undeclared `UpperTorso`, a nil `MathLib` on the jump path and a bare
-- `ReleaseRemotePose` in shutdown).
--
-- This file is deliberately PARTIAL. It declares only what the framework touches, and every
-- value is typed loosely (`any` / `number` / `string`) so the checker can still catch the class
-- of bug above -- undefined names and nil indexing -- without pretending to model Roblox exactly.
-- Diagnostics that still fall out of the gaps are reported separately as "definition gaps" by
-- verify.mjs, never silently dropped.
--
-- DSL NOTE (see @luau-rs/luau definition.rs):
--   `declare NAME: <type>` registers a global value.
--   `@checked` makes a declaration participating in strict checking.
--   `declare class` is not enabled in this build.
--   Type names MUST be exported (`export type X = ...`). A bare `type X = ...` inside a
--   definition module does NOT resolve ("Unknown type"), and declaring X as a *value* instead
--   makes the checker fail with "attempting to negate a non-testable type" the moment a module
--   annotates with it. `export type` is the only form that works; do not "simplify" it.

--=========================================================
-- [1] ROBLOX CORE DATATYPES
--=========================================================

declare Vector3: {
    new: (x: number, y: number, z: number) -> any,
    zero: any,
    one: any,
    xAxis: any,
    yAxis: any,
    zAxis: any,
}

declare Vector2: {
    new: (x: number, y: number) -> any,
    zero: any,
    one: any,
}

declare CFrame: {
    new: (...any) -> any,
    identity: any,
    lookAt: (any, any, any) -> any,
    fromEulerAnglesXYZ: (number, number, number) -> any,
    fromAxisAngle: (any, number) -> any,
    Angles: (number, number, number) -> any,
    AnglesYXZ: (number, number, number) -> any,
}

declare Color3: {
    new: (number, number, number) -> any,
    fromRGB: (number, number, number) -> any,
}

declare UDim: any
declare UDim2: any
declare Ray: any
declare Region3: any
declare NumberRange: any
declare NumberSequence: any
declare ColorSequence: any
declare TweenInfo: any

-- RaycastParams is constructed once during ground-alignment setup.
declare RaycastParams: {
    new: () -> any,
}

--=========================================================
-- [2] ENUMS
--=========================================================

-- Enumerations are read-only tables of items; modelling every member would be noise, so the
-- index result is `any` while the individual enum tables the project reads are named below.
declare Enum: {
    HumanoidStateType: any,
    HumanoidRigType: any,
    Material: any,
    EasingStyle: any,
    EasingDirection: any,
    RaycastFilterType: any,
    RunService: any,
    KeyCode: any,
    UserInputType: any,
    CameraType: any,
    NormalId: any,
    Axis: any,
}

--=========================================================
-- [3] SERVICES AND ENGINE LOCALS
--=========================================================

declare game: any
declare workspace: any
declare script: any
declare plugin: any
declare shared: any

-- `Instance` is both a namespace and the membership test used by the mocks.
declare Instance: {
    new: (...any) -> any,
    fromExisting: (any) -> any,
    IsA: (any, string) -> boolean,
}

--=========================================================
-- [4] GLOBAL FUNCTIONS
--=========================================================
-- Do NOT re-declare the standard library (pcall, xpcall, select, unpack, rawget, rawset,
-- rawequal, rawlen, typeof, print, require, loadstring, getfenv, setfenv). The analyser ships
-- its own typed versions and narrowing on them is understood; shadowing them with a loose
-- `any`-flavoured signature breaks control-flow analysis and the checker dies with
-- "attempting to negate a non-testable type" on the first `if not pcall(...)`. Only the
-- globals the analyser does not know are declared here.

@checked declare function warn(...: any): ()
@checked declare function tick(): number
@checked declare function time(): number
@checked declare function elapsedTime(): number
@checked declare function settings(): any

--=========================================================
-- [5] `task` SCHEDULER
--=========================================================

-- `debug` is partially known to the analyser; profiling hooks are not. Declaring the whole
-- namespace as-is would clash, so only the missing keys are provided via a loose table.
declare debug: {
    profilebegin: (string) -> (),
    profileend: () -> (),
}

declare task: {
    spawn: (...any) -> any,
    defer: (...any) -> any,
    delay: (number, (...any) -> ...any, ...any) -> any,
    wait: (number?) -> number,
    cancel: (any) -> (),
    synchronize: ((...any) -> ...any) -> any,
    desynchronize: ((...any) -> ...any) -> any,
}

--=========================================================
-- [6] TYPE NAMES THE PROJECT ANNOTATES WITH
--=========================================================
-- `export` is required -- see the DSL note at the top of this file.

export type RBXScriptConnection = {
    Disconnect: (self: RBXScriptConnection) -> (),
    Connected: boolean,
}

export type RBXScriptSignal = {
    Connect: (self: RBXScriptSignal, callback: (...any) -> ...any) -> RBXScriptConnection,
    Once: (self: RBXScriptSignal, callback: (...any) -> ...any) -> RBXScriptConnection,
    Wait: (self: RBXScriptSignal) -> ...any,
}
