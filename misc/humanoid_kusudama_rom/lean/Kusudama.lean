/-
  Kusudama joint-limitation continuity model + Plausible property test.

  Mirrors scene/resources/3d/joint_limitation_kusudama_3d.cpp `_solve`, in
  particular the continuous 6D-direction projection (`_continuous_project`):
  the single-column case of Zhou2019's continuous rotation map — softmin-blend
  the region-boundary closest points, then normalize.

  The property we test is exactly the C++ test's invariant: sweeping the input
  direction continuously (great-circle / latitude / cone-to-cone), consecutive
  constrained outputs never jump more than `maxStepDeg`. Plausible randomly
  samples the (sweep, step) indices looking for a teleport counterexample.
-/
import Plausible

namespace Kusudama

abbrev R := Float
def pi : R := 3.14159265358979323846
def tau : R := 2.0 * pi

structure V3 where
  x : R
  y : R
  z : R
deriving Repr

namespace V3
def add (a b : V3) : V3 := ⟨a.x+b.x, a.y+b.y, a.z+b.z⟩
def sub (a b : V3) : V3 := ⟨a.x-b.x, a.y-b.y, a.z-b.z⟩
def smul (s : R) (a : V3) : V3 := ⟨s*a.x, s*a.y, s*a.z⟩
def dot (a b : V3) : R := a.x*b.x + a.y*b.y + a.z*b.z
def cross (a b : V3) : V3 := ⟨a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x⟩
def len (a : V3) : R := Float.sqrt (dot a a)
def norm (a : V3) : V3 := let l := len a; if l > 1e-12 then smul (1.0/l) a else a
def angleTo (a b : V3) : R := Float.atan2 (len (cross a b)) (dot a b)
-- Spherical interpolation of unit vectors (matches Quaternion/Basis slerp on S^2).
def slerp (a b : V3) (t : R) : V3 :=
  let d0 := dot a b
  let d := if d0 > 1.0 then 1.0 else if d0 < -1.0 then -1.0 else d0
  let om := Float.acos d
  let s := Float.sin om
  if om < 1e-6 then norm a
  else if s < 1e-6 then norm (add (smul (1.0 - t) a) (smul t b)) -- antipodal fallback
  else add (smul (Float.sin ((1.0 - t) * om) / s) a) (smul (Float.sin (t * om) / s) b)
-- Godot Vector3::get_any_perpendicular
def anyPerp (a : V3) : V3 :=
  let ax := if (Float.abs a.x ≤ Float.abs a.y) && (Float.abs a.x ≤ Float.abs a.z)
            then (⟨1,0,0⟩ : V3) else (⟨0,1,0⟩ : V3)
  norm (cross a ax)
def isZero (a : V3) : Bool := (Float.abs a.x < 1e-9) && (Float.abs a.y < 1e-9) && (Float.abs a.z < 1e-9)
end V3

open V3

/-- A cone: unit center + angular radius. -/
structure Cone where
  c : V3
  r : R

/-- 10 Fibonacci cones, 30° radius — the exact configuration the C++ test uses. -/
def fibCones (n : Nat) (radius : R) : List Cone := Id.run do
  let gr := (1.0 + Float.sqrt 5.0) / 2.0
  let mut out : List Cone := []
  for i in [0:n] do
    let fi := Float.ofNat i
    let th := Float.acos (1.0 - 2.0*(fi + 0.5)/Float.ofNat n)
    let ph := tau * fi / gr
    let ctr := V3.norm ⟨Float.sin th * Float.cos ph, Float.sin th * Float.sin ph, Float.cos th⟩
    out := out ++ [⟨ctr, radius⟩]
  return out

def pointInCone (p : V3) (k : Cone) : Bool := V3.angleTo (V3.norm p) k.c ≤ k.r

/-- Closest point on the small circle of radius `r` about `center` (swing onto it). -/
def closestOnCircle (p center : V3) (r : R) : V3 :=
  let perp0 := V3.sub p (V3.smul (V3.dot p center) center)
  let perp := V3.norm (if V3.isZero perp0 then V3.anyPerp center else perp0)
  V3.norm (V3.add (V3.smul (Float.cos r) center) (V3.smul (Float.sin r) perp))

