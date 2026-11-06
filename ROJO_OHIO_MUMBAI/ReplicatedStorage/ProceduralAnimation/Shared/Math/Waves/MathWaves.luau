--!strict
-- ProceduralAnimation/Shared/AnimationMathWaves

return function(MathLib: { [string]: any }, Private: { [string]: any }): ()
local Pi = math.pi
local TwoPi = Pi * 2.0
local Sin = math.sin
local Floor = math.floor

--=========================================================
-- [8] WAVES (layered harmonics + noise)
--=========================================================

-- Hardcoded permutation table for value noise (256 entries, shuffled 0-255).
local PermutationTable: { number } = {
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
    140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
    247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
    57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
    74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
    60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
    65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
    200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
    52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
    207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
    119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
    129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
    218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
    81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
    184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
    222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
}

local function Fade(Value: number): number
    return Value * Value * Value * (Value * (Value * 6.0 - 15.0) + 10.0)
end

local function Grad(Hash: number, X: number): number
    local H = Hash % 4
    if H == 0 then
        return X
    elseif H == 1 then
        return -X
    elseif H == 2 then
        return 1.0 - 2.0 * (X - Floor(X))
    else
        return 2.0 * (X - Floor(X)) - 1.0
    end
end

-- 1D value noise, returns a value in approximately [-1, 1].
function MathLib.Noise1D(X: number): number
    local Xi = Floor(X)
    local Xf = X - Xi
    local U = Fade(Xf)
    local Hash0 = PermutationTable[(Xi % 256) + 1]
    local Hash1 = PermutationTable[((Xi + 1) % 256) + 1]
    local Grad0 = Grad(Hash0, Xf)
    local Grad1 = Grad(Hash1, Xf - 1.0)
    return Grad0 + U * (Grad1 - Grad0)
end

-- Evaluates a wave definition at Time. Wave is a table with Harmonics (array of {Amplitude, Frequency, Phase})
-- and optionally NoiseAmplitude, NoiseFrequency.
function MathLib.SampleWave(Wave: any, Time: number): number
    local Value = 0.0
    local Harmonics = Wave.Harmonics
    if Harmonics then
        for Index = 1, #Harmonics do
            local Harmonic = Harmonics[Index]
            Value += Harmonic.Amplitude * Sin(TwoPi * Harmonic.Frequency * Time + Harmonic.Phase)
        end
    end
    if Wave.NoiseAmplitude and Wave.NoiseAmplitude > 0.0 then
        local NoiseFreq = Wave.NoiseFrequency or 1.0
        Value += Wave.NoiseAmplitude * MathLib.Noise1D(Time * NoiseFreq)
    end
    return Value
end

-- Compiles a wave preset into a flat array for fast sampling. Returns a table with
-- Harmonics as a flat array {Amp1, Freq1, Phase1, Amp2, Freq2, Phase2, ...} and noise params.
function MathLib.CompileWave(Wave: any): any
    local Compiled: any = {
        HarmonicCount = 0,
        Harmonics = {},
        NoiseAmplitude = Wave.NoiseAmplitude or 0.0,
        NoiseFrequency = Wave.NoiseFrequency or 1.0,
    }
    local Harmonics = Wave.Harmonics
    if Harmonics then
        local Count = #Harmonics
        Compiled.HarmonicCount = Count
        for Index = 1, Count do
            local H = Harmonics[Index]
            Compiled.Harmonics[Index * 3 - 2] = H.Amplitude
            Compiled.Harmonics[Index * 3 - 1] = H.Frequency
            Compiled.Harmonics[Index * 3] = H.Phase
        end
    end
    return Compiled
end

-- Fast wave sampler using pre-compiled flat array. No allocations.
function MathLib.SampleCompiledWave(Compiled: any, Time: number): number
    local Value = 0.0
    local Harmonics = Compiled.Harmonics
    local Count = Compiled.HarmonicCount
    for Index = 1, Count do
        local Offset = Index * 3 - 2
        local Amp = Harmonics[Offset]
        local Freq = Harmonics[Offset + 1]
        local Phase = Harmonics[Offset + 2]
        Value += Amp * Sin(TwoPi * Freq * Time + Phase)
    end
    if Compiled.NoiseAmplitude > 0.0 then
        Value += Compiled.NoiseAmplitude * MathLib.Noise1D(Time * Compiled.NoiseFrequency)
    end
    return Value
end
end
