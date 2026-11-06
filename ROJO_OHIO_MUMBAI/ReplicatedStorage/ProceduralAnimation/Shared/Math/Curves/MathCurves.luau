--!strict
-- ProceduralAnimation/Shared/AnimationMathCurves

return function(MathLib: { [string]: any }, Private: { [string]: any }): ()


local EasingCount = MathLib.EasingCount
local BezierCurves = Private.BezierCurves
local BezierCurveCount = 0
local Sqrt = math.sqrt

-- Number of chord segments used to approximate arc length at compile time. Fixed so every
-- peer produces identical tables from identical authoring data.
local ArcLengthSamples = 64

-- Evaluates a compiled spline at Time. Internal: shared by the arc-length precomputation and
-- the public SampleSpline, so both can never drift apart. Allocation free.
local function EvaluateCompiledSpline(Spline: any, Time: number): number
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

-- Precomputes arc lengths along the (Time, Value) graph of the curve: ArcLengths[i] is the
-- accumulated chord length up to sample i (0-based arc position i / ArcLengthSamples). Used by
-- SampleSplineAtDistance for constant-speed sampling. Runs once at compile time.
local function AttachArcLengths(Spline: any): ()
    local Count = Spline.Count
    if Count < 2 then
        Spline.ArcLengths = { 0.0 }
        Spline.ArcLengthSpan = 0.0
        Spline.TotalLength = 0.0
        return
    end

    local Times = Spline.Times
    local First = Times[1]
    local Span = Times[Count] - First
    local Lengths = table.create(ArcLengthSamples + 1, 0.0)
    local Total = 0.0
    local Dt = Span / ArcLengthSamples
    local PreviousValue = EvaluateCompiledSpline(Spline, First)
    for Index = 1, ArcLengthSamples do
        local Value = EvaluateCompiledSpline(Spline, First + Dt * Index)
        local Dy = Value - PreviousValue
        Total += Sqrt(Dt * Dt + Dy * Dy)
        PreviousValue = Value
        Lengths[Index + 1] = Total
    end

    Spline.ArcLengths = Lengths
    Spline.ArcLengthSpan = Span
    Spline.TotalLength = Total
end

--=========================================================
-- [5] BEZIER (De Casteljau evaluation + derivative)
--=========================================================

local function LerpBezier(From: number, To: number, Alpha: number): number
    return From + (To - From) * Alpha
end

-- Registers a Bezier sampler and returns its easing id (EasingCount + n).
function MathLib.RegisterBezierCurve(Kind: number, P0: number, P1: number, P2: number?, P3: number?): number
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

function MathLib.GetSamplerCount(): number
    return EasingCount + BezierCurveCount
end

function MathLib.BezierQuadratic(P0: number, P1: number, P2: number, Alpha: number): number
    local A0 = LerpBezier(P0, P1, Alpha)
    local A1 = LerpBezier(P1, P2, Alpha)
    return LerpBezier(A0, A1, Alpha)
end

function MathLib.BezierCubic(P0: number, P1: number, P2: number, P3: number, Alpha: number): number
    local A0 = LerpBezier(P0, P1, Alpha)
    local A1 = LerpBezier(P1, P2, Alpha)
    local A2 = LerpBezier(P2, P3, Alpha)
    local B0 = LerpBezier(A0, A1, Alpha)
    local B1 = LerpBezier(A1, A2, Alpha)
    return LerpBezier(B0, B1, Alpha)
end

function MathLib.BezierQuadraticDerivative(P0: number, P1: number, P2: number, Alpha: number): number
    local OneMinus = 1.0 - Alpha
    return 2.0 * OneMinus * (P1 - P0) + 2.0 * Alpha * (P2 - P1)
end

function MathLib.BezierCubicDerivative(P0: number, P1: number, P2: number, P3: number, Alpha: number): number
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
function MathLib.CompileSpline(Kind: string, Times: { number }, Values: { number }): any
    local Count = #Times
    local Spline: any = {
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
        AttachArcLengths(Spline)
        return Spline
    end

    if Count == 1 then
        Spline.A[1] = Values[1]
        Spline.First = Values[1]
        Spline.Last = Values[1]
        AttachArcLengths(Spline)
        return Spline
    end

    Spline.First = Values[1]
    Spline.Last = Values[Count]

    local Slope: { number } = table.create(Count, 0.0)
    for Index = 1, Count - 1 do
        local Span = Spline.Times[Index + 1] - Spline.Times[Index]
        if Span <= 0.0 then
            Span = 0.0001
        end
        Slope[Index] = (Values[Index + 1] - Values[Index]) / Span
    end

    if Kind == "Natural" then
        local Second: { number } = table.create(Count, 0.0)
        Second[1] = 0.0
        Second[Count] = 0.0

        local Unknown = Count - 2
        if Unknown > 0 then
            local Lower: { number } = table.create(Unknown, 0.0)
            local Diagonal: { number } = table.create(Unknown, 0.0)
            local Upper: { number } = table.create(Unknown, 0.0)
            local Right: { number } = table.create(Unknown, 0.0)
            local Solution: { number } = table.create(Unknown, 0.0)

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

        AttachArcLengths(Spline)
        return Spline
    end

    local Tangent: { number } = table.create(Count, 0.0)
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

    AttachArcLengths(Spline)
    return Spline
end

-- Evaluates a compiled spline at Time. Allocation free: no tables are built here.
function MathLib.SampleSpline(Spline: any, Time: number): number
    return EvaluateCompiledSpline(Spline, Time)
end

-- Total (Time, Value) arc length of a compiled spline. Computed at compile time; this is a
-- cheap field read, not an integration.
function MathLib.GetSplineLength(Spline: any): number
    return Spline.TotalLength or 0.0
end

-- Samples a compiled spline at an absolute arc-length offset from the curve start, for
-- constant-speed motion along the curve. Binary-searches the precomputed arc-length table;
-- allocation free. Distance is clamped to [0, Spline.TotalLength]. Returns the spline value at
-- the resolved parameter.
function MathLib.SampleSplineAtDistance(Spline: any, Distance: number): number
    local Total = Spline.TotalLength or 0.0
    if Total <= 0.0 then
        return EvaluateCompiledSpline(Spline, 0.0)
    end
    if Distance <= 0.0 then
        return EvaluateCompiledSpline(Spline, Spline.Times[1])
    end
    if Distance >= Total then
        return EvaluateCompiledSpline(Spline, Spline.Times[Spline.Count])
    end

    local Lengths = Spline.ArcLengths
    local Low, High = 1, ArcLengthSamples + 1
    while Low < High do
        local Mid = math.floor((Low + High) / 2)
        if Lengths[Mid] < Distance then
            Low = Mid + 1
        else
            High = Mid
        end
    end

    local Upper = Low
    local Lower = Upper - 1
    local Span = Lengths[Upper] - Lengths[Lower]
    local Alpha = 0.0
    if Span > 0.0 then
        Alpha = (Distance - Lengths[Lower]) / Span
    end

    local First = Spline.Times[1]
    local Time = First + Spline.ArcLengthSpan * (((Lower - 1) + Alpha) / ArcLengthSamples)
    return EvaluateCompiledSpline(Spline, Time)
end
end
