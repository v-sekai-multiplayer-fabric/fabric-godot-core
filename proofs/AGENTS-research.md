# AGENTS.md — multiplayer-fabric-predictive-bvh-research

Guidance for AI coding agents working in this repo.

## What this is

Aspirational / research-tier Lean proofs split out of
[multiplayer-fabric-predictive-bvh](https://github.com/V-Sekai-fire/multiplayer-fabric-predictive-bvh).
None of these modules are in the production codegen import closure. The
production repo's `bvh-codegen` exe writes `predictive_bvh.h` without
touching anything here.

The modules cover query soundness on the abstract BVH, zone migration
protocol, and ReBAC authorisation. They are currently broken under Lean
4.26 and are tracked for incremental repair.

## Build

```sh
lake update
lake build
```

`lake build` is expected to fail. Repair work targets one module at a
time; use `lake build PredictiveBVHResearch.<Module>` to iterate.

## Lake dependencies

- `optimal-partition` — the upstream production repo. Provides
  `PredictiveBVH.Primitives.Types`, `PredictiveBVH.Formulas.*`,
  `PredictiveBVH.Spatial.HilbertBroadphase`,
  `PredictiveBVH.Relativistic.NoGod`, etc. These are imported under
  their original `PredictiveBVH.*` paths.

## Conventions

- Module path renamed to `PredictiveBVHResearch.*`; internal Lean
  `namespace PredictiveBVH …` declarations are unchanged.
- Cross-references between moved files use `PredictiveBVHResearch.*`
  imports.
- Imports of clean upstream modules (`PredictiveBVH.Primitives.Types`
  etc.) are unchanged and resolve via the Lake dep on `optimal-partition`.
- Commit message style: sentence case, no `type(scope):` prefix.
