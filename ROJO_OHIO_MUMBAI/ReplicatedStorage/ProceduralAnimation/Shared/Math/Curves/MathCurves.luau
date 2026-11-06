-- ProceduralAnimation/Shared/AnimationMathCurves

return function(MathLib, Private)


local EasingCount = MathLib.EasingCount
local BezierCurves = Private.BezierCurves
local BezierCurveCount = 0

--=========================================================
-- [5] BEZIER (De Casteljau evaluation + derivative)
--=========================================================

local function LerpBezier(From, To, Alpha)
    return From + (To - From) * Alpha
end

-- Registers a Bezier sampler and returns its easing id (EasingCount + n).
function MathLib.RegisterBezierCurve(Kind, P0, P1, P2, P3)
    if Kind ~= 1 and Kind ~= 2 then
        return 0
    end
    BezierCurveCount += 1
    local Id = EasingCount + BezierCurveCount
    BezierCurves[Id] = {
        Kind = Kind,
        P0 = P0,
        P1 = P1,
        P2 = P2 or 0.0,
        P3 = P3 or 0.0,
    }
    return Id
end

function MathLib.GetSamplerCount()
    return EasingCount + BezierCurveCount
end

function MathLib.BezierQuadratic(P0, P1, P2, Alpha)
    local A0 = LerpBezier(P0, P1, Alpha)
    local A1 = LerpBezier(P1, P2, Alpha)
    return LerpBezier(A0, A1, Alpha)
end

function MathLib.BezierCubic(P0, P1, P2, P3, Alpha)
    local A0 = LerpBezier(P0, P1, Alpha)
    local A1 = LerpBezier(P1, P2, Alpha)
    local A2 = LerpBezier(P2, P3, Alpha)
    local B0 = LerpBezier(A0, A1, Alpha)
    local B1 = LerpBezier(A1, A2, Alpha)
    return LerpBezier(B0, B1, Alpha)
end

function MathLib.BezierQuadraticDerivative(P0, P1, P2, Alpha)
    local OneMinus = 1.0 - Alpha
    return 2.0 * OneMinus * (P1 - P0) + 2.0 * Alpha * (P2 - P1)
end

function MathLib.BezierCubicDerivative(P0, P1, P2, P3, Alpha)
    local OneMinus = 1.0 - Alpha
    local TermA = 3.0 * OneMinus * OneMinus * (P1 - P0)
    local TermB = 6.0 * OneMinus * Alpha * (P2 - P1)
    local TermC = 3.0 * Alpha * Alpha * (P3 - P2)
    return TermA + TermB + TermC
end

--=========================================================
-- [6] SPLINES (Catmull-Rom + natural cubic, coefficients precomputed)
--=========================================================

