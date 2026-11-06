-- ProceduralAnimation/Client/CharacterMotionState
-- The character-level motion state machine that sits above raw clip sampling:
--   * jump phases (grounded -> anticipation -> launch -> airborne -> landing -> recovery),
--   * gesture playback with fade-in/hold/fade-out,
--   * the clip-start / landing bus notifications those transitions raise.
--
-- Split out of ProceduralAnimator to respect the 500-line limit; bodies are unchanged. State
-- lives on the caller's State table, so this module owns nothing across frames.

return function(Dependencies)
local Config = Dependencies.Config
-- Injected by the animator: the bus is animator-owned, this module only raises events.
local DispatchEvent = Dependencies.DispatchEvent
-- Injected by the pose pipeline; clip sampling is owned there.
local SampleClip = Dependencies.SampleClip

--=========================================================
-- [1] CONSTANTS
--=========================================================

local JumpClips = Config.Compiled.Jump
local GestureClips = Config.Compiled.Gestures
local MaxGestures = Config.MaxGestures

local JumpStateGrounded = 0
local JumpStateAnticipation = 1
local JumpStateLaunch = 2
local JumpStateAirborne = 3
local JumpStateLanding = 4
local JumpStateRecovery = 5

local Floor = math.floor
local Exp = math.exp

local MotionState = {}

--=========================================================
-- [2] STATE MACHINE
--=========================================================

local function GetJumpSegment(StateId)
    if StateId == JumpStateAnticipation then
        return JumpClips[1]
    elseif StateId == JumpStateLaunch then
        return JumpClips[2]
    elseif StateId == JumpStateAirborne then
        return JumpClips[3]
    elseif StateId == JumpStateLanding then
        return JumpClips[4]
    elseif StateId == JumpStateRecovery then
        return JumpClips[5]
    end
    return nil
end

local function FireBusEvent(EventId)
    DispatchEvent(EventId, 1)
end

local function UpdateJump(State, DeltaTime)
    local Humanoid = State.Humanoid

    if State.JumpState ~= JumpStateGrounded then
        State.JumpTime += DeltaTime
        local Segment = GetJumpSegment(State.JumpState)
        if Segment then
            local Phase = 1.0
            if State.JumpState == JumpStateAirborne then
                -- Airborne holds until the humanoid reports a landing; ramp in over 0.25s.
                Phase = MathLib.Clamp01(State.JumpTime / 0.25)
            elseif Segment.Duration > 0.0001 then
                Phase = MathLib.Clamp01(State.JumpTime / Segment.Duration)
            end

            State.JumpOffset = SampleClip(Segment, Phase, 1.0, State.Overlay, 0, State)

            if State.JumpState ~= JumpStateAirborne
                and Segment.Duration > 0.0001
                and State.JumpTime >= Segment.Duration
            then
                State.JumpTime = 0.0
                State.JumpState += 1
                if State.JumpState > JumpStateRecovery then
                    State.JumpState = JumpStateGrounded
                    State.JumpOffset = 0.0
                    FireBusEvent(Config.EventId.ClipStop)
                end
            end
        else
            State.JumpState = JumpStateGrounded
        end
    end

    -- FloorMaterial poll: catches landings the state machine missed (ledges, low fps).
    if State.JumpState == JumpStateAirborne and Humanoid.FloorMaterial ~= Enum.Material.Air then
        State.JumpState = JumpStateLanding
        State.JumpTime = 0.0
        FireBusEvent(Config.EventId.Landing)
    end

    local TargetWeight = 0.0
    if State.JumpState ~= JumpStateGrounded then
        TargetWeight = 1.0
    end
    local Blend = 1.0 - Exp(-14.0 * DeltaTime)
    State.JumpWeight += (TargetWeight - State.JumpWeight) * Blend
end

local function UpdateGestures(State, DeltaTime)
    local Gestures = State.Gestures
    for Slot = 1, MaxGestures do
        local Gesture = Gestures[Slot]
        if Gesture.Active then
            Gesture.Time += DeltaTime
            local Alpha = Gesture.Time / Gesture.Duration
            if Alpha >= 1.0 then
                Gesture.Active = false
                Gesture.Weight = 0.0
                FireBusEvent(Config.EventId.ClipStop)
            else
                local Weight = 1.0
                if Alpha < 0.15 then
                    Weight = Alpha / 0.15
                elseif Alpha > 0.85 then
                    Weight = (1.0 - Alpha) / 0.15
                end
                Gesture.Weight = Weight
                if Weight > 0.001 then
                    SampleClip(Gesture.Clip, Alpha, Weight, State.Pose, Gesture.EasingId, State)
                end
            end
        end
    end
end

--=========================================================
-- [3] PUBLIC SURFACE
--=========================================================

MotionState.FireBusEvent = FireBusEvent
MotionState.JumpStateGrounded = JumpStateGrounded
MotionState.JumpStateAnticipation = JumpStateAnticipation
MotionState.JumpStateLaunch = JumpStateLaunch
MotionState.JumpStateAirborne = JumpStateAirborne
MotionState.JumpStateLanding = JumpStateLanding
MotionState.JumpStateRecovery = JumpStateRecovery
MotionState.GetJumpSegment = GetJumpSegment
MotionState.UpdateJump = UpdateJump
MotionState.UpdateGestures = UpdateGestures

return MotionState
end
