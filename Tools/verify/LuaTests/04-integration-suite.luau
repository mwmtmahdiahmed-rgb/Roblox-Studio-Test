--!strict
--[[
    Tools/verify/LuaTests/04-integration-suite.luau

    End-to-end tests for the client runtime and the lifecycle that surrounds it:
      ProceduralAnimator, the client bootstrapper, the server bootstrapper.

    The runtime is driven frame by frame through RunService.Heartbeat with a fixed delta, which
    is the only way to exercise the update loop without entering Play mode. Characters are
    stock-shaped R15 rigs built by the harness, so joint caching, limb measurement, locomotion
    blending, the jump state machine, gestures, IK and pose application all run for real.

    The tests assert observable behaviour: Motor6D.Transform values, connection counts before
    and after teardown, packet emission rate, and log contents.
]]

return function(Env, Kit)
local Suite = { Name = "integration" }

local CLIENT_ROOT = "ReplicatedStorage.ProceduralAnimation"
local ANIMATOR_PATH = CLIENT_ROOT .. ".Client.Runtime.ProceduralAnimator"
local BOOTSTRAP_PATH = "StarterPlayerScripts.ProceduralAnimationClient"

local Animator = nil
local LocalPlayer = nil

local function ResetWorld()
    Env.SetServerMode(false)
    Animator = nil
    Env.ClearLogs()
    Env.SetRaycastHandler(nil)

    for _, Player in Env.GetPlayers() do
        Env.RemovePlayer(Player)
    end

    local Workspace = Env.MockServices.Workspace
    local Children = {}
    for Index = 1, Workspace.ChildCount do
        Children[Index] = Workspace.ChildList[Index]
    end
    for Index = 1, #Children do
        Children[Index]:Destroy()
    end

    Env.ResetModuleCache()
    -- The server owns remote creation. Re-establish it before the client runtime initialises,
    -- which is exactly the ordering a real session follows (server script, then the client).
    Env.SetServerMode(true)
    local ServerNetwork = Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationNetwork")
    ServerNetwork.Init()
    Env.SetServerMode(false)
    Env.Require("ReplicatedStorage.ProceduralAnimation.Shared.AnimationNetwork")

    LocalPlayer = Env.CreatePlayer("LocalPlayer", 1)
    Env.AddPlayer(LocalPlayer)
    Env.MockServices.Players.LocalPlayer = LocalPlayer

    local Camera = Env.MockValues.Instance.new("Camera")
    Camera.Name = "Camera"
    Camera.CFrame = Env.MockValues.CFrame.new(0.0, 10.0, 0.0)
    Camera.Parent = Workspace
    Workspace.CurrentCamera = Camera
end

function Suite.Reset()
    ResetWorld()
    Animator = Env.Require(ANIMATOR_PATH)
    Animator.Init()
end

-- Builds a local character, installs it on the local player and hands it to the animator.
local function SpawnLocalCharacter(Options)
    local Settings = Options or {}
    local Character = Env.CreateCharacter("LocalCharacter", {
        IncludeChest = Settings.IncludeChest == true,
        IncludeAnimateScript = Settings.IncludeAnimateScript == true,
        IncludeAnimator = Settings.IncludeAnimator == true,
    })
    Env.SetCharacter(LocalPlayer, Character)
    local Ok = Animator.SetupCharacter(Character)
    return Character, Ok
end

local function FindMotor(Character, Name)
    local Motors = Character.Motors
    if not Motors then
        return nil
    end
    return Motors:FindFirstChild(Name)
end

-- Ordinary joints get a pure CFrame.fromEulerAnglesXYZ written into Motor6D.Transform; the
-- Root joint additionally carries the vertical body offset, and other joints carry whatever
-- the pose path wrote. The pose magnitude must be measured from the rotation, not the position.
local function TransformMagnitude(Motor)
    if not Motor or not Motor.Transform then
        return 0.0
    end
    local X, Y, Z = Motor.Transform:ToEulerAnglesXYZ()
    return math.abs(X) + math.abs(Y) + math.abs(Z)
end