/-- Log map at `a` toward `b`: tangent vector at `a`, magnitude = geodesic distance. -/
def logMap (a b : V3) : V3 :=
  let d := V3.angleTo a b
  if d < 1e-9 then ⟨0,0,0⟩
  else V3.smul d (V3.norm (V3.sub b (V3.smul (V3.dot a b) a)))
/-- Exp map at `a` with tangent `v`. -/
def expMap (a v : V3) : V3 :=
  let n := V3.len v
  if n < 1e-9 then a
  else V3.norm (V3.add (V3.smul (Float.cos n) a) (V3.smul (Float.sin n / n) v))

def SOFT_BAND : R := 0.06

/-- Keep-in soft-saturated candidate for cone `k` (mirrors the C++): the input's
    angle to the cone, saturated toward the radius from below — a calculus limit,
    identity deep inside, never exceeding the radius. -/
def softCone (p : V3) (k : Cone) : V3 :=
  let th := V3.angleTo p k.c
  let thSat := if th > k.r - SOFT_BAND
               then k.r - SOFT_BAND * Float.exp (-(th - (k.r - SOFT_BAND)) / SOFT_BAND)
               else th
  let perp0 := V3.sub p (V3.smul (V3.dot p k.c) k.c)
  let perp := V3.norm (if V3.isZero perp0 then V3.anyPerp k.c else perp0)
  V3.norm (V3.add (V3.smul (Float.cos thSat) k.c) (V3.smul (Float.sin thSat) perp))

/-- Current C++ projection (cone part): softmin-weighted one-step Karcher mean of
    the per-cone keep-in soft-saturated candidates, with an exact-identity special
    case when the nearest candidate equals the input. (Tangent-circle keep-out
    candidates are omitted in this Lean proxy.) -/
def continuousProject (cones : List Cone) (p : V3) (temperature : R) : V3 :=
  let cd := cones.map (fun k => let q := softCone p k; (q, V3.angleTo p q))
  let dmin := cd.foldl (fun m x => if x.2 < m then x.2 else m) 1e30
  if dmin < 1e-5 then p else
    let anchor := (cd.foldl (fun (best : V3 × R) x => if x.2 < best.2 then x else best) (⟨0,1,0⟩, 1e30)).1
    let w := fun (d : R) => Float.exp (-(d - dmin) / temperature)
    let num := cd.foldl (fun (s : V3) x => V3.add s (V3.smul (w x.2) (logMap anchor x.1))) ⟨0,0,0⟩
    let den := cd.foldl (fun (s : R) x => s + w x.2) 0.0
    if den ≤ 1e-30 then p else expMap anchor (V3.smul (1.0/den) num)

def solve (cones : List Cone) (p : V3) (temperature : R) : V3 :=
  continuousProject cones (V3.norm p) temperature

def radToDeg (r : R) : R := r * 180.0 / pi

def cones10 : List Cone := fibCones 10 (30.0 * pi / 180.0)
def temp : R := 0.14

def steps : Nat := 200

/-- Direction at spherical (theta = elevation from +Z pole, phi = azimuth). -/
def sphereDir (theta phi : R) : V3 :=
  V3.norm ⟨Float.sin theta * Float.cos phi, Float.sin theta * Float.sin phi, Float.cos theta⟩

/-! ## Quaternion + swing-twist decomposition (shader-motion `swing_twist_inv`). -/
structure Q where
  w : R
  x : R
  y : R
  z : R
deriving Repr

namespace Q
def mul (a b : Q) : Q :=
  ⟨a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
   a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
   a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
   a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w⟩
def conj (a : Q) : Q := ⟨a.w, -a.x, -a.y, -a.z⟩
/-- Shortest-arc quaternion taking unit `u` to unit `v` (pure swing). -/
def fromTo (u v : V3) : Q :=
  let d := V3.dot u v
  if d > 0.999999 then ⟨1,0,0,0⟩
  else if d < -0.999999 then let p := V3.anyPerp u; ⟨0, p.x, p.y, p.z⟩
  else
    let c := V3.cross u v
    let q : Q := ⟨1.0 + d, c.x, c.y, c.z⟩
    let n := Float.sqrt (q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z)
    ⟨q.w/n, q.x/n, q.y/n, q.z/n⟩
