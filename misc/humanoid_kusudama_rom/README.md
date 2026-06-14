# Humanoid Kusudama ROM — generator pipeline

Source of truth for the **generated** files checked into the engine:

- `scene/resources/3d/humanoid_kusudama_rom_data.h` — per-bone swing-cone fans + twist for
  every `SkeletonProfileHumanoid` slot, interpolated over the ANNY phenotype at runtime.
- `tests/scene/humanoid_kusudama_rom_gold.h` — per-joint IK-target gold table consumed by
  `tests/scene/test_joint_limitation_kusudama_3d.cpp`.

Both are committed (the engine and CI must not need this toolchain to build); regenerate
them only when the ROM model changes.

## Anatomy of a joint constraint

Each clinical joint's range of motion is modelled as a **spherical ellipse** on the unit
sphere — flexion/extension (major axis) × lateral/abduction (minor axis), with per-side
offsets — and fitted by the **minimal tapered Kusudama cone fan** (caps + tangent bands =
the geodesic neighbourhood of the major-axis polyline). Round joints collapse to one
covering cone; hinges become tapered fans offset toward flexion. The 11 arm/leg/foot/spine
joints instead use real per-subject biomechanics fans from AddBiomechanics.

`N` (cone count) is chosen to minimise a coverage-weighted cost `2·miss + over` (for a
*limit*, falsely rejecting a valid pose is worse than mildly over-allowing). The cone radius
floor is `MIN_CONE_RADIUS = 5.5°` (~1.6× the solver's `SOFT_BAND`).

## Pipeline

```
lean/JointRom.lean ──(Lean+Plausible, parallel)──> lean/shard{0..3}.out
        │                                                  │
        │  emit{0..3}.lean = 11 bones each                 │ FAN| and GOLD| lines
        ▼                                                  ▼
   assemble_joints.py ──> humanoid_joint_fans.py           ──> tests/scene/humanoid_kusudama_rom_gold.h
        │  (BONE_FANS: per-bone fan cones)
        ▼
   gen_humanoid_rom_header.py  (+ rom_limits.jsonl for the 11 data-driven joints)
        ▼
   scene/resources/3d/humanoid_kusudama_rom_data.h
```

### 1. Fit + verify (Lean)

```sh
cd lean
lake build JointRom                                   # builds the library (fast)
for k in 0 1 2 3; do lake env lean emit$k.lean > shard$k.out 2>&1 & done
lake env lean verify.lean > verify.out 2>&1 &         # Plausible construction soundness
wait
```

`emit{k}.lean` fits 11 bones each and prints `FAN|<bone>|...` / `GOLD|<bone>|...` lines.
`verify.lean` runs the Plausible properties (fan covers the interior / never bulges out).

### 2. Assemble

```sh
python assemble_joints.py            # reads lean/shard?.out
# -> writes humanoid_joint_fans.py  and  ../../tests/scene/humanoid_kusudama_rom_gold.h
```

### 3. Bake the data header

```sh
python gen_humanoid_rom_header.py [rom_limits.jsonl] [out.h]
# default out: ../../scene/resources/3d/humanoid_kusudama_rom_data.h
```

`rom_limits.jsonl` is the AddBiomechanics per-subject NORMAL-range extract (external, not
committed — large). It supplies the 11 data-driven joints; the 44 clinical joints come from
`humanoid_joint_fans.py`. If you only changed clinical fans, the committed data header is
already current and this step is optional.

## Requirements

- Lean 4 (toolchain pinned in `lean/lean-toolchain`) + `lake`; `plausible` is fetched per
  `lean/lakefile.toml`.
- Python 3 with `numpy`.