-- Compiles a keyframe list into per-segment cubic coefficients once, so
-- MathLib.SampleSpline can evaluate the curve without allocating.
-- Kind of "Natural" builds a natural cubic spline (second derivatives solved
-- with a tridiagonal sweep); any other kind builds a Catmull-Rom spline.
function MathLib.CompileSpline(Kind, Times, Values)
    local Count = #Times
    local Spline = {
        Kind = Kind,
        Count = Count,
        Times = table.create(Count),
        A = table.create(Count),
        B = table.create(Count),
        C = table.create(Count),
        D = table.create(Count),
    }

    for Index = 1, Count do
        Spline.Times[Index] = Times[Index]
    end

    if Count == 0 then
        Spline.First = 0.0
        Spline.Last = 0.0
        return Spline
    end

    if Count == 1 then
        Spline.A[1] = Values[1]
        Spline.First = Values[1]
        Spline.Last = Values[1]
        return Spline
    end

    Spline.First = Values[1]
    Spline.Last = Values[Count]

    local Slope = table.create(Count)
    for Index = 1, Count - 1 do
        local Span = Spline.Times[Index + 1] - Spline.Times[Index]
        if Span <= 0.0 then
            Span = 0.0001
        end
        Slope[Index] = (Values[Index + 1] - Values[Index]) / Span
    end

    if Kind == "Natural" then
        local Second = table.create(Count)
        Second[1] = 0.0
        Second[Count] = 0.0

        local Unknown = Count - 2
        if Unknown > 0 then
            local Lower = table.create(Unknown)
            local Diagonal = table.create(Unknown)
            local Upper = table.create(Unknown)
            local Right = table.create(Unknown)
            local Solution = table.create(Unknown)

            for Position = 1, Unknown do
                local Index = Position + 1
                local SpanLower = Spline.Times[Index] - Spline.Times[Index - 1]
                local SpanUpper = Spline.Times[Index + 1] - Spline.Times[Index]
                if SpanLower <= 0.0 then
                    SpanLower = 0.0001
                end
                if SpanUpper <= 0.0 then
                    SpanUpper = 0.0001
                end
                Lower[Position] = SpanLower
                Diagonal[Position] = 2.0 * (SpanLower + SpanUpper)
                Upper[Position] = SpanUpper
                Right[Position] = 6.0 * ((Values[Index + 1] - Values[Index]) / SpanUpper - (Values[Index] - Values[Index - 1]) / SpanLower)
                Solution[Position] = 0.0
            end

            for Position = 2, Unknown do
                local Factor = Lower[Position] / Diagonal[Position - 1]
                Diagonal[Position] -= Factor * Upper[Position - 1]
                Right[Position] -= Factor * Right[Position - 1]
            end

            Solution[Unknown] = Right[Unknown] / Diagonal[Unknown]
            for Position = Unknown - 1, 1, -1 do
                Solution[Position] = (Right[Position] - Upper[Position] * Solution[Position + 1]) / Diagonal[Position]
            end

            for Position = 1, Unknown do
                Second[Position + 1] = Solution[Position]
            end
        end

        for Index = 1, Count - 1 do
            local Span = Spline.Times[Index + 1] - Spline.Times[Index]
            if Span <= 0.0 then
                Span = 0.0001
            end
            local SecondLow = Second[Index]
            local SecondHigh = Second[Index + 1]
            local SpanSquared = Span * Span
            Spline.A[Index] = Values[Index]
            Spline.B[Index] = Slope[Index] * Span - SpanSquared * (2.0 * SecondLow + SecondHigh) / 6.0
            Spline.C[Index] = SecondLow * SpanSquared * 0.5
            Spline.D[Index] = (SecondHigh - SecondLow) * SpanSquared / 6.0
        end

        return Spline
    end

    local Tangent = table.create(Count)
    Tangent[1] = Slope[1]
    Tangent[Count] = Slope[Count - 1]
    for Index = 2, Count - 1 do
        local Span = Spline.Times[Index + 1] - Spline.Times[Index - 1]
        if Span <= 0.0 then
            Span = 0.0001
        end
        Tangent[Index] = (Values[Index + 1] - Values[Index - 1]) / Span
    end

    for Index = 1, Count - 1 do
        local Span = Spline.Times[Index + 1] - Spline.Times[Index]
        if Span <= 0.0 then
            Span = 0.0001
        end
        local StartValue = Values[Index]
        local EndValue = Values[Index + 1]
        local TangentLow = Tangent[Index] * Span
        local TangentHigh = Tangent[Index + 1] * Span
        Spline.A[Index] = StartValue
        Spline.B[Index] = TangentLow
        Spline.C[Index] = 3.0 * (EndValue - StartValue) - 2.0 * TangentLow - TangentHigh
        Spline.D[Index] = 2.0 * (StartValue - EndValue) + TangentLow + TangentHigh
    end

    return Spline
end

-- Evaluates a compiled spline at Time. Allocation free: no tables are built here.
function MathLib.SampleSpline(Spline, Time)
    local Count = Spline.Count
    if Count == 0 then
        return 0.0
    end
    if Count == 1 then
        return Spline.A[1]
    end

    local Times = Spline.Times
    if Time <= Times[1] then
        return Spline.First
    end
    if Time >= Times[Count] then
        return Spline.Last
    end

    local Segment = Count - 1
    for Index = 1, Count - 1 do
        if Time < Times[Index + 1] then
            Segment = Index
            break
        end
    end

    local Span = Times[Segment + 1] - Times[Segment]
    local Alpha = 0.0
    if Span > 0.0 then
        Alpha = (Time - Times[Segment]) / Span
    end

    return Spline.A[Segment] + Alpha * (Spline.B[Segment] + Alpha * (Spline.C[Segment] + Alpha * Spline.D[Segment]))
end
end