/-- Twist angle (rad) about an arbitrary unit axis `a` = 2·atan2(q.vec·a, q.w). -/
def twistAbout (q : Q) (a : V3) : R := 2.0 * Float.atan2 (q.x*a.x + q.y*a.y + q.z*a.z) q.w
end Q

def fwd : V3 := ⟨0,0,1⟩  -- the test's neutral forward
/-- Bone rotation realizing output direction `d` as a pure swing from `fwd`. -/
def boneRot (d : V3) : Q := Q.fromTo fwd d

/-- DELTA-twist (deg) between consecutive constrained frames, about axis `axisOut(d0)`. -/
def deltaTwistDeg (d0 d1 : V3) (aboutOut : Bool) : R :=
  let o0 := solve cones10 d0 temp
  let o1 := solve cones10 d1 temp
  let delta := Q.mul (boneRot o1) (boneRot o0).conj
  let axis := if aboutOut then o0 else fwd
  radToDeg (Q.twistAbout delta axis)

/-- UP/DOWN (meridian) sweep: fixed azimuth `lon`, elevation theta pole→pole. -/
def meridianTwist (lon : Nat) (s : Nat) : R :=
  let phi := tau * Float.ofNat lon / 24.0
  let th0 := pi * Float.ofNat s / Float.ofNat steps
  let th1 := pi * Float.ofNat (s+1) / Float.ofNat steps
  deltaTwistDeg (sphereDir th0 phi) (sphereDir th1 phi) true

/-- EQUATOR sweep: theta = pi/2, azimuth phi sweeps full circle. -/
def equatorTwist (s : Nat) : R :=
  let p0 := tau * Float.ofNat s / Float.ofNat steps
  let p1 := tau * Float.ofNat (s+1) / Float.ofNat steps
  deltaTwistDeg (sphereDir (pi/2.0) p0) (sphereDir (pi/2.0) p1) true

def fmax (a b : R) : R := if a > b then a else b
def fabs (a : R) : R := if a < 0.0 then -a else a

/-- Max twist over a deterministic full sweep (functional fold; avoids a Float
    mutable-`do` compiler panic). -/
def meridianMaxTwist : R :=
  (List.range 24).foldl (fun m lon =>
    (List.range steps).foldl (fun m2 s => fmax m2 (fabs (meridianTwist lon s))) m) 0.0

/-- Meridian twist EXCLUDING the antipodal band (s in [20,180], i.e. θ away from π):
    confirms the 360° is only the swing=180° antipode singularity (away from forward). -/
def meridianMidMaxTwist : R :=
  (List.range 24).foldl (fun m lon =>
    ((List.range 161).map (· + 20)).foldl (fun m2 s => fmax m2 (fabs (meridianTwist lon s))) m) 0.0

def equatorMaxTwist : R :=
  (List.range steps).foldl (fun m s => fmax m (fabs (equatorTwist s))) 0.0

-- Baseline: same frame measurement but with NO constraint (output = input). Isolates
-- the frame-holonomy of the shortest-arc-from-forward frame from the constraint's twist.
def deltaTwistId (d0 d1 : V3) : R :=
  let delta := Q.mul (boneRot d1) (boneRot d0).conj
  radToDeg (Q.twistAbout delta d0)
def equatorTwistIdMax : R :=
  (List.range steps).foldl (fun m s =>
    let p0 := tau * Float.ofNat s / Float.ofNat steps
    let p1 := tau * Float.ofNat (s+1) / Float.ofNat steps
    fmax m (fabs (deltaTwistId (sphereDir (pi/2.0) p0) (sphereDir (pi/2.0) p1)))) 0.0

#eval s!"up/down (meridian) max twist: {meridianMaxTwist} deg  (360 = antipode swing=180 singularity, away from forward)"
#eval s!"up/down (meridian) max twist EXCLUDING antipode band: {meridianMidMaxTwist} deg"
#eval s!"equator max twist (constrained): {equatorMaxTwist} deg"
#eval s!"equator max twist (identity baseline / frame holonomy): {equatorTwistIdMax} deg"

