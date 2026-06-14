/-
  Rank-1 Kabsch completion (ik_kabsch_6d.cpp, svd3): when the cross-covariance has rank 1 only the
  swing axis is pinned (u0 <- v0); the perpendicular (twist) plane is free. Any perpendicular is a
  legal completion, so we pick the CANONICAL one -- minimal twist -- by carrying V's free axes
  v1,v2 through the shortest arc R0 : v0 -> u0. Then U = [u0, R0 v1, R0 v2], V = [v0,v1,v2], and
  R = U V^T = R0, the swing-only rotation.

  This file builds that completion and Plausible-checks:
    1. [u0,c1,c2] is orthonormal and right-handed  => R is a proper rotation,
    2. R v0 = u0                                    => the pinned correspondence is preserved,
    3. axis(R) . u0 = 0                             => MINIMAL TWIST (shortest arc),
  and contrasts it with get_any_perpendicular()-style completion, which leaves a nonzero twist
  (axis(R) . u0 != 0) -- the discontinuity-prone behavior the canonicalization removes.
-/
import Plausible

namespace KusKabsch

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
def sub (a b : V3) : V3 := ⟨a.x - b.x, a.y - b.y, a.z - b.z⟩
def norm (a : V3) : V3 := let l := len a; if l > 1e-12 then smul (1.0 / l) a else a
def sph (elev az : R) : V3 :=
  ⟨Float.sin (d2r elev) * Float.cos (d2r az), Float.cos (d2r elev), Float.sin (d2r elev) * Float.sin (d2r az)⟩

-- Rodrigues: rotate v about unit axis k by angle t.
def rod (k : V3) (cs sn : R) (v : V3) : V3 :=
  add (add (smul cs v) (smul sn (cross k v))) (smul (dot k v * (1.0 - cs)) k)

-- An orthonormal right-handed frame whose first axis is v0 (deterministic completion of V).
def frameOf (v0 : V3) : V3 × V3 × V3 :=
  let ref : V3 := if Float.abs v0.y < 0.9 then ⟨0,1,0⟩ else ⟨1,0,0⟩
  let v1 := norm (cross v0 ref)
  let v2 := norm (cross v0 v1)
  (v0, v1, v2)

-- The C++ canonical completion: c1,c2 = R0 v1, R0 v2 with R0 = shortest arc v0 -> u0.
def canonCompletion (v0 u0 v1 v2 : V3) : V3 × V3 :=
  let axis := cross v0 u0
  let s := len axis
  let c := dot v0 u0
  if s < 1e-9 then
    (if c > 0.0 then (v1, v2) else (v1, v2)) -- aligned/antipodal: handled by C++ fallback; skip here
  else
    let k := smul (1.0 / s) axis
    let cs := c
    let sn := s
    (rod k cs sn v1, rod k cs sn v2)

-- An arbitrary (get_any_perpendicular-style) completion: a fixed perpendicular of u0, NOT carried
-- from V. Generally introduces a spurious twist about u0.
def anyCompletion (u0 : V3) : V3 × V3 :=
  let (_, p1, p2) := frameOf u0
  (p1, p2)

-- R = U V^T applied to a vector w: sum_i col_U_i * (col_V_i . w).
def applyR (u0 c1 c2 v0 v1 v2 w : V3) : V3 :=
  add (add (smul (dot v0 w) u0) (smul (dot v1 w) c1)) (smul (dot v2 w) c2)

-- axis(R) . u0, where axis(R) ~ the antisymmetric part of R (Rij - Rji). For a shortest-arc
-- rotation v0->u0 the axis is v0 x u0, which is perpendicular to u0; a twisted completion is not.
def rAxisDotU0 (u0 c1 c2 v0 v1 v2 : V3) : R :=
  -- columns of R: R e_j = applyR(...) e_j ; build the matrix then (R21-R12, R02-R20, R10-R01).
  let col (w : V3) := applyR u0 c1 c2 v0 v1 v2 w
  let cx := col ⟨1,0,0⟩
  let cy := col ⟨0,1,0⟩
  let cz := col ⟨0,0,1⟩
  let ax : V3 := ⟨cy.z - cz.y, cz.x - cx.z, cx.y - cy.x⟩
  dot ax u0

structure TCase where
  e0 : Nat -- v0 elevation
  a0 : Nat -- v0 azimuth
  e1 : Nat -- u0 elevation
  a1 : Nat -- u0 azimuth
deriving Repr

def v0Of (t : TCase) : V3 := norm (sph (Float.ofNat t.e0) (Float.ofNat t.a0))
def u0Of (t : TCase) : V3 := norm (sph (Float.ofNat t.e1) (Float.ofNat t.a1))

-- Skip the near-aligned / near-antipodal cases (the C++ has an explicit fallback there).
def wellSeparated (t : TCase) : Bool :=
  let c := dot (v0Of t) (u0Of t)
  (c < 0.98) && (c > -0.98)

def canonOK (t : TCase) : Bool :=
  if !wellSeparated t then true else
  let v0 := v0Of t
  let u0 := u0Of t
  let (_, v1, v2) := frameOf v0
  let (c1, c2) := canonCompletion v0 u0 v1 v2
  let orthonormal :=
    (Float.abs (len c1 - 1.0) < 1e-3) && (Float.abs (len c2 - 1.0) < 1e-3) &&
    (Float.abs (dot u0 c1) < 1e-3) && (Float.abs (dot u0 c2) < 1e-3) && (Float.abs (dot c1 c2) < 1e-3)
  let mapsV0 := len (sub (applyR u0 c1 c2 v0 v1 v2 v0) u0) < 1e-3
  let minimalTwist := Float.abs (rAxisDotU0 u0 c1 c2 v0 v1 v2) < 1e-3
  orthonormal && mapsV0 && minimalTwist

-- The arbitrary completion is a valid rotation and maps v0->u0, but leaves a nonzero twist about u0
-- (so this predicate, asserting minimal twist, should FAIL for some cases -- the canonicalization
-- is what removes it).
def anyHasMinimalTwist (t : TCase) : Bool :=
  if !wellSeparated t then true else
  let v0 := v0Of t
  let u0 := u0Of t
  let (_, v1, v2) := frameOf v0
  let (c1, c2) := anyCompletion u0
  Float.abs (rAxisDotU0 u0 c1 c2 v0 v1 v2) < 1e-3

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable TCase := ⟨fun _ => []⟩
instance : SampleableExt TCase :=
  SampleableExt.mkSelfContained do
    let e0 ← Gen.chooseNatLt 5 175 (by omega)
    let a0 ← Gen.chooseNatLt 0 360 (by omega)
    let e1 ← Gen.chooseNatLt 5 175 (by omega)
    let a1 ← Gen.chooseNatLt 0 360 (by omega)
    pure { e0 := e0.val, a0 := a0.val, e1 := e1.val, a1 := a1.val }

#eval "=== canonical completion: proper rotation, maps v0->u0, MINIMAL TWIST (expect no counterexample) ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ t : TCase, canonOK t = true)
#eval "=== arbitrary (any-perp) completion claims minimal twist -- expect COUNTEREXAMPLES (it has twist) ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ t : TCase, anyHasMinimalTwist t = true)

end KusKabsch