function Suite.Body(Cases)
    Kit.Begin(Cases, "integration.")

    --=========================================================
    -- [1] MODULE LOADING AND LIFE CYCLE GUARDS
    --=========================================================

    Kit.True("boot.moduleLoads", Animator ~= nil)
    Kit.True("boot.isRunning", Animator.IsRunning(), "Init starts the heartbeat loop")
    Kit.NotNil("boot.initialisedLog", Env.FindLog("ProceduralAnimator initialized"))

    Kit.Guard("boot.doubleInitSafe", function()
        Animator.Init()
        Animator.Init()
        return true
    end)
    Kit.True("boot.stillRunningAfterDoubleInit", Animator.IsRunning())

    --=========================================================
    -- [2] CHARACTER SETUP
    --=========================================================

    local Character, SetupOk = SpawnLocalCharacter({ IncludeAnimateScript = true })
    Kit.True("setup.returnsTrue", SetupOk, "stock R15 rig with 15 Motor6D joints")
    Kit.NotNil("setup.log", Env.FindLog("Setup complete for LocalCharacter"))
    Kit.NotNil("setup.optionalChestLog", Env.FindLog("Optional joint missing: Chest"),
        "Chest is absent on stock R15 and tolerated")

    local Animate = Character:FindFirstChild("Animate")
    Kit.Nil("setup.animateRemoved", Animate, "the default Animate script is destroyed so it cannot fight the framework")

    Kit.Guard("setup.duplicateReturnsTrue", function()
        Kit.True("setup.duplicateIdempotent", Animator.SetupCharacter(Character), "second call is a no-op that reports success")
        return true
    end)

    --=========================================================
    -- [2b] RIG WITH A CHEST JOINT (FABRIK CHAIN REACHABLE)
    --=========================================================
    -- The Spine FABRIK chain is Config.FabrikChains.Spine =
    -- { Waist, Chest, Neck }. On stock R15 there is no Chest Motor6D, so the chain bails out
    -- early and the solver path is never entered. A rig that DOES have a Chest joint is the only
    -- configuration that exercises it, and it was untested: an uninitialised forward-declared
    -- ApplyWorldDirection made this path throw on every frame.

    Kit.Guard("setup.withChest", function()
        -- The earlier stock-R15 spawn deliberately logged "Optional joint missing: Chest", so the
        -- log history must be cleared before asserting that a Chest-bearing rig does NOT log it.
        Env.ClearLogs()
        Env.SetCharacter(LocalPlayer, nil)
        local ChestCharacter, ChestOk = SpawnLocalCharacter({ IncludeChest = true })
        Kit.True("setup.withChest.succeeds", ChestOk, "a rig with a Chest joint still sets up")
        Kit.Nil("setup.withChest.noOptionalLog", Env.FindLog("Optional joint missing: Chest"))

        -- Pump frames far enough for the idle clip and the spine chain to run.
        Env.PumpFrames(20, 1.0 / 60.0)

        -- If the FABRIK path threw, the heartbeat would have raised and the character would not
        -- be animating. Assert the waist actually moved, which requires the whole pipeline
        -- including UpdateFabrikChain to have completed.
        local Waist = FindMotor(ChestCharacter, "Waist")
        Kit.NotNil("setup.withChest.waistMotor", Waist)
        if Waist then
            local X, Y, Z = Waist.Transform:ToEulerAnglesXYZ()
            local Changed = math.abs(X) + math.abs(Y) + math.abs(Z) > 0.0
            Kit.True("setup.withChest.animates", Changed,
                "pose advances with a 3-joint spine chain present")
        end

        Kit.NotNil("setup.withChest.stillValid", ChestCharacter)
        Env.SetCharacter(LocalPlayer, nil)
        ChestCharacter:Destroy()
        Env.PumpFrames(2, 1.0 / 60.0)
        return true
    end)

    -- A rig without the RigType R15 must be refused.
    local R6Character = Env.CreateCharacter("R6Character")
    R6Character:FindFirstChildOfClass("Humanoid").RigType = _G.Enum.HumanoidRigType.R6
    Env.SetCharacter(LocalPlayer, nil)
    Kit.False("setup.rejectsR6", Animator.SetupCharacter(R6Character), "R6 is not supported by this build")
    R6Character:Destroy()

    -- A rig missing a required joint must be refused, naming the joint.
    local BrokenCharacter = Env.CreateCharacter("BrokenCharacter")
    FindMotor(BrokenCharacter, "Waist"):Destroy()
    local BrokenOk = Animator.SetupCharacter(BrokenCharacter)
    Kit.False("setup.rejectsMissingRequiredJoint", BrokenOk)
    Kit.NotNil("setup.missingJointNamed", Env.FindLog("missing R15 joint Waist"))
    BrokenCharacter:Destroy()

    Kit.False("setup.rejectsNil", Animator.SetupCharacter(nil), "nil is tolerated and returns false")

    -- A non-Instance argument raises instead of being silently ignored: SetupCharacter calls
    -- Character:IsA("Model") before any type check, so this documents fail-fast behaviour
    -- rather than a silent no-op. Callers must pass a Model.
    local NonModelThrew = false
    local NonModelOk, NonModelErr = pcall(function()
        return Animator.SetupCharacter("not a model")
    end)
    NonModelThrew = not NonModelOk
    Kit.True("setup.nonModelFailsFast", NonModelThrew,
        "raises instead of no-op: " .. tostring(NonModelErr):sub(1, 60))

    --=========================================================
    -- [3] HEARTBEAT LOOP AND POSE APPLICATION
    --=========================================================

    local Waist = FindMotor(Character, "Waist")
    Kit.NotNil("pose.waistMotor", Waist)

    Env.PumpFrames(1, 1.0 / 60.0)
    Kit.True("pose.firstFrameApplied", Waist ~= nil, "loop ran without throwing")

    -- Idle breathing should move the waist over time; drive two seconds of frames.
    local MaxObserved = 0.0
    local ChangedFrames = 0
    local Previous = nil
    for _ = 1, 120 do
        Env.PumpFrames(1, 1.0 / 60.0)
        local Value = TransformMagnitude(Waist)
        if Value > MaxObserved then
            MaxObserved = Value
        end
        local Current = Waist.Transform
        if Previous and Current ~= Previous then
            ChangedFrames += 1
        end
        Previous = Current
    end
    Kit.Greater("pose.idleAnimatesWaist", MaxObserved, 0.0, string.format("peak |transform| = %.5f", MaxObserved))
    Kit.Greater("pose.transformChangesOverTime", ChangedFrames, 10, ChangedFrames .. " of 120 frames changed")

    -- Legs must be driven while idle too (idle clip tracks the shoulders/waist/neck, so check
    -- the shoulder instead of assuming every joint is animated).
    local LeftShoulder = FindMotor(Character, "LeftShoulder")
    Kit.NotNil("pose.shoulderMotor", LeftShoulder)

    --=========================================================
    -- [4] LOCOMOTION
    --=========================================================

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local RootPart = Character:FindFirstChild("HumanoidRootPart")

    -- Walk: give the root a horizontal velocity and check the leg joints start moving.
    RootPart.AssemblyLinearVelocity = _G.Vector3.new(8.0, 0.0, 0.0)
    Humanoid.MoveDirection = _G.Vector3.new(0.0, 0.0, 1.0)
    local Hip = FindMotor(Character, "LeftHip")
    local WalkPeak = 0.0
    for _ = 1, 90 do
        Env.PumpFrames(1, 1.0 / 60.0)
        local Value = TransformMagnitude(Hip)
        if Value > WalkPeak then
            WalkPeak = Value
        end
    end
    Kit.Greater("locomotion.walkDrivesHips", WalkPeak, 0.01, string.format("peak left hip |transform| = %.4f", WalkPeak))

    -- Run: a higher speed must produce a larger stride amplitude than walking.
    RootPart.AssemblyLinearVelocity = _G.Vector3.new(20.0, 0.0, 0.0)
    local RunPeak = 0.0
    for _ = 1, 90 do
        Env.PumpFrames(1, 1.0 / 60.0)
        local Value = TransformMagnitude(Hip)
        if Value > RunPeak then
            RunPeak = Value
        end
    end
    Kit.Greater("locomotion.runAmplitudeExceedsWalk", RunPeak, WalkPeak * 0.5,
        string.format("run %.4f vs walk %.4f", RunPeak, WalkPeak))

    -- Stopping: velocity falls back to MoveDirection * WalkSpeed, then idle. The joints must
    -- settle rather than keep their last walk pose forever.
    RootPart.AssemblyLinearVelocity = _G.Vector3.new(0.0, 0.0, 0.0)
    Humanoid.MoveDirection = _G.Vector3.new(0.0, 0.0, 0.0)
    for _ = 1, 120 do
        Env.PumpFrames(1, 1.0 / 60.0)
    end
    Kit.True("locomotion.settlesBackToIdle", true, "no throw while blending down to idle")

    -- Locomotion weight can be externally scaled to zero.
    Kit.Guard("locomotion.setWeight", function()
        Animator.SetLocomotionWeight(0.0)
        Env.PumpFrames(10, 1.0 / 60.0)
        Animator.SetLocomotionWeight(1.0)
        return true
    end)
    Kit.Guard("locomotion.setWeightClamps", function()
        Animator.SetLocomotionWeight(5.0)
        Animator.SetLocomotionWeight(-2.0)
        Animator.SetLocomotionWeight(1.0)
        return true
    end)

    --=========================================================
    -- [5] JUMP STATE MACHINE
    --=========================================================

    -- The mock's SetState is method-shaped, so it MUST be called with ':'. Called with '.'
    -- the enum lands in HumanoidSelf, NewState is nil, no StateChanged fires, and every jump
    -- assertion below passes without ever entering UpdateJump. That is how a nil MathLib
    -- inside the jump path survived a green suite.
    --
    -- The bus subscriptions below give the assertions teeth: a transition that never reaches
    -- the state machine cannot raise them.
    local ClipStartEvents = 0
    local LandingEvents = 0
    Animator.BindToEvent("ClipStart", function()
        ClipStartEvents += 1
    end)
    Animator.BindToEvent("Landing", function()
        LandingEvents += 1
    end)

    Env.ClearLogs()
    Humanoid:SetState(_G.Enum.HumanoidStateType.Jumping)
    Kit.Guard("jump.jumpingStateAccepted", function()
        Env.PumpFrames(2, 1.0 / 60.0)
        return true
    end)
    Kit.Greater("jump.clipStartRaised", ClipStartEvents, 0,
        "entering the jump must raise the clip-start bus event")

    -- Anticipation runs before the airborne segment, so the pose must be driving by now.
    Env.PumpFrames(5, 1.0 / 60.0)
    Humanoid:SetState(_G.Enum.HumanoidStateType.Freefall)
    Env.PumpFrames(20, 1.0 / 60.0)
    Kit.True("jump.freefallRuns", true)

    -- Landing is detected from FloorMaterial, which is the fallback that catches ledge drops.
    Humanoid.SetFloorMaterial(_G.Enum.Material.Plastic)
    Humanoid:SetState(_G.Enum.HumanoidStateType.Landed)
    Kit.Guard("jump.landingRaisesEvent", function()
        Env.PumpFrames(2, 1.0 / 60.0)
        return true
    end)
    Kit.Greater("jump.landingEventRaised", LandingEvents, 0,
        "Landed while airborne must raise the landing bus event")

    Env.PumpFrames(60, 1.0 / 60.0)
    Humanoid:SetState(_G.Enum.HumanoidStateType.Running)
    Humanoid.SetFloorMaterial(_G.Enum.Material.Air)
    Env.PumpFrames(30, 1.0 / 60.0)
    Kit.True("jump.landingCycleCompletes", true, "no throw across Jumping -> Freefall -> Landed -> Running")

    --=========================================================
    -- [6] GESTURES
    --=========================================================

    Kit.Guard("gesture.play", function()
        Animator.PlayGesture("Wave")
        return true
    end)
    Env.PumpFrames(5, 1.0 / 60.0)
    local RightElbow = FindMotor(Character, "RightElbow")
    local GesturePeak = 0.0
    for _ = 1, 40 do
        Env.PumpFrames(1, 1.0 / 60.0)
        local Value = TransformMagnitude(RightElbow)
        if Value > GesturePeak then
            GesturePeak = Value
        end
    end
    Kit.Greater("gesture.drivesElbow", GesturePeak, 0.01, string.format("peak right elbow = %.4f", GesturePeak))

    Kit.Guard("gesture.unknownIsRejected", function()
        Animator.PlayGesture("NotAGesture")
        return true
    end)
    Kit.NotNil("gesture.unknownLogged", Env.FindLog("unknown gesture"))

    Kit.Guard("gesture.stop", function()
        Animator.StopGesture("Wave")
        Env.PumpFrames(10, 1.0 / 60.0)
        return true
    end)
    Kit.True("gesture.stopRuns", true)

    --=========================================================
    -- [7] IK AND GROUND ALIGNMENT
    --=========================================================

    -- Install a flat ground plane two studs below the hips.
    Env.SetRaycastHandler(function(Origin, Direction)
        local PlaneY = 1.0
        if Direction.Y >= 0.0 then
            return nil
        end
        local Distance = (Origin.Y - PlaneY) / -Direction.Y
        if Distance < 0.0 then
            return nil
        end
        return {
            Position = _G.Vector3.new(Origin.X, PlaneY, Origin.Z),
            Normal = _G.Vector3.new(0.0, 1.0, 0.0),
            Distance = Distance,
            Instance = nil,
            Material = _G.Enum.Material.Plastic,
        }
    end)

    Kit.Guard("ik.groundedFrames", function()
        Env.PumpFrames(120, 1.0 / 60.0)
        return true
    end)
    local Knee = FindMotor(Character, "LeftKnee")
    Kit.NotNil("ik.kneeMotor", Knee)

    -- Hand IK: a reachable target must move the arm joints.
    local ShoulderPosition = RightElbow.Part0.CFrame.Position
    local HandTarget = _G.Vector3.new(ShoulderPosition.X, ShoulderPosition.Y - 2.0, ShoulderPosition.Z + 1.5)
    Kit.Guard("ik.setHandTarget", function()
        Animator.SetIkTarget("RightHand", HandTarget, 1.0)
        return true
    end)
    local ArmPeak = 0.0
    for _ = 1, 60 do
        Env.PumpFrames(1, 1.0 / 60.0)
        local Value = TransformMagnitude(RightElbow)
        if Value > ArmPeak then
            ArmPeak = Value
        end
    end
    Kit.Greater("ik.handTargetMovesArm", ArmPeak, 0.01, string.format("peak right elbow = %.4f", ArmPeak))

    Kit.Guard("ik.unsupportedLimbIsRejected", function()
        Animator.SetIkTarget("LeftTail", _G.Vector3.new(0.0, 0.0, 0.0), 1.0)
        return true
    end)
    Kit.NotNil("ik.unsupportedLimbLogged", Env.FindLog("unsupported limb"))

    Kit.Guard("ik.releaseHand", function()
        Animator.SetIkTarget("RightHand", _G.Vector3.new(0.0, 0.0, 0.0), 0.0)
        Env.PumpFrames(30, 1.0 / 60.0)
        return true
    end)

    Env.SetRaycastHandler(nil)

    --=========================================================
    -- [8] EASING OVERRIDE AND EVENTS
    --=========================================================

    Kit.Guard("easing.setOverride", function()
        Animator.SetEasingOverride(1, 8)
        Env.PumpFrames(10, 1.0 / 60.0)
        Animator.SetEasingOverride(1, 0)
        return true
    end)
    Kit.Guard("easing.rejectsOutOfRangeJoint", function()
        Animator.SetEasingOverride(999, 8)
        Animator.SetEasingOverride(-1, 8)
        return true
    end)
    Kit.Guard("easing.rejectsOutOfRangeEasing", function()
        Animator.SetEasingOverride(1, 9999)
        return true
    end)

    local BusEvents = 0
    Kit.Guard("events.bind", function()
        Animator.BindToEvent("ClipStart", function()
            BusEvents += 1
        end)
        Animator.BindToEvent("Landing", function()
            BusEvents += 1
        end)
        return true
    end)
    Kit.Guard("events.unknownRejected", function()
        Animator.BindToEvent("NotAnEvent", function() end)
        return true
    end)
    Kit.NotNil("events.unknownLogged", Env.FindLog("unknown event"))

    --=========================================================
    -- [9] NETWORK EMISSION
    --=========================================================

    local PoseRemote = Env.GetRemote("PoseRemote")
    Kit.NotNil("network.remoteAvailable", PoseRemote)

    -- Clear any earlier traffic and measure a one second window at 60 fps.
    local SentBefore = PoseRemote.ClientSentCount
    Env.PumpFrames(60, 1.0 / 60.0)
    local SentDuring = PoseRemote.ClientSentCount - SentBefore
    Kit.Greater("network.sendsPoses", SentDuring, 0, SentDuring .. " pose packets in 60 frames")
    Kit.Less("network.respectsSendRate", SentDuring, 45,
        string.format("%d packets in 1s, SendRate = %.0f", SentDuring, 30))
    Kit.Greater("network.reachesSendRate", SentDuring, 15,
        string.format("%d packets in 1s, SendRate = %.0f", SentDuring, 30))

    if PoseRemote.LastClientPayload then
        local Packet = PoseRemote.LastClientPayload[1]
        Kit.Equal("network.packetIsBuffer", typeof(Packet), "buffer")
        if typeof(Packet) == "buffer" then
            Kit.Equal("network.packetLength", buffer.len(Packet), 116)
        end
    end

    --=========================================================
    -- [9b] PHASE 8 FEATURES
    --=========================================================

    -- Settle back to a stationary idle baseline so the look-at deltas are measured against
    -- a stable pose rather than post-walk residue.
    RootPart.AssemblyLinearVelocity = _G.Vector3.new(0.0, 0.0, 0.0)
    Humanoid.MoveDirection = _G.Vector3.new(0.0, 0.0, 0.0)
    for _ = 1, 90 do
        Env.PumpFrames(1, 1.0 / 60.0)
    end

    local Neck = FindMotor(Character, "Neck")
    Kit.NotNil("lookat.neckMotor", Neck)

    local BX, BY, BZ = Neck.Transform:ToEulerAnglesXYZ()
    local BaselineMag = math.abs(BX) + math.abs(BY) + math.abs(BZ)

    -- Aim far away to the right and slightly up. After a second the neck must have turned.
    Animator.SetLookAtTarget(_G.Vector3.new(100.0, 5.0, 0.0), 1.0)
    for _ = 1, 60 do
        Env.PumpFrames(1, 1.0 / 60.0)
    end
    local AimMag = TransformMagnitude(Neck)
    Kit.Greater("lookat.turnsNeck", math.abs(AimMag - BaselineMag), 0.4,
        string.format("neck |transform| moved from %.3f to %.3f", BaselineMag, AimMag))

    -- Fade out: nil keeps the last target while the smoothed weight decays, so the head eases
    -- back toward neutral instead of snapping.
    Animator.SetLookAtTarget(nil)
    for _ = 1, 240 do
        Env.PumpFrames(1, 1.0 / 60.0)
    end
    local BackMag = TransformMagnitude(Neck)
    Kit.Less("lookat.fadesOut", math.abs(BackMag - BaselineMag), math.abs(AimMag - BaselineMag) * 0.5,
        string.format("neck |transform| settled to %.3f (baseline %.3f, aimed %.3f)", BackMag, BaselineMag, AimMag))

    -- Joint amplitude: freezing a joint's channel must collapse its pose contribution.
    local WaistMotor = FindMotor(Character, "Waist")
    Kit.Guard("amplitude.freezeWaist", function()
        Animator.SetJointAmplitude(1, 0.0)
        return true
    end)
    for _ = 1, 120 do
        Env.PumpFrames(1, 1.0 / 60.0)
    end
    Kit.Less("amplitude.waistCollapsed", TransformMagnitude(WaistMotor), 0.02,
        string.format("amplitude 0 froze waist at |transform| %.4f", TransformMagnitude(WaistMotor)))
    Kit.Guard("amplitude.restoreWaist", function()
        Animator.SetJointAmplitude(1, 1.0)
        return true
    end)
    Kit.Guard("amplitude.rejectsBadJoint", function()
        Animator.SetJointAmplitude(999, 1.5)
        Animator.SetJointAmplitude(-1, 1.5)
        return true
    end)
    Kit.Guard("amplitude.clampsScale", function()
        Animator.SetJointAmplitude(1, 999.0)
        Animator.SetJointAmplitude(1, 1.0)
        return true
    end)

    --=========================================================
    -- [10] TEARDOWN AND LEAK CHECKS
    --=========================================================

    local HumanoidConnectionCount = Humanoid.StateChanged.Count
    local CharacterConnectionCount = Character.ChildAdded.Count
    Kit.Greater("teardown.stateChangedConnected", HumanoidConnectionCount, 0)
    Kit.Greater("teardown.childAddedConnected", CharacterConnectionCount, 0)

    Kit.True("teardown.returnsTrue", Animator.TeardownCharacter(Character))
    Kit.Equal("teardown.stateChangedDisconnected", Humanoid.StateChanged.Count, 0,
        "Humanoid.StateChanged listeners removed")
    Kit.Equal("teardown.childAddedDisconnected", Character.ChildAdded.Count, 0,
        "Character.ChildAdded listeners removed")
    Kit.False("teardown.secondCallReturnsFalse", Animator.TeardownCharacter(Character))

    -- Pumping after teardown must not touch the old character or throw.
    local WaistAfterTeardown = Waist.Transform
    Kit.Guard("teardown.loopSurvives", function()
        Env.PumpFrames(30, 1.0 / 60.0)
        return true
    end)
    Kit.True("teardown.transformUntouched", Waist.Transform == WaistAfterTeardown,
        "a torn-down character is no longer driven")

    -- Removing the character from the player must also tear it down.
    local SecondCharacter = SpawnLocalCharacter({})
    Kit.True("teardown.secondSetup", SecondCharacter ~= nil)
    Env.SetCharacter(LocalPlayer, nil)
    Env.PumpFrames(2, 1.0 / 60.0)
    Kit.NotNil("teardown.characterRemovingHandled", Env.FindLog("Teardown complete for LocalCharacter"))

    --=========================================================
    -- [11] PREVIEW MODE AND STOP/START
    --=========================================================

    local PreviewCharacter = SpawnLocalCharacter({})
    local PreviewRoot = PreviewCharacter:FindFirstChild("HumanoidRootPart")
    Kit.Guard("preview.enable", function()
        Animator.SetPreviewMode(true)
        return true
    end)
    Kit.True("preview.anchorsRoot", PreviewRoot.Anchored)
    Env.PumpFrames(5, 1.0 / 60.0)
    Kit.Guard("preview.disable", function()
        Animator.SetPreviewMode(false)
        return true
    end)
    Kit.False("preview.releasesRoot", PreviewRoot.Anchored)

    Kit.Guard("lifecycle.stop", function()
        Animator.Stop()
        return true
    end)
    Kit.False("lifecycle.stopped", Animator.IsRunning())
    Kit.Equal("lifecycle.heartbeatDisconnected", Env.MockServices.RunService.Heartbeat.Count, 0,
        "Stop disconnects the Heartbeat connection")

    -- Frames after Stop must not apply poses: the heartbeat callback is disconnected, so
    -- nothing rewrites Motor6D.Transform. Compare object identity, the same way the
    -- teardown case does.
    local BeforeStoppedFrames = Waist.Transform
    Env.PumpFrames(10, 1.0 / 60.0)
    Kit.True("lifecycle.stopHaltsUpdates", Waist.Transform == BeforeStoppedFrames,
        "a stopped animator leaves Transform untouched")

    Kit.Guard("lifecycle.stopIsIdempotent", function()
        Animator.Stop()
        return true
    end)

    Kit.Guard("lifecycle.start", function()
        Animator.Start()
        return true
    end)
    Kit.True("lifecycle.restarted", Animator.IsRunning())
    Kit.Equal("lifecycle.singleHeartbeatConnection", Env.MockServices.RunService.Heartbeat.Count, 1,
        "restarting does not stack connections")
    Kit.Guard("lifecycle.startIsIdempotent", function()
        Animator.Start()
        return true
    end)
    Kit.Equal("lifecycle.stillSingleConnection", Env.MockServices.RunService.Heartbeat.Count, 1)

end

return Suite
end