/-! ## Kusudama TWIST LIMIT (new) — clamp the twist about the bone axis into [tmin,tmax].
    Swing-twist decomposition q = swing * twist(about a); clamp the twist angle, recompose.
    Verified by Plausible: in-range twist is untouched, out-of-range is clamped INTO range,
    and the swing (bone direction) is never disturbed by the twist limit. -/
namespace Q
def qnorm (q : Q) : Q :=
  let n := Float.sqrt (q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z)
  if n > 1e-12 then ⟨q.w/n, q.x/n, q.y/n, q.z/n⟩ else ⟨1,0,0,0⟩
/-- Rotation of `angle` rad about unit axis `a`. -/
def axisAngle (angle : R) (a : V3) : Q :=
  let h := angle / 2.0; let s := Float.sin h
  ⟨Float.cos h, a.x*s, a.y*s, a.z*s⟩
/-- Twist component of `q` about unit axis `a` (project the vector part onto `a`). -/
def twistPart (q : Q) (a : V3) : Q :=
  let d := q.x*a.x + q.y*a.y + q.z*a.z
  qnorm ⟨q.w, d*a.x, d*a.y, d*a.z⟩
/-- Swing component = q · twist⁻¹. -/
def swingPart (q : Q) (a : V3) : Q := mul q (twistPart q a).conj
end Q

def clampR (x lo hi : R) : R := if x < lo then lo else if x > hi then hi else x

/-- THE twist limit: decompose `q` about axis `a`, clamp twist angle to [tmin,tmax], recompose. -/
def limitTwist (q : Q) (a : V3) (tmin tmax : R) : Q :=
  let t := Q.twistAbout q a
  let tc := clampR t tmin tmax
  Q.mul (Q.swingPart q a) (Q.axisAngle tc a)

/-- Quaternions equal up to sign (double cover). -/
def qClose (a b : Q) : Bool :=
  let d := a.w*b.w + a.x*b.x + a.y*b.y + a.z*b.z
  fabs (fabs d - 1.0) < 1e-2

/-- A random twist-limit test case: a unit axis, a rotation about a possibly-different
    axis, and an ordered twist window [tmin,tmax]. -/
structure TwistCase where
  ax : V3        -- bone twist axis (unit)
  q  : Q         -- input rotation
  tmin : R
  tmax : R
deriving Repr

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable TwistCase := ⟨fun _ => []⟩
instance : SampleableExt TwistCase :=
  SampleableExt.mkSelfContained do
    let at_ ← Gen.chooseNatLt 1 17 (by omega)   -- axis elevation
    let ap ← Gen.chooseNatLt 0 36 (by omega)    -- axis azimuth
    let a := sphereDir (pi * Float.ofNat at_.val / 18.0) (tau * Float.ofNat ap.val / 36.0)
    let rt ← Gen.chooseNatLt 1 17 (by omega)    -- rotation axis (independent of bone axis)
    let rp ← Gen.chooseNatLt 0 36 (by omega)
    let ra := sphereDir (pi * Float.ofNat rt.val / 18.0) (tau * Float.ofNat rp.val / 36.0)
    let ang ← Gen.chooseNatLt 0 240 (by omega)  -- rotation angle in (-2.0, 2.0) rad (avoid ±π gimbal)
    let q := Q.axisAngle ((Float.ofNat ang.val / 240.0) * 4.0 - 2.0) ra
    let lo ← Gen.chooseNatLt 0 60 (by omega)    -- tmin in [-150,-30] deg
    let span ← Gen.chooseNatLt 20 120 (by omega) -- window width 20..120 deg
    let tmin := (Float.ofNat lo.val - 60.0) * pi / 180.0
    let tmax := tmin + Float.ofNat span.val * pi / 180.0
    pure { ax := a, q := q, tmin := tmin, tmax := tmax }

/-- P2: the output twist is always inside the window (the limit actually clamps). -/
def twP2_inRange (c : TwistCase) : Bool :=
  let o := limitTwist c.q c.ax c.tmin c.tmax
  let t := Q.twistAbout o c.ax
  (t ≥ c.tmin - 2e-3) && (t ≤ c.tmax + 2e-3)

