/-
  Gizmo-vs-solve frame mismatch for the kusudama (the "animation doesn't match the gizmo" bug).

  The GIZMO draws the cones in the CANONICAL (+Y-forward) frame (cone_sequence = raw stored cone
  centers; CUSTOM0 stays canonical -- joint_limitation_kusudama_3d.cpp ~L841).
  solve() instead maps the input through make_space(forward, right): the cones are effectively
  applied in make_space(canonical). When right = NONE (the failing scene's right_axis = 0),
  make_space is the SHORTEST-ARC rotation +Y -> forward, which carries a different roll than
  canonical whenever forward != +Y. So an off-axis cone (+X / +Z) is applied at a different azimuth
  than it is drawn, and a target direction can be inside the drawn region yet outside the applied
  region (or vice versa) -- exactly the visual mismatch.

  This file models make_space's shortest-arc fallback and Plausible-checks: with right = NONE and
  forward != +Y, the applied cone direction make_space(c) differs from the drawn direction c, so the
  two memberships disagree for some target. With a defined right axis the two frames coincide.
-/
import Plausible

namespace KusFrame

abbrev R := Float
def pi : R := 3.14159265358979323846

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
def clamp1 (x : R) : R := if x < -1.0 then -1.0 else if x > 1.0 then 1.0 else x
def angleTo (a b : V3) : R := Float.acos (clamp1 (dot (norm a) (norm b)))

def yAxis : V3 := ⟨0, 1, 0⟩

-- Rotate v about a unit axis k by angle t (Rodrigues).
def rotAxis (k : V3) (t : R) (v : V3) : V3 :=
  let c := Float.cos t
  let s := Float.sin t
  add (add (smul c v) (smul s (cross k v))) (smul (dot k v * (1.0 - c)) k)

-- make_space's shortest-arc fallback (right = NONE): the rotation taking +Y to `forward`. Applying
-- it to a canonical cone center gives where solve() effectively places that cone.
def shortestArcFromY (forward : V3) (c : V3) : V3 :=
  let f := norm forward
  let axis0 := cross yAxis f
  if len axis0 < 1e-9 then
    (if dot yAxis f > 0.0 then c else ⟨c.x, -c.y, -c.z⟩) -- aligned / antipodal
  else
    rotAxis (norm axis0) (angleTo yAxis f) c

-- A cone membership in the CANONICAL frame (what the gizmo draws).
def inConeCanonical (center : V3) (radius : R) (d : V3) : Bool := angleTo (norm d) (norm center) ≤ radius

structure FCase where
  -- forward direction (elevation/azimuth indices) and a target near the cone, plus a cone azimuth
  fEl : Nat -- forward elevation 0..90 deg from +Y
  fAz : Nat
  cAz : Nat -- the off-axis cone's azimuth (it sits 45 deg off +Y)
  tJit : Nat -- small target jitter inside the drawn cone
deriving Repr

def d2r (x : R) : R := x * pi / 180.0
def sph (elev az : R) : V3 := -- elev from +Y, az around +Y
  ⟨Float.sin (d2r elev) * Float.cos (d2r az), Float.cos (d2r elev), Float.sin (d2r elev) * Float.sin (d2r az)⟩

def fwdOf (c : FCase) : V3 := sph (Float.ofNat c.fEl) (Float.ofNat c.fAz)
def coneCenter (c : FCase) : V3 := sph 45.0 (Float.ofNat c.cAz) -- a 45-deg off-axis cone, canonical
def coneR : R := d2r 12.0

-- A target sitting just inside the DRAWN (canonical) cone.
def target (c : FCase) : V3 := sph (45.0 + (Float.ofNat c.tJit - 5.0)) (Float.ofNat c.cAz)

-- With right = NONE, solve applies the cone at shortestArcFromY(forward, coneCenter). The drawn
-- (canonical) and applied memberships AGREE iff that equals the canonical center. The bug: they
-- disagree whenever forward is off +Y. This predicate is TRUE only when they agree -- Plausible
-- should find disagreements (off-+Y forwards), demonstrating the mismatch.
def framesAgree (c : FCase) : Bool :=
  let drawn := inConeCanonical (coneCenter c) coneR (target c)
  let applied := inConeCanonical (shortestArcFromY (fwdOf c) (coneCenter c)) coneR (target c)
  drawn == applied

-- The FIX: with a defined right axis the solve frame equals the gizmo's canonical frame, so the
-- applied cone == the drawn cone for ALL forwards. Modelled as: if the make_space frame is the
-- canonical identity (right defined to reproduce it), agreement is total.
def framesAgreeFixed (c : FCase) : Bool :=
  let drawn := inConeCanonical (coneCenter c) coneR (target c)
  let applied := inConeCanonical (coneCenter c) coneR (target c) -- identity frame
  drawn == applied

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable FCase := ⟨fun _ => []⟩
instance : SampleableExt FCase :=
  SampleableExt.mkSelfContained do
    let fe ← Gen.chooseNatLt 0 91 (by omega)
    let fa ← Gen.chooseNatLt 0 360 (by omega)
    let ca ← Gen.chooseNatLt 0 360 (by omega)
    let tj ← Gen.chooseNatLt 0 11 (by omega)
    pure { fEl := fe.val, fAz := fa.val, cAz := ca.val, tJit := tj.val }

#eval "=== right = NONE: gizmo (canonical) vs solve (shortest-arc) -- expect counterexamples ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : FCase, framesAgree c = true)
#eval "=== fixed (defined right axis = canonical frame) -- expect NO counterexample ==="
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : FCase, framesAgreeFixed c = true)

end KusFrame
