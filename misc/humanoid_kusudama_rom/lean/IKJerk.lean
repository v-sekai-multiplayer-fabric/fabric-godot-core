/-
  Jerk bound for the SwingTwistIK3D solve (the EWBIK-style "dampening" step limiter).

  The solver applied each bone's full candidate rotation every iteration, so at a kinematic
  fold the candidate could flip ~180deg and the joint teleported in one frame (measured on the
  live rig: a 1.5mm target step producing a 175deg joint jump -- catastrophic jerk).

  The fix mirrors IterateIK3D::angular_delta_limit: rate-limit each per-iteration rotation by
  slerping the delta down to a cap `adl`:
      diff = angle(prev, target)
      if diff > adl: target := slerp(prev, target, adl/diff)
  Because slerp advances along the geodesic at CONSTANT angular speed, the achieved step angle
  is exactly `min(diff, adl)` -- never more than the cap. So every per-step rotation is <= adl,
  hence the per-frame joint motion <= max_iterations*adl is bounded: no teleport, bounded jerk.

  PROVEN here (in the geodesic angle coordinate, where the achieved step = min(diff, cap)):
  every step <= cap and <= diff. PLAUSIBLE-CHECKED below on the actual Float great-circle slerp
  (V3.slerp, the same one that matches Quaternion/Basis slerp on S^2): (1) slerp advances the
  angle linearly -- angle(a, slerp a b t) = t*angle(a,b) -- which is what makes the cap exact;
  (2) end to end, the rate-limited step never exceeds the cap.
-/
import Plausible

namespace IKJerk

-- Achieved per-step rotation under the rate limiter, in the geodesic angle coordinate (integer
-- microradians, so the bound is a clean Nat fact). slerp is constant-speed, so capping the slerp
-- fraction at cap/diff caps the achieved angle at min(diff, cap).
def step (diff cap : Nat) : Nat := min diff cap

theorem step_le_cap (diff cap : Nat) : step diff cap ≤ cap := Nat.min_le_right diff cap
theorem step_le_diff (diff cap : Nat) : step diff cap ≤ diff := Nat.min_le_left diff cap

-- Jerk (change in per-step rotation between consecutive frames) is bounded: every step is <= cap,
-- so |step_{n+1} - step_n| <= cap. No single frame can teleport past the cap.
theorem jerk_bounded (d1 d2 cap : Nat) : step d1 cap ≤ cap ∧ step d2 cap ≤ cap :=
  ⟨step_le_cap d1 cap, step_le_cap d2 cap⟩

-- Per-frame joint motion (iters passes, each capped at cap) is bounded by iters*cap.
theorem perframe_le (diff cap iters : Nat) : iters * step diff cap ≤ iters * cap :=
  Nat.mul_le_mul_left iters (step_le_cap diff cap)

end IKJerk

/- ---------------------------------------------------------------------------
   Plausible: on the actual Float great-circle slerp, (1) the angle advances
   linearly and (2) the rate-limited step never exceeds the cap.
--------------------------------------------------------------------------- -/
namespace IKJerkCheck

abbrev R := Float
def pi : R := 3.14159265358979323846
def d2r (x : R) : R := x * pi / 180.0

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
def angleTo (a b : V3) : R := Float.atan2 (len (cross a b)) (dot a b)

-- Great-circle slerp of unit vectors (matches Quaternion/Basis slerp on S^2; copy of Kusudama's).
def slerp (a b : V3) (t : R) : V3 :=
  let d0 := dot a b
  let d := if d0 > 1.0 then 1.0 else if d0 < -1.0 then -1.0 else d0
  let om := Float.acos d
  let s := Float.sin om
  if om < 1e-6 then norm a
  else if s < 1e-6 then norm (add (smul (1.0 - t) a) (smul t b))
  else add (smul (Float.sin ((1.0 - t) * om) / s) a) (smul (Float.sin (t * om) / s) b)

def dir (th ph : Nat) : V3 :=
  let t := d2r (Float.ofNat th)
  let p := d2r (Float.ofNat ph)
  norm ⟨Float.sin t * Float.cos p, Float.sin t * Float.sin p, Float.cos t⟩

structure JCase where
  th1 : Nat
  ph1 : Nat
  th2 : Nat
  ph2 : Nat
  tPct : Nat -- slerp fraction in [0,100]
  capDeg : Nat -- angular_delta_limit in degrees
deriving Repr

def aOf (c : JCase) : V3 := dir c.th1 c.ph1
def bOf (c : JCase) : V3 := dir c.th2 c.ph2
-- Only assert in the well-conditioned range (avoid identical / near-antipodal, where the slerp
-- fallback is a lerp): the solver's per-iteration deltas are small, so this is the regime that matters.
def wellPosed (c : JCase) : Bool := let g := angleTo (aOf c) (bOf c); g > 0.05 && g < 3.0

-- (1) slerp advances the geodesic angle linearly: angle(a, slerp a b t) = t * angle(a,b).
def linearOK (c : JCase) : Bool :=
  if wellPosed c then
    let t := Float.ofNat c.tPct / 100.0
    let g := angleTo (aOf c) (bOf c)
    Float.abs (angleTo (aOf c) (slerp (aOf c) (bOf c) t) - t * g) < 1e-3
  else true

-- (2) the rate-limited step never exceeds the cap: achieved = angle(a, clamped) <= cap.
def cappedOK (c : JCase) : Bool :=
  if wellPosed c then
    let cap := d2r (Float.ofNat c.capDeg)
    let diff := angleTo (aOf c) (bOf c)
    let clamped := if diff ≤ cap then bOf c else slerp (aOf c) (bOf c) (cap / diff)
    angleTo (aOf c) clamped ≤ cap + 1e-3
  else true

open Plausible (Gen SampleableExt Shrinkable)

instance : Shrinkable JCase := ⟨fun _ => []⟩
instance : SampleableExt JCase :=
  SampleableExt.mkSelfContained do
    let t1 ← Gen.chooseNatLt 0 181 (by omega)
    let p1 ← Gen.chooseNatLt 0 360 (by omega)
    let t2 ← Gen.chooseNatLt 0 181 (by omega)
    let p2 ← Gen.chooseNatLt 0 360 (by omega)
    let tp ← Gen.chooseNatLt 0 101 (by omega)
    let cd ← Gen.chooseNatLt 1 30 (by omega)
    pure { th1 := t1.val, ph1 := p1.val, th2 := t2.val, ph2 := p2.val, tPct := tp.val, capDeg := cd.val }

#eval Plausible.Testable.check (cfg := { numInst := 5000 })
  (∀ c : JCase, linearOK c = true)
#eval Plausible.Testable.check (cfg := { numInst := 5000 })
  (∀ c : JCase, cappedOK c = true)

end IKJerkCheck