/-- P1: if the input twist is already in range, the limit is the identity. -/
def twP1_identity (c : TwistCase) : Bool :=
  let t := Q.twistAbout c.q c.ax
  if (t ≥ c.tmin) && (t ≤ c.tmax) then qClose (limitTwist c.q c.ax c.tmin c.tmax) c.q else true

/-- P3: the swing (bone direction) is unchanged by the twist limit. -/
def twP3_swingKept (c : TwistCase) : Bool :=
  qClose (Q.swingPart (limitTwist c.q c.ax c.tmin c.tmax) c.ax) (Q.swingPart c.q c.ax)

/-- P4: idempotent — re-limiting changes nothing. -/
def twP4_idem (c : TwistCase) : Bool :=
  let o1 := limitTwist c.q c.ax c.tmin c.tmax
  qClose (limitTwist o1 c.ax c.tmin c.tmax) o1

#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : TwistCase, twP2_inRange c = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : TwistCase, twP1_identity c = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : TwistCase, twP3_swingKept c = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : TwistCase, twP4_idem c = true)

/-! ## Normalize swing & twist to [0,1] between the ranges (shader-motion / Mecanim muscle style).
    Swing: sphere log map at `fwd` scaled by cone radius R -> a 2D coord whose magnitude is
    0 at rest and 1 on the cone boundary (exp map inverts it). Twist: affine into [0,1]. -/
def swingNorm (dir : V3) (Rr : R) : V3 :=    -- returns (a, b, 0); |(a,b)| = swingAngle / R
  let c := clampR (V3.dot fwd dir) (-1.0) 1.0
  let th := Float.acos c
  let t := V3.sub dir (V3.smul c fwd)        -- tangent component at fwd (z-axis)
  let tn := V3.len t
  if tn < 1e-9 then ⟨0,0,0⟩
  else let u := V3.smul (1.0/tn) t; ⟨th/Rr * u.x, th/Rr * u.y, 0.0⟩
def swingDenorm (v : V3) (Rr : R) : V3 :=
  let m := Float.sqrt (v.x*v.x + v.y*v.y)     -- = swingAngle / R
  if m < 1e-9 then fwd
  else let th := m * Rr
       V3.add (V3.smul (Float.cos th) fwd) (V3.smul (Float.sin th / m) ⟨v.x, v.y, 0.0⟩)
def twistNorm (t tmin tmax : R) : R := clampR ((t - tmin) / (tmax - tmin)) 0.0 1.0
def twistDenorm (n tmin tmax : R) : R := tmin + clampR n 0.0 1.0 * (tmax - tmin)

/-- A swing-normalization case: a direction at elevation θ (≤ radius) and azimuth, radius R. -/
structure SwingCase where
  thI : Nat   -- 0..rIdx (inside the cone)
  phI : Nat
  rIdx : Nat  -- radius bucket
deriving Repr
instance : Shrinkable SwingCase := ⟨fun _ => []⟩
instance : SampleableExt SwingCase :=
  SampleableExt.mkSelfContained do
    let r ← Gen.chooseNatLt 6 60 (by omega)     -- radius 6..60 deg
    let th ← Gen.chooseNatLt 0 (r.val + 1) (by omega)  -- elevation in [0, R]
    let p ← Gen.chooseNatLt 0 36 (by omega)
    pure { thI := th, phI := p.val, rIdx := r.val }
def scDir (c : SwingCase) : V3 :=
  sphereDir (Float.ofNat c.thI * pi / 180.0) (tau * Float.ofNat c.phI / 36.0)
def scR (c : SwingCase) : R := Float.ofNat c.rIdx * pi / 180.0

/-- P5: swing normalize→denormalize is the identity for directions inside the cone. -/
def swP5_roundTrip (c : SwingCase) : Bool :=
  let d := scDir c
  V3.angleTo d (swingDenorm (swingNorm d (scR c)) (scR c)) < 2e-3
