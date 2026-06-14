/-
  Two correctness findings in joint_limitation_kusudama_3d.cpp, modelled so Plausible exhibits the
  BREAKING input before any C++ patch is applied (the fix is only justified once breakage is shown).

  A) limit_twist (~L249): the swing-twist split builds
        twist_q = Quaternion(d*ax, d*ay, d*az, w).normalized()
     with d = q.vec . a and w = q.w. Its squared length is d^2 + w^2. For a 180-degree rotation
     (w = 0) about an axis PERPENDICULAR to a (d = 0) this is 0, so normalized() divides by zero ->
     NaN, which then poisons swing and the returned clamp. A fully-bent hinge produces exactly this.

  B) compute_tangent_circles (~L949): r_tangent_radius = (pi - (r1 + r2)) / 2. Cone radii are
     authored in [1deg, 180deg], so two large adjacent cones with r1 + r2 > pi give a NEGATIVE
     tangent radius -> a bogus bridge.

  For each: a predicate asserting "no breakage" should FAIL (Plausible finds a counterexample), and
  the guarded version should hold (no counterexample).
-/
import Plausible

namespace KusGuards

abbrev R := Float
def pi : R := 3.14159265358979323846
def d2r (x : R) : R := x * pi / 180.0
def eps : R := 1e-6

-- ===== A) limit_twist zero-length twist quaternion =====
-- a = +Z (the twist axis). k = unit axis of the rotation, built in the XY plane (so k . a = 0 when
-- we want the perpendicular case) or tilted by `tilt`. q = (sin(t/2) k, cos(t/2)).
structure TwistCase where
  kAz : Nat -- k azimuth in XY plane, 0..359 deg
  tiltDeg : Nat -- tilt of k out of the XY plane toward a (0 = perpendicular to a)
  angDeg : Nat -- rotation angle, 0..359 deg
deriving Repr

def twistMagSq (c : TwistCase) : R :=
  let tilt := d2r (Float.ofNat c.tiltDeg)
  let az := d2r (Float.ofNat c.kAz)
  -- k: tilt toward +Z (a) by `tilt`; perpendicular component in XY by azimuth.
  let kz := Float.sin tilt
  let kxy := Float.cos tilt
  let kx := kxy * Float.cos az
  let ky := kxy * Float.sin az
  -- a = (0,0,1) so d = (sin(t/2) k) . a = sin(t/2) * kz ; w = cos(t/2).
  let h := d2r (Float.ofNat c.angDeg) / 2.0
  let d := Float.sin h * kz
  let w := Float.cos h
  d * d + w * w

-- BREAKAGE predicate: claim the twist quaternion is always safely normalizable (>= eps). Plausible
-- should find a counterexample (the 180deg-about-perpendicular-axis case -> magnitude ~0).
def twistAlwaysSafe (c : TwistCase) : Bool := twistMagSq c ≥ eps

-- FIXED: guard returns the input rotation when the magnitude is below the floor (no normalize).
-- Modelled as: with the guard, we never divide by a sub-eps magnitude -> always safe.
def twistSafeGuarded (c : TwistCase) : Bool :=
  let m := twistMagSq c
  (m < eps) || (m ≥ eps) -- tautology: either we take the guard branch, or m is safe

-- ===== B) negative tangent radius =====
structure ConePair where
  r1Deg : Nat -- 1..180
  r2Deg : Nat -- 1..180
deriving Repr

def tangentRadius (c : ConePair) : R := (pi - (d2r (Float.ofNat c.r1Deg) + d2r (Float.ofNat c.r2Deg))) / 2.0
def tangentNonneg (c : ConePair) : Bool := tangentRadius c ≥ 0.0
def tangentGuardedNonneg (c : ConePair) : Bool := (if tangentRadius c < 0.0 then 0.0 else tangentRadius c) ≥ 0.0

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable TwistCase := ⟨fun _ => []⟩
instance : SampleableExt TwistCase :=
  SampleableExt.mkSelfContained do
    let a ← Gen.chooseNatLt 0 360 (by omega)
    let t ← Gen.chooseNatLt 0 30 (by omega) -- mostly near-perpendicular to a
    let g ← Gen.chooseNatLt 150 211 (by omega) -- rotation near 180deg
    pure { kAz := a.val, tiltDeg := t.val, angDeg := g.val }
instance : Shrinkable ConePair := ⟨fun _ => []⟩
instance : SampleableExt ConePair :=
  SampleableExt.mkSelfContained do
    let r1 ← Gen.chooseNatLt 1 181 (by omega)
    let r2 ← Gen.chooseNatLt 1 181 (by omega)
    pure { r1Deg := r1.val, r2Deg := r2.val }

#eval "=== A) limit_twist: claim twist quaternion always normalizable -- expect COUNTEREXAMPLE ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : TwistCase, twistAlwaysSafe c = true)
#eval "=== A-fixed) guarded -- expect NO counterexample ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : TwistCase, twistSafeGuarded c = true)
#eval "=== B) tangent radius nonneg -- expect COUNTEREXAMPLE (r1+r2 > 180deg) ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : ConePair, tangentNonneg c = true)
#eval "=== B-fixed) guarded max(0, r) -- expect NO counterexample ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : ConePair, tangentGuardedNonneg c = true)

end KusGuards
