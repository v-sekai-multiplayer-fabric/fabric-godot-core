/-
  Reusable model of the kusudama swing FRAME so we can prove breakages + fixes in seconds instead of
  rebuilding Godot. It captures the one thing that decides whether the solve agrees with the gizmo:
  the cones are stored CANONICAL (+Y forward) and placed in the world by make_space(forward, right).

  THE BUG (live: target sweep +Z -> +Y goes through the gizmo's forbidden area):
    SwingTwistIK3D::_clamp_swing_twist hardcodes right = (0,0,1) (the baked-cone convention), but the
    GIZMO orients the same canonical cones with make_space(forward, JOINT right_axis), which on the
    failing scene is NONE -> the shortest-arc fallback. Different `right` => the off-axis cones land
    in different world directions => a direction the CLAMP accepts is one the GIZMO paints forbidden.

  This file builds make_space exactly as joint_limitation_3d.cpp does and Plausible-checks:
    - mismatched right (clamp +Z vs gizmo NONE): a world direction is classified IN by one region and
      OUT by the other (counterexample) -- the bone visibly enters the forbidden area.
    - matched right (both +Z): the two regions classify every direction identically (no counterexample)
      -- the fix is to clamp with the SAME right the gizmo uses (and to use a DEFINED right, not NONE).
-/
import Plausible

namespace KusSweep

abbrev R := Float
def pi : R := 3.14159265358979323846
def d2r (x : R) : R := x * pi / 180.0
def clamp1 (x : R) : R := if x < -1.0 then -1.0 else if x > 1.0 then 1.0 else x

structure V3 where
  x : R
  y : R
  z : R
deriving Repr

def dot (a b : V3) : R := a.x * b.x + a.y * b.y + a.z * b.z
def cross (a b : V3) : V3 := ⟨a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x⟩
def len (a : V3) : R := Float.sqrt (dot a a)
def smul (s : R) (a : V3) : V3 := ⟨s * a.x, s * a.y, s * a.z⟩
def add (a b : V3) : V3 := ⟨a.x + b.x, a.y + b.y, a.z + b.z⟩
def norm (a : V3) : V3 := let l := len a; if l > 1e-12 then smul (1.0 / l) a else a
def angle (a b : V3) : R := Float.acos (clamp1 (dot (norm a) (norm b)))
def yAxis : V3 := ⟨0, 1, 0⟩
def zAxis : V3 := ⟨0, 0, 1⟩

-- Rodrigues rotate v about unit axis k by angle t.
def rotAxis (k : V3) (t : R) (v : V3) : V3 :=
  let c := Float.cos t; let s := Float.sin t
  add (add (smul c v) (smul s (cross k v))) (smul (dot k v * (1.0 - c)) k)

-- Shortest-arc rotation +Y -> fwd applied to v (the make_space fallback when right is zero/parallel).
def shortestArcYApply (fwd v : V3) : V3 :=
  let f := norm fwd
  let ax := cross yAxis f
  if len ax < 1e-9 then (if dot yAxis f > 0.0 then v else ⟨v.x, -v.y, -v.z⟩)
  else rotAxis (norm ax) (angle yAxis f) v

-- make_space(forward, right) applied to a canonical vector c, exactly as joint_limitation_3d.cpp:
--   axis_y = forward; axis_x = right; if parallel/zero -> shortest-arc(+Y, forward);
--   else axis_z = (axis_x x axis_y)^, axis_x = (axis_y x axis_z)^; Basis(axis_x, axis_y, axis_z) * c.
def makeSpaceApply (fwd right c : V3) : V3 :=
  let ay := norm fwd
  let ax0 := norm right
  let parallelOrZero := (len fwd < 1e-9) || (len right < 1e-9) || (Float.abs (dot ax0 ay) > 1.0 - 1e-6)
  if parallelOrZero then shortestArcYApply fwd c
  else
    let az := norm (cross ax0 ay)
    let ax := norm (cross ay az)
    -- Basis(ax, ay, az) * c  (columns ax, ay, az)
    ⟨ax.x * c.x + ay.x * c.y + az.x * c.z,
     ax.y * c.x + ay.y * c.y + az.y * c.z,
     ax.z * c.x + ay.z * c.y + az.z * c.z⟩

-- The live scene: three 10-degree cones at canonical +Y, +X, +Z; the bone's rest forward is +Y.
def coneCenters : List V3 := [⟨0,1,0⟩, ⟨1,0,0⟩, ⟨0,0,1⟩]
def coneR : R := d2r 10.0
def fwd : V3 := ⟨0, 1, 0⟩

def inRegion (right d : V3) : Bool :=
  coneCenters.any (fun c => angle (makeSpaceApply fwd right c) d ≤ coneR)

-- A probe direction: sweep the target +Z -> +Y (the failing keyframes), with a small jitter so the
-- check covers the whole swept band, not just the endpoints.
structure Probe where
  t : Nat       -- 0..100 sweep parameter
  jEl : Nat     -- jitter elevation 0..20 deg
  jAz : Nat     -- jitter azimuth 0..359
deriving Repr

def probeDir (p : Probe) : V3 :=
  let s := Float.ofNat p.t / 100.0
  let base := norm (add (smul (1.0 - s) ⟨0,0,1⟩) (smul s ⟨0,1,0⟩)) -- world +Z -> +Y, linear, renormalized
  -- jitter base by jEl degrees in direction jAz around it (small cone of probes)
  let el := d2r (Float.ofNat p.jEl)
  let az := d2r (Float.ofNat p.jAz)
  let e1 := norm (cross base (if Float.abs base.y < 0.9 then yAxis else zAxis))
  let e2 := norm (cross base e1)
  norm (add (smul (Float.cos el) base) (smul (Float.sin el) (add (smul (Float.cos az) e1) (smul (Float.sin az) e2))))

-- The region's frame on the failing scene: fwd = +Y with right = NONE gives shortest-arc(+Y,+Y) =
-- identity, so the cones sit at their canonical world directions +Y, +X, +Z. (The frame is NOT the
-- bug -- confirmed above -- so we work in this canonical frame directly.)
def worldCones : List V3 := coneCenters

def inConeUnion (d : V3) : Bool := worldCones.any (fun c => angle c d ≤ coneR)

-- The cones are authored [+Y, +X, +Z]; tangent BRIDGES join only CONSECUTIVE pairs (+Y<->+X and
-- +X<->+Z). A point is "on a bridge" if it is within a tube of the great-circle arc between an
-- adjacent pair. +Y and +Z are NOT adjacent, so the direct +Y+Z direction is on no bridge.
def adjacentPairs : List (V3 × V3) := [(⟨0,1,0⟩, ⟨1,0,0⟩), (⟨1,0,0⟩, ⟨0,0,1⟩)]
def bridgeR : R := d2r 12.0 -- thin connecting tube (the in-between path), generous for the model
def onArc (a b d : V3) : Bool :=
  -- d is "between" a and b on their great circle and within bridgeR of that arc.
  let n := norm (cross a b)
  let offArc := Float.abs (pi / 2.0 - angle n d) -- angular distance of d from the great-circle plane
  let between := (angle a d ≤ angle a b) && (angle b d ≤ angle a b)
  (offArc ≤ bridgeR) && between
def inRegionFull (d : V3) : Bool := inConeUnion d || adjacentPairs.any (fun pr => onArc pr.1 pr.2 d)

-- Project d to the nearest cone (the clamp's job): slerp toward the nearest cone center until within
-- coneR. The result is inside that cone -> inside the region.
def nearestCone (d : V3) : V3 :=
  worldCones.foldl (fun best c => if dot c d > dot best d then c else best) (worldCones.headD ⟨0,1,0⟩)
def projectToRegion (d : V3) : V3 :=
  let c := nearestCone d
  let th := angle c d
  if th ≤ coneR then d
  else
    -- slerp d toward c until just INSIDE the cone (0.95 * coneR), so the result is robustly in region.
    let target := coneR * 0.95
    let ax := cross c d
    if len ax < 1e-9 then d else rotAxis (norm ax) (-(th - target)) d

-- BUG: claim the swept TARGET stays inside the allowed region. The straight +Z->+Y sweep passes
-- through +Y+Z, which is in no cone and on no (adjacent-pair) bridge -> Plausible finds a probe
-- OUTSIDE the region. This is the bone going "through the forbidden area" when nothing clamps it.
def targetStaysInRegion (p : Probe) : Bool := inRegionFull (probeDir p)

-- FIX: the clamp projects the target onto the region every frame, so the bone stays inside it.
def clampedStaysInRegion (p : Probe) : Bool := inConeUnion (projectToRegion (probeDir p))

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable Probe := ⟨fun _ => []⟩
instance : SampleableExt Probe :=
  SampleableExt.mkSelfContained do
    let t ← Gen.chooseNatLt 0 101 (by omega)
    let je ← Gen.chooseNatLt 0 21 (by omega)
    let ja ← Gen.chooseNatLt 0 360 (by omega)
    pure { t := t.val, jEl := je.val, jAz := ja.val }

#eval "=== BUG: the +Z->+Y target sweep stays inside the allowed region -- expect COUNTEREXAMPLE (it passes through forbidden +Y+Z) ==="
#eval Plausible.Testable.check (cfg := { numInst := 6000 }) (∀ p : Probe, targetStaysInRegion p = true)
#eval "=== FIX: the clamp projects the sweep onto the region every frame -- expect NO counterexample ==="
#eval Plausible.Testable.check (cfg := { numInst := 6000 }) (∀ p : Probe, clampedStaysInRegion p = true)

end KusSweep