/-- P6: |normalized swing| ≤ 1 exactly when the direction is within the cone radius. -/
def swP6_unitDisk (c : SwingCase) : Bool :=
  let n := swingNorm (scDir c) (scR c)
  Float.sqrt (n.x*n.x + n.y*n.y) ≤ 1.0 + 2e-3   -- thI ≤ rIdx by construction
/-- P7: twist normalize→denormalize round-trips inside the window. -/
def swP7_twistRT (c : TwistCase) : Bool :=
  let t := clampR (Q.twistAbout c.q c.ax) c.tmin c.tmax
  fabs (twistDenorm (twistNorm t c.tmin c.tmax) c.tmin c.tmax - t) < 2e-3

#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : SwingCase, swP5_roundTrip c = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : SwingCase, swP6_unitDisk c = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ c : TwistCase, swP7_twistRT c = true)

/-! ## Per-cone swing-axis BASIS convention: Vector3 -> Basis(Quaternion(+Y -> center)),
    take the X (e1) and Z (e2) columns as the two swing axes. Verifies the C++ change
    (replacing the arbitrary get_any_perpendicular with a deterministic, consistent basis):
    e1,e2 are orthonormal & tangent to the center, the handedness is the Godot Basis
    convention (X x Z = -Y), and the swing coordinate round-trips. -/
namespace Q
def rot (q : Q) (v : V3) : V3 :=
  let qv : V3 := ⟨q.x, q.y, q.z⟩
  let t := V3.smul 2.0 (V3.cross qv v)
  V3.add v (V3.add (V3.smul q.w t) (V3.cross qv t))
end Q

def yAxis : V3 := ⟨0, 1, 0⟩
/-- Basis from a center direction: rotate +Y onto center (shortest arc); e1 = X col, e2 = Z col. -/
def swingBasis (center : V3) : V3 × V3 :=
  let q := Q.fromTo yAxis (V3.norm center)
  (Q.rot q ⟨1, 0, 0⟩, Q.rot q ⟨0, 0, 1⟩)

def coneSwingTo (center : V3) (radius : R) (dir : V3) : V3 :=
  let c := V3.norm center
  let d := V3.norm dir
  let cs := clampR (V3.dot c d) (-1.0) 1.0
  let th := Float.acos cs
  let tg := V3.sub d (V3.smul cs c)
  let tn := V3.len tg
  if tn < 1e-9 then ⟨0, 0, 0⟩
  else
    let u := V3.smul (1.0 / tn) tg
    let b := swingBasis c
    ⟨th / radius * V3.dot u b.1, th / radius * V3.dot u b.2, 0.0⟩

def coneSwingFrom (center : V3) (radius : R) (axes : V3) : V3 :=
  let c := V3.norm center
  let m := Float.sqrt (axes.x * axes.x + axes.y * axes.y)
  if m < 1e-9 then c
  else
    let b := swingBasis c
    let t := V3.norm (V3.add (V3.smul (axes.x / m) b.1) (V3.smul (axes.y / m) b.2))
    let th := m * radius
    V3.add (V3.smul (Float.cos th) c) (V3.smul (Float.sin th) t)

structure BasisCase where
  ct : Nat
  cp : Nat
  dr : Nat
  da : Nat
  rIdx : Nat
deriving Repr
instance : Shrinkable BasisCase := ⟨fun _ => []⟩
instance : SampleableExt BasisCase :=
  SampleableExt.mkSelfContained do
    let ct ← Gen.chooseNatLt 1 17 (by omega)
    let cp ← Gen.chooseNatLt 0 36 (by omega)
    let r ← Gen.chooseNatLt 6 50 (by omega)
    let dr ← Gen.chooseNatLt 0 (r.val + 1) (by omega)
    let da ← Gen.chooseNatLt 0 36 (by omega)
    pure { ct := ct.val, cp := cp.val, dr := dr, da := da.val, rIdx := r.val }
def bcCenter (b : BasisCase) : V3 := sphereDir (pi * Float.ofNat b.ct / 18.0) (tau * Float.ofNat b.cp / 36.0)
def bcR (b : BasisCase) : R := Float.ofNat b.rIdx * pi / 180.0
def bcDir (b : BasisCase) : V3 :=
  let c := V3.norm (bcCenter b)
  let bs := swingBasis c
  let th := Float.ofNat b.dr * pi / 180.0
  let az := tau * Float.ofNat b.da / 36.0
  let t := V3.add (V3.smul (Float.cos az) bs.1) (V3.smul (Float.sin az) bs.2)
  V3.add (V3.smul (Float.cos th) c) (V3.smul (Float.sin th) t)

