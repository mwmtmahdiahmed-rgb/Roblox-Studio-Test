# Procedural Animation Framework (Roblox-Studio-Test)

A procedural animation framework for **R15 avatars** on Roblox, plus a fully offline
verification harness. All motion writes to `Motor6D.Transform`; the `Humanoid` remains in
charge of physics. Character-specific presets live in configuration; the runtime is generic.

Features: velocity-filtered locomotion (idle/walk/run), jump state machine with squash &
stretch spring, additive gestures, two-bone IK, FABRIK chains, wave-driven secondary motion,
head look-at constraints, per-joint amplitude limits, and networked pose replication via
unreliable remotes with a fixed binary packet layout.

> **Status — verified where verifiable, unverified where it isn't.** Every gate below is
> automated and green on `main`. What has **not** been verified is stated in
> `Documentation/Audit.md` (unverified runtime behaviour) — this project is developed
> without entering Play mode, by policy.

## Repository layout

```
ROJO_OHIO_MUMBAI/               # Source tree mirrored into the place by Rojo
├── ReplicatedStorage/ProceduralAnimation/
│   ├── Client/                 # Bootstrap (auto-init) + runtime (pose pipeline, kinematics)
│   ├── Server/                 # Bootstrap (replication broadcaster)
│   └── Shared/                 # Animation, Config (Data + Compile), Math (Core/Curves/IK/Waves),
│                               # Networking (Constants/Receive), Utilities, Changelog
├── ServerScriptService/        # ProceduralAnimationServer.legacy.luau (harness-named Script)
├── StarterPlayerScripts/       # ProceduralAnimationClient.local.luau
└── ServerStorage/ZeroScript/   # In-Studio memory snapshot for readers without the repo

Tools/verify/                   # Offline gate: Luau compiler, type checker, mocked VM + suites
├── src/                        # Mocked Roblox services (harness, never ships)
├── LuaTests/                   # Behavioural suites (math, config, network, integration, ...)
├── baseline/api.json           # Frozen public API surface
└── *.mjs                       # verify / rojo-check / changelog-check / bench
ProceduralAnimation.project.json
Documentation/                  # Memory, Changelog, GoodPractices, BadPractices, SyntaxReference,
                                # Maintenance, Audit, API
```

## Verification (offline — no Studio, no Play mode)

```bash
cd Tools/verify
npm ci                       # lockfile-pinned; one dependency: @luau-rs/luau
node verify.mjs              # compile 28 modules + static analysis + behavioural suites + API diff
node rojo-check.mjs          # project.json integrity (paths, coverage, harness conventions)
node changelog-check.mjs     # changelog parity: Documentation vs runtime copy
node bench.mjs               # optional micro-benchmarks (same machine only)
```

Expected: **Compilation 28/28 · Analysis 0 errors / 0 warnings · Cases PASS 448 | FAIL 0**.
CI (`.github/workflows/verify.yml`) runs the same three commands on every push/PR to `main`
and `arena/**`.

## Guarantees and frozen invariants

- Packet format frozen: **20 B header / 6 B joint block / 116 B @ 16 joints**
  (`Networking/Constants`, `NetworkReceive.luau`, validated against the network suite).
- Public API baseline frozen (`Tools/verify/baseline/api.json`); additions are reported, not failed.
- Every Luau file is `--!strict`; every script ≤ 500 lines (framework max: 495).
- Functional style: no OOP, classes, metatables or inheritance.

## Documentation

Start with **[Memory.md](Documentation/Memory.md)** (current state, reading order, invariants).
Then: [Changelog.md](Documentation/Changelog.md) ·
[GoodPractices.md](Documentation/GoodPractices.md) ·
[BadPractices.md](Documentation/BadPractices.md) ·
[SyntaxReference.md](Documentation/SyntaxReference.md) ·
[Maintenance.md](Documentation/Maintenance.md) ·
[Audit.md](Documentation/Audit.md) ·
[API.md](Documentation/API.md).

## Known limitations

- R15 only (R6 deferred); no Play-mode validation has been performed — see `Audit.md`.
- One open architectural decision: foot placement currently relies on joint amplitude
  limits; an `AnimationConstraint`-based rig fix is proposed but not applied.
- Studio ↔ GitHub parity is checked by inspection only; `rojo build` has not been run in
  this environment.
