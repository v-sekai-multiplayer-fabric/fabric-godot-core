/-
  WristRom.lean — fit the anatomical wrist ROM region on the unit sphere with the
  MINIMAL number of Kusudama swing cones, and emit the bake parameters.

  Anatomical target (neutral = forearm/forward axis):
    flexion ≈ 70°, extension ≈ 70°  (major axis)
    radial dev ≈ 20°, ulnar dev ≈ 30°  (minor axis, asymmetric)

  The asymmetric minor axis (20 vs 30) is exactly a 5° center offset toward ulnar with a
  25° symmetric half-width; the major axis is symmetric ±70°. So the ROM is a spherical
  ELLIPSE centered at tangent (x0, 0), semi-axes (Bx, Yy).

  The Kusudama swing region for a cone chain is the geodesic r-neighborhood of the polyline
  through the cone centers (caps + tangent bands). We fit that capsule-chain to the ellipse
  and search N = 1..30 for the minimal count whose Jaccard/IoU stops improving.

  forward = +Z (matches Kusudama.lean). Tangent plane at +Z is XY:
    tangent y  = flexion(+)/extension(-)
    tangent x  = radial(+)/ulnar(-)
-/
import Kusudama
import Plausible

namespace Kusudama
open V3
open Plausible (Gen SampleableExt Shrinkable)

def d2r (x : R) : R := x * pi / 180.0

-- anatomical limits (deg)
def A_flex  : R := 70.0
def A_ext   : R := 70.0
def A_rad   : R := 20.0
def A_ulnar : R := 30.0

-- centered spherical-ellipse params (radians)
def x0 : R := d2r ((A_rad - A_ulnar) / 2.0)     -- -5°  (center toward ulnar)
def Bx : R := d2r ((A_rad + A_ulnar) / 2.0)     --  25°  minor half-width
def Yy : R := d2r ((A_flex + A_ext) / 2.0)      --  70°  major half-width

/-- Ellipse "level": ≤ 1 inside the ROM, = 1 on its boundary. -/
def ellipseLevel (d : V3) : R :=
  let t := logMap fwd d
  let a := (t.x - x0) / Bx
  let b := t.y / Yy
  a*a + b*b

def inEllipse (d : V3) : Bool := ellipseLevel d ≤ 1.0

/-- Cone center from a tangent offset (tx,ty) at +Z. -/
def centerTan (tx ty : R) : V3 := expMap fwd ⟨tx, ty, 0.0⟩

/-- A tapered capsule chain along the ellipse major axis: N centers on the medial line
    x = x0, y spanning ±0.92·Yy, radius = local minor half-width (≥ 8° Kusudama floor). -/
def buildFan (N : Nat) : List Cone := Id.run do
  let ymax := Yy * 0.92
  let rfloor := d2r 8.0
  let mut out : List Cone := []
  for i in [0:N] do
    let yi := if N ≤ 1 then 0.0
              else -ymax + 2.0*ymax * Float.ofNat i / Float.ofNat (N-1)
    let q := yi / Yy
    let ri := fmax rfloor (Bx * Float.sqrt (fmax 0.0 (1.0 - q*q)))
    out := out ++ [⟨centerTan x0 yi, ri⟩]
  return out

/-- Geodesic distance from `p` to the minor great-circle arc a→b, with the
    projection parameter t∈[0,1] (clamped to the nearer endpoint when off-arc). -/
def distSeg (p a b : V3) : R × R :=
  let ab := V3.angleTo a b
  if ab < 1e-7 then (V3.angleTo p a, 0.0)
  else
    let n := V3.norm (V3.cross a b)
    let dGC := fabs (pi/2.0 - V3.angleTo p n)          -- distance to the great circle
    let pc := V3.norm (V3.sub p (V3.smul (V3.dot p n) n))
    let apc := V3.angleTo a pc
    let pcb := V3.angleTo pc b
    if fabs (apc + pcb - ab) < 1e-3 then (dGC, apc/ab)  -- foot lands inside the arc
    else if V3.angleTo p a ≤ V3.angleTo p b then (V3.angleTo p a, 0.0)
    else (V3.angleTo p b, 1.0)

def segHit (p : V3) (k1 k2 : Cone) : Bool :=
  let dt := distSeg p k1.c k2.c
  dt.1 ≤ k1.r + dt.2 * (k2.r - k1.r)