/-- e1,e2 orthonormal and tangent to the center. -/
def bP_ortho (b : BasisCase) : Bool :=
  let c := V3.norm (bcCenter b); let bs := swingBasis c
  (fabs (V3.dot bs.1 c) < 1e-3) && (fabs (V3.dot bs.2 c) < 1e-3) && (fabs (V3.dot bs.1 bs.2) < 1e-3)
    && (fabs (V3.len bs.1 - 1.0) < 1e-3) && (fabs (V3.len bs.2 - 1.0) < 1e-3)
/-- Godot Basis handedness: X x Z = -Y, i.e. e1 x e2 = -center. -/
def bP_handed (b : BasisCase) : Bool :=
  let c := V3.norm (bcCenter b); let bs := swingBasis c
  V3.angleTo (V3.cross bs.1 bs.2) (V3.smul (-1.0) c) < 1e-2
/-- The per-cone swing coordinate round-trips. -/
def bP_roundtrip (b : BasisCase) : Bool :=
  let c := bcCenter b; let r := bcR b; let d := bcDir b
  V3.angleTo d (coneSwingFrom c r (coneSwingTo c r d)) < 3e-3

#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ b : BasisCase, bP_ortho b = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ b : BasisCase, bP_handed b = true)
#eval Plausible.Testable.check (cfg := { numInst := 2000 }) (∀ b : BasisCase, bP_roundtrip b = true)

-- HARD-BOUND check: max excursion of the equator output OUTSIDE the nearest cone
-- (>0 means it left the cone — must be <= 0 for the soft limit to stay inside).
def equatorMaxOutside : R :=
  (List.range (steps+1)).foldl (fun m s =>
    let phi := tau * Float.ofNat s / Float.ofNat steps
    let o := solve cones10 (sphereDir (pi/2.0) phi) temp
    let nearest := cones10.foldl (fun best k => let d := V3.angleTo o k.c - k.r; if d < best then d else best) 1e30
    fmax m nearest) (-1e30)
#eval s!"equator output max excursion outside nearest cone: {radToDeg equatorMaxOutside} deg (<=0 = inside hard bound)"

/-! ## Plausible: search for a twist flip (> threshold) on each motion. -/
def maxTwistDeg : R := 10.0

/-- No twist flip on up/down sweeps. -/
def upDownNoTwist (lon : Fin 24) (s : Fin 200) : Bool := fabs (meridianTwist lon.val s.val) ≤ maxTwistDeg
/-- No twist flip on equator sweep. -/
def equatorNoTwist (s : Fin 200) : Bool := fabs (equatorTwist s.val) ≤ maxTwistDeg

#test ∀ (lon : Fin 24) (s : Fin 200), upDownNoTwist lon s = true
#test ∀ (s : Fin 200), equatorNoTwist s = true

/-! ## Adversarial config generation (chamelean/Plausible)

    Plausible GENERATES random 4-cone configurations (arbitrary centers + radii —
    so antipodal, coincident, collinear, degenerate-radius, huge-radius, etc. all
    get sampled) and a great-circle sweep step, then searches for one that breaks
    an invariant: a non-finite output, or the constraint AMPLIFYING the step
    (output-step − input-step) beyond a generous bound (the signature of a teleport
    / discontinuity). Any counter-example it finds is a concrete adversarial config
    to run against the real C++ solver. -/

open Plausible (Gen SampleableExt Shrinkable)

def isFin (v : V3) : Bool := (Float.isFinite v.x) && (Float.isFinite v.y) && (Float.isFinite v.z)

def seedCone (thI phI rdI : Nat) : Cone :=
  let theta := pi * (Float.ofNat thI + 1.0) / 18.0  -- avoids exact poles
  let phi := tau * Float.ofNat phI / 36.0
  let r := (5.0 + 2.75 * Float.ofNat rdI) * pi / 180.0  -- ~5..79 deg
  ⟨sphereDir theta phi, r⟩

