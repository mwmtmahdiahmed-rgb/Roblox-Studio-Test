--!strict
-- ProceduralAnimation/Shared/AnimationMathIk

return function(MathLib: { [string]: any }, Private: { [string]: any }): ()
local Sqrt = math.sqrt
local Vector3New = Vector3.new

-- [7] FABRIK (Forward And Backward Reaching Inverse Kinematics)
--=========================================================

-- Solves a chain of N bones using FABRIK iteration. ChainPositions is modified in place.
-- ChainPositions[1] is the root (fixed), ChainPositions[N+1] is the end effector.
-- Lengths[i] is the length of bone i (from joint i to joint i+1).
-- Tolerance is the acceptable error in studs. MaxIterations caps the solve.
function MathLib.SolveFabrik(ChainPositions: { any }, Lengths: { number }, TargetPosition: any, Tolerance: number, MaxIterations: number): ()
    local BoneCount = #Lengths
    if BoneCount == 0 then
        return
    end

    local RootX, RootY, RootZ = ChainPositions[1].X, ChainPositions[1].Y, ChainPositions[1].Z
    local TargetX, TargetY, TargetZ = TargetPosition.X, TargetPosition.Y, TargetPosition.Z

    -- Check if target is reachable at all.
    local TotalLength = 0.0
    for Index = 1, BoneCount do
        TotalLength += Lengths[Index]
    end

    local ToTargetX = TargetX - RootX
    local ToTargetY = TargetY - RootY
    local ToTargetZ = TargetZ - RootZ
    local Distance = Sqrt(ToTargetX * ToTargetX + ToTargetY * ToTargetY + ToTargetZ * ToTargetZ)

    -- If the target is beyond reach, stretch the chain straight toward it.
    if Distance > TotalLength then
        local Scale = TotalLength / Distance
        local DirX = ToTargetX * Scale
        local DirY = ToTargetY * Scale
        local DirZ = ToTargetZ * Scale
        local CurrentX, CurrentY, CurrentZ = RootX, RootY, RootZ
        for Index = 1, BoneCount do
            local BoneLength = Lengths[Index]
            local BoneDirX = DirX / TotalLength
            local BoneDirY = DirY / TotalLength
            local BoneDirZ = DirZ / TotalLength
            CurrentX += BoneDirX * BoneLength
            CurrentY += BoneDirY * BoneLength
            CurrentZ += BoneDirZ * BoneLength
            ChainPositions[Index + 1] = Vector3New(CurrentX, CurrentY, CurrentZ)
        end
        return
    end

    -- Iterative FABRIK: forward pass from end effector to root, backward pass from root to end.
    for Iteration = 1, MaxIterations do
        -- Forward pass: place the end effector at the target, then work backward.
        ChainPositions[BoneCount + 1] = Vector3New(TargetX, TargetY, TargetZ)
        for Index = BoneCount, 1, -1 do
            local NextPos = ChainPositions[Index + 1]
            local NextX, NextY, NextZ = NextPos.X, NextPos.Y, NextPos.Z
            local CurrPos = ChainPositions[Index]
            local CurrX, CurrY, CurrZ = CurrPos.X, CurrPos.Y, CurrPos.Z
            local Dx = NextX - CurrX
            local Dy = NextY - CurrY
            local Dz = NextZ - CurrZ
            local Len = Sqrt(Dx * Dx + Dy * Dy + Dz * Dz)
            if Len < 0.0001 then
                Len = 0.0001
            end
            local Ratio = Lengths[Index] / Len
            local NewX = NextX - Dx * Ratio
            local NewY = NextY - Dy * Ratio
            local NewZ = NextZ - Dz * Ratio
            ChainPositions[Index] = Vector3New(NewX, NewY, NewZ)
        end

        -- Backward pass: place the root at its original position, then work forward.
        ChainPositions[1] = Vector3New(RootX, RootY, RootZ)
        for Index = 1, BoneCount do
            local PrevPos = ChainPositions[Index]
            local PrevX, PrevY, PrevZ = PrevPos.X, PrevPos.Y, PrevPos.Z
            local NextPos = ChainPositions[Index + 1]
            local NextX, NextY, NextZ = NextPos.X, NextPos.Y, NextPos.Z
            local Dx = NextX - PrevX
            local Dy = NextY - PrevY
            local Dz = NextZ - PrevZ
            local Len = Sqrt(Dx * Dx + Dy * Dy + Dz * Dz)
            if Len < 0.0001 then
                Len = 0.0001
            end
            local Ratio = Lengths[Index] / Len
            local NewX = PrevX + Dx * Ratio
            local NewY = PrevY + Dy * Ratio
            local NewZ = PrevZ + Dz * Ratio
            ChainPositions[Index + 1] = Vector3New(NewX, NewY, NewZ)
        end

        -- Check convergence.
        local EndPos = ChainPositions[BoneCount + 1]
        local ErrorX = EndPos.X - TargetX
        local ErrorY = EndPos.Y - TargetY
        local ErrorZ = EndPos.Z - TargetZ
        local Error = Sqrt(ErrorX * ErrorX + ErrorY * ErrorY + ErrorZ * ErrorZ)
        if Error < Tolerance then
            break
        end
    end
end
end