/-- Kusudama swing-region membership: inside any cap, or any tangent band. -/
def inFan (cs : List Cone) (p : V3) : Bool :=
  match cs with
  | []  => false
  | [k] => pointInCone p k
  | _   => cs.any (fun k => pointInCone p k)
         || (cs.zip (cs.drop 1)).any (fun pr => segHit p pr.1 pr.2)

/-- Fit quality of an N-cone fan vs the ellipse, by area-weighted spherical sampling.
    Returns (IoU, missFrac, overFrac) where frac is relative to the ellipse area. -/
def fit (N : Nat) : R × R × R := Id.run do
  let cs := buildFan N
  let mut inter := 0.0
  let mut eOnly := 0.0
  let mut fOnly := 0.0
  for ti in [0:101] do                       -- elevation 0..100°
    let th := d2r (Float.ofNat ti)
    let w := Float.sin th
    for pj in [0:180] do                      -- azimuth 0..360° step 2°
      let ph := tau * Float.ofNat pj / 180.0
      let d := sphereDir th ph
      let e := inEllipse d
      let f := inFan cs d
      if e && f then inter := inter + w
      else if e then eOnly := eOnly + w
      else if f then fOnly := fOnly + w
  let eArea := inter + eOnly
  let union := inter + eOnly + fOnly
  return (inter / union, eOnly / eArea, fOnly / eArea)

def pct (x : R) : R := (Float.round (x * 1000.0)) / 10.0

#eval "N   IoU%   miss%(under)   over%(bulge)"
#eval Id.run do
  let mut s := ""
  for N in [1:13] do
    let f := fit N
    s := s ++ s!"{N}  {pct f.1}   {pct f.2.1}   {pct f.2.2}\n"
  return s

/-! ## Chosen configuration + bake parameters -/

def Nbest : Nat := 5

/-- Bake parameters per cone: (swing_x, swing_z, radius_deg) in the make_space frame
    (forward = +Y; flexion → swing_x = X, radial/ulnar → swing_z = Z). -/
def bakeParams : List (R × R × R) := Id.run do
  let mut out : List (R × R × R) := []
  for k in buildFan Nbest do
    -- recover the tangent offset of this center (x0, yi) and map to the +Y bake frame
    let t := logMap fwd k.c
    let tx := t.x        -- radial/ulnar  → swing_z
    let ty := t.y        -- flex/ext      → swing_x
    let ang := Float.sqrt (tx*tx + ty*ty)
    let sx := if ang < 1e-9 then 0.0 else Float.sin ang * ty / ang
    let sz := if ang < 1e-9 then 0.0 else Float.sin ang * tx / ang
    out := out ++ [(sx, sz, radToDeg k.r)]
  return out

#eval s!"chosen N = {Nbest}, fit = {fit Nbest}"
#eval "bake cones (swing_x, swing_z, radius_deg):"
#eval bakeParams

/-! ## Plausible: the fan agrees with the ellipse away from the boundary band. -/

structure WristCase where
  thI : Nat
  phI : Nat
deriving Repr
instance : Shrinkable WristCase := ⟨fun _ => []⟩
instance : SampleableExt WristCase :=
  SampleableExt.mkSelfContained do
    let th ← Gen.chooseNatLt 0 101 (by omega)    -- elevation 0..100°
    let ph ← Gen.chooseNatLt 0 360 (by omega)
    pure { thI := th.val, phI := ph.val }
def wcDir (c : WristCase) : V3 :=
  sphereDir (d2r (Float.ofNat c.thI)) (d2r (Float.ofNat c.phI))

/-- Well INSIDE the ellipse (level ≤ 0.6) ⇒ inside the fan. -/
def wP_coversInterior (c : WristCase) : Bool :=
  let d := wcDir c
  if ellipseLevel d ≤ 0.6 then inFan (buildFan Nbest) d else true

/-- Well OUTSIDE the ellipse (level ≥ 1.6) ⇒ outside the fan (no bulge). -/
def wP_noOuterBulge (c : WristCase) : Bool :=
  let d := wcDir c
  if ellipseLevel d ≥ 1.6 then ! (inFan (buildFan Nbest) d) else true

#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : WristCase, wP_coversInterior c = true)
#eval Plausible.Testable.check (cfg := { numInst := 4000 }) (∀ c : WristCase, wP_noOuterBulge c = true)

end Kusudama