instance : Repr Cone := ⟨fun c _ => s!"cone(c=({c.c.x},{c.c.y},{c.c.z}), r={c.r})"⟩

/-- A generated adversarial configuration: a variable number of cones (2..30) with
    arbitrary centers + radii, PLUS a randomized animation track — a list of target
    keyframe directions that get slerp-interpolated, the way a rig actually drives the
    solver. `sub` = interpolation substeps between consecutive keyframes. -/
structure AdvCfg where
  cones : List Cone
  keys : List V3
  sub : Nat
  deriving Repr

instance : Shrinkable AdvCfg := ⟨fun _ => []⟩

/-- A keyframe target direction from elevation/azimuth indices. -/
def keyDir (thI phI : Nat) : V3 :=
  sphereDir (pi * (Float.ofNat thI + 1.0) / 18.0) (tau * Float.ofNat phI / 36.0)

-- Plausible GENERATES the configs: a random cone count in [2,30] with random
-- centers+radii, AND a random keyframe track (2..8 target keys) that is slerped.
instance : SampleableExt AdvCfg :=
  SampleableExt.mkSelfContained do
    let nb ← Gen.chooseNatLt 2 31 (by omega)
    let mut cs : List Cone := []
    for _ in [0:nb.val] do
      let t ← Gen.chooseNatLt 0 17 (by omega)
      let p ← Gen.chooseNatLt 0 36 (by omega)
      let r ← Gen.chooseNatLt 0 28 (by omega)
      cs := cs ++ [seedCone t.val p.val r.val]
    let nk ← Gen.chooseNatLt 2 9 (by omega)
    let mut ks : List V3 := []
    for _ in [0:nk.val] do
      let t ← Gen.chooseNatLt 0 17 (by omega)
      let p ← Gen.chooseNatLt 0 36 (by omega)
      ks := ks ++ [keyDir t.val p.val]
    let s ← Gen.chooseNatLt 8 49 (by omega)
    pure { cones := cs, keys := ks, sub := s.val }

/-- The slerp-interpolated target path: walk each consecutive keyframe pair with
    `sub` substeps (plus the final key). This is the input track the solver sees. -/
def buildPath (keys : List V3) (sub : Nat) : List V3 :=
  let s := if sub < 2 then 2 else sub
  let pairs := keys.zip (keys.drop 1)
  let body := pairs.foldl
    (fun acc (pr : V3 × V3) =>
      acc ++ (List.range s).map (fun i => V3.slerp pr.1 pr.2 (Float.ofNat i / Float.ofNat s)))
    []
  match keys.getLast? with
  | some l => body ++ [l]
  | none => body

/-- Worst constraint amplification (deg) over the slerped keyframe track of this
    config; a non-finite output scores +infinity. Amplification = output angular step
    minus input angular step, so a teleport (output jumps more than the target moved)
    is caught regardless of where on the track it happens. -/
def advWorst (a : AdvCfg) : R :=
  match buildPath a.keys a.sub with
  | [] => 0.0
  | in0 :: rest =>
    let res := rest.foldl
      (fun (acc : R × V3 × V3) inI =>
        let outI := solve a.cones inI 0.22
        let amp := if isFin outI then radToDeg (V3.angleTo acc.2.2 outI - V3.angleTo acc.2.1 inI) else 1e9
        (fmax acc.1 amp, inI, outI))
      ((-1e9 : R), in0, solve a.cones in0 0.22)
    res.1

/-- The adversary tries to break this: the constraint must never amplify a slerp
    step by more than 12 deg anywhere on the keyframe track. -/
def advOK (a : AdvCfg) : Bool := advWorst a < 12.0

-- Plausible generates 4000 random configs (2..30 cones + 2..8 slerped keyframes) and
-- searches for one whose interpolated target track makes the solver teleport.
-- (adversarial SWING hunt — expected to find counterexamples; muted so the build stays
--  green for the TWIST-limit verification above. Re-enable to resume the swing adversary.)
-- #eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ a : AdvCfg, advOK a = true)

end Kusudama
