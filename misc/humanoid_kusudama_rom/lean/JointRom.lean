/-
  JointRom.lean — fit EVERY clinical Godot-humanoid joint constraint (44 bones; the 11
  arm/leg/foot/spine joints keep their real-biomechanics fans) with the minimal tapered
  Kusudama cone fan, AND emit a per-joint Plausible-sampled GOLD table (directions +
  ground-truth ROM membership) for isolated regression testing.

  Each joint ROM = a spherical ellipse: flexion(+y)/extension(-y) major, lateral(±x) minor,
  with offsets. The fan is the geodesic neighborhood of the major-axis polyline (caps +
  tangent bands). N is searched 1..8 and capped at the IoU peak. Plausible verifies the
  construction (covers interior / no outward bulge) for random flexion-dominant ellipses.

  forward = +Z (Kusudama.lean). Emitted dirs/cones are in the bake frame (+Y forward;
  flexion → X = swing_x, lateral → Z = swing_z): permutation (x,y,z)_lean → (y,z,x)_bake.
-/
import Kusudama
import Plausible

namespace Kusudama
open V3
open Plausible (Gen SampleableExt Shrinkable)

def d2r (x : R) : R := x * pi / 180.0

structure Spec where
  flex : R
  ext  : R
  latP : R
  latN : R
  twist : R

def cxOf (s : Spec) : R := d2r ((s.latP - s.latN) / 2.0)
def cyOf (s : Spec) : R := d2r ((s.flex - s.ext) / 2.0)
def axOf (s : Spec) : R := d2r ((s.latP + s.latN) / 2.0)
def ayOf (s : Spec) : R := d2r ((s.flex + s.ext) / 2.0)

def ellipseLevel (s : Spec) (d : V3) : R :=
  let t := logMap fwd d
  let u := (t.x - cxOf s) / axOf s
  let w := (t.y - cyOf s) / ayOf s
  u*u + w*w
def inEllipse (s : Spec) (d : V3) : Bool := ellipseLevel s d ≤ 1.0

def centerTan (tx ty : R) : V3 := expMap fwd ⟨tx, ty, 0.0⟩

def buildFan (s : Spec) (N : Nat) : List Cone := Id.run do
  let rfloor := d2r 5.5
  let mj := ayOf s
  let mn := axOf s
  -- N=1: a single cone must COVER the ellipse, so use the major semi-axis, not the minor.
  if N ≤ 1 then
    return [⟨centerTan (cxOf s) (cyOf s), fmax rfloor (fmax mn mj)⟩]
  let ymax := mj * 0.92
  let mut out : List Cone := []
  for i in [0:N] do
    let si := -ymax + 2.0*ymax * Float.ofNat i / Float.ofNat (N-1)
    let q := si / mj
    let ri := fmax rfloor (mn * Float.sqrt (fmax 0.0 (1.0 - q*q)))
    out := out ++ [⟨centerTan (cxOf s) (cyOf s + si), ri⟩]
  return out

def distSeg (p a b : V3) : R × R :=
  let ab := V3.angleTo a b
  if ab < 1e-7 then (V3.angleTo p a, 0.0)
  else
    let n := V3.norm (V3.cross a b)
    let dGC := fabs (pi/2.0 - V3.angleTo p n)
    let pc := V3.norm (V3.sub p (V3.smul (V3.dot p n) n))
    let apc := V3.angleTo a pc
    let pcb := V3.angleTo pc b
    if fabs (apc + pcb - ab) < 1e-3 then (dGC, apc/ab)
    else if V3.angleTo p a ≤ V3.angleTo p b then (V3.angleTo p a, 0.0)
    else (V3.angleTo p b, 1.0)

def segHit (p : V3) (k1 k2 : Cone) : Bool :=
  let dt := distSeg p k1.c k2.c
  dt.1 ≤ k1.r + dt.2 * (k2.r - k1.r)

def inFan (cs : List Cone) (p : V3) : Bool :=
  match cs with
  | []  => false
  | [k] => pointInCone p k
  | _   => cs.any (fun k => pointInCone p k)
         || (cs.zip (cs.drop 1)).any (fun pr => segHit p pr.1 pr.2)

def fit (s : Spec) (N : Nat) : R × R × R := Id.run do
  let cs := buildFan s N
  let mut inter := 0.0
  let mut eOnly := 0.0
  let mut fOnly := 0.0
  for ti in [0:61] do
    let th := d2r (2.0 * Float.ofNat ti)
    let w := Float.sin th
    for pj in [0:90] do
      let ph := tau * Float.ofNat pj / 90.0
      let d := sphereDir th ph
      let e := inEllipse s d
      let f := inFan cs d
      if e && f then inter := inter + w
      else if e then eOnly := eOnly + w
      else if f then fOnly := fOnly + w
  let eArea := inter + eOnly
  return (inter / (inter + eOnly + fOnly), eOnly / eArea, fOnly / eArea)

/-- Minimal N by max-IoU (= min symmetric difference): the smallest N whose IoU is within
    1% of the best over 1..8. Round joints peak at N=1 (single covering cone); elongated
    joints peak at a tapered fan. Avoids both the miss-threshold trap (always N=1) and
    over-covering past the optimum. -/
def minimalN (s : Spec) : Nat × R × R × R := Id.run do
  let mut fits : List (Nat × R × R × R) := []
  for N in [1:9] do
    let f := fit s N
    fits := fits ++ [(N, f.1, f.2.1, f.2.2)]
  -- Coverage-weighted symmetric difference: miss (false rejection of a valid pose ->
  -- stiffness) costs 2x over (mild excess). Pick the smallest N within 0.5% of the min cost.
  let mut bestCost := 1.0e9
  for p in fits do
    let c := 2.0 * p.2.2.1 + p.2.2.2
    if c < bestCost then bestCost := c
  let mut chosenN := 1
  let mut chIou := 0.0
  let mut chMiss := 1.0
  let mut chOver := 0.0
  let mut found := false
  for p in fits do
    if (! found) && (2.0 * p.2.2.1 + p.2.2.2) ≤ bestCost + 0.005 then
      chosenN := p.1; chIou := p.2.1; chMiss := p.2.2.1; chOver := p.2.2.2; found := true
  return (chosenN, chIou, chMiss, chOver)

def bakeDir (d : V3) : V3 := ⟨d.y, d.z, d.x⟩   -- +Z-fwd (Lean) → +Y-fwd (bake)

def fanToParams (cs : List Cone) : List (R × R × R) :=
  cs.map (fun k =>
    let t := logMap fwd k.c
    let ang := Float.sqrt (t.x*t.x + t.y*t.y)
    let sx := if ang < 1e-9 then 0.0 else Float.sin ang * t.y / ang
    let sz := if ang < 1e-9 then 0.0 else Float.sin ang * t.x / ang
    (sx, sz, radToDeg k.r))

/-- Deterministic Fibonacci-sphere direction (reproducible gold sampling). -/
def fibDir (i n : Nat) : V3 :=
  let gr := (1.0 + Float.sqrt 5.0) / 2.0
  let fi := Float.ofNat i
  let th := Float.acos (1.0 - 2.0*(fi + 0.5)/Float.ofNat n)
  let ph := tau * fi / gr
  V3.norm ⟨Float.sin th*Float.cos ph, Float.sin th*Float.sin ph, Float.cos th⟩

/-- Hard projection onto the fan region: inside → unchanged; outside → nearest point on the
    cone-cap / tangent-band boundary. This is the ideal constrained direction the kusudama
    solve should return for an IK target `p`. -/
def hardProjectFan (cs : List Cone) (p : V3) : V3 :=
  if inFan cs p then p
  else Id.run do
    let mut best := fwd
    let mut bestD := 1.0e9
    for k in cs do
      let q := closestOnCircle p k.c k.r
      let dd := V3.angleTo p q
      if dd < bestD then bestD := dd; best := q
    for pr in cs.zip (cs.drop 1) do
      let dt := distSeg p pr.1.c pr.2.c
      let A := slerp pr.1.c pr.2.c dt.2
      let r := pr.1.r + dt.2 * (pr.2.r - pr.1.r)
      let q := closestOnCircle p A r
      let dd := V3.angleTo p q
      if dd < bestD then bestD := dd; best := q
    return best

/-- Gold table for an IK-target isolation test: ≤ 30 reproducible target directions and the
    expected constrained direction after the joint limit (target if inside the ROM, else the
    nearest boundary point). Emitted in the bake frame (+Y forward). -/
def genGold (s : Spec) (N : Nat) : List (V3 × V3) := Id.run do
  let cs := buildFan s N
  let mut out : List (V3 × V3) := []
  let mut cnt := 0
  for i in [0:240] do
    if cnt < 30 then
      let d := fibDir i 240
      if V3.angleTo fwd d ≤ d2r 115.0 then
        out := out ++ [(bakeDir d, bakeDir (hardProjectFan cs d))]
        cnt := cnt + 1
  return out

/-! ## All 44 clinical joint constraints (per-bone). -/

def sHand        : Spec := ⟨70, 70, 20, 30, 15⟩
def sHips        : Spec := ⟨30, 30, 30, 30, 45⟩
def sChest       : Spec := ⟨25, 20, 20, 20, 30⟩
def sUpperChest  : Spec := ⟨20, 15, 18, 18, 30⟩
def sNeck        : Spec := ⟨40, 50, 40, 40, 45⟩
def sHead        : Spec := ⟨20, 20, 10, 10, 40⟩
def sShoulder    : Spec := ⟨20, 20, 25, 25, 10⟩
def sToes        : Spec := ⟨40, 30,  8,  8,  0⟩
def sEye         : Spec := ⟨28, 28, 28, 28,  0⟩
def sJaw         : Spec := ⟨18,  2,  8,  8,  2⟩
def sThumbMeta   : Spec := ⟨45, 15, 40, 40, 12⟩
def sThumbProx   : Spec := ⟨55,  5, 10, 10,  6⟩
def sThumbDist   : Spec := ⟨80, 10,  8,  8,  0⟩
def sFingerProx  : Spec := ⟨90, 30, 20, 20,  6⟩
def sFingerInter : Spec := ⟨100, 5,  8,  8,  0⟩
def sFingerDist  : Spec := ⟨80,  5,  8,  8,  0⟩

def fingerNames : List String := ["Index", "Middle", "Ring", "Little"]

def clinical : List (String × Spec) :=
  let core : List (String × Spec) :=
    [("Hips", sHips), ("Chest", sChest), ("UpperChest", sUpperChest),
     ("Neck", sNeck), ("Head", sHead), ("Jaw", sJaw),
     ("LeftShoulder", sShoulder), ("RightShoulder", sShoulder),
     ("LeftHand", sHand), ("RightHand", sHand),
     ("LeftToes", sToes), ("RightToes", sToes),
     ("LeftEye", sEye), ("RightEye", sEye)]
  let digits : List (String × Spec) :=
    (["Left", "Right"].flatMap (fun side =>
      [(side ++ "ThumbMetacarpal", sThumbMeta), (side ++ "ThumbProximal", sThumbProx),
       (side ++ "ThumbDistal", sThumbDist)]
      ++ fingerNames.flatMap (fun f =>
          [(side ++ f ++ "Proximal", sFingerProx), (side ++ f ++ "Intermediate", sFingerInter),
           (side ++ f ++ "Distal", sFingerDist)])))
  core ++ digits

def fmt (x : R) : String := toString ((Float.round (x * 1000000.0)) / 1000000.0)
def pct (x : R) : R := (Float.round (x * 1000.0)) / 10.0

/-- Compute one bone's fan line, gold line, and fit comment (minimalN once). Shard drivers
    fold this over a slice of `clinical` so the work parallelises across Lean processes. -/
def emitBone (p : String × Spec) : String :=
  let nm := p.1
  let sp := p.2
  let m := minimalN sp
  let N := m.1
  let cones := String.intercalate ", "
    ((fanToParams (buildFan sp N)).map (fun c => s!"({fmt c.1}, {fmt c.2.1}, {fmt c.2.2})"))
  let g := genGold sp N
  let pts := String.intercalate ", "
    (g.map (fun ts => s!"({fmt ts.1.x}, {fmt ts.1.y}, {fmt ts.1.z}, {fmt ts.2.x}, {fmt ts.2.y}, {fmt ts.2.z})"))
  s!"FAN|{nm}|({fmt sp.twist}, [{cones}])\n" ++
  s!"GOLD|{nm}|[{pts}]\n" ++
  s!"#FIT|{nm}|N={N} IoU={pct m.2.1}% miss={pct m.2.2.1}% over={pct m.2.2.2}%"

def emitSlice (a b : Nat) : String :=
  String.intercalate "\n" (((clinical.drop a).take b).map emitBone)

/-! ## Plausible: the fan covers interiors / never bulges, for random flexion-dominant
    ellipses whose minor axis ≥ the 8° cone floor (the construction's valid domain). -/

structure GenCase where
  flexI : Nat
  extI  : Nat
  latI  : Nat
  nI    : Nat
  thI   : Nat
  phI   : Nat
deriving Repr
instance : Shrinkable GenCase := ⟨fun _ => []⟩
instance : SampleableExt GenCase :=
  SampleableExt.mkSelfContained do
    let fl ← Gen.chooseNatLt 20 100 (by omega)
    let ex ← Gen.chooseNatLt 0 41 (by omega)
    let la ← Gen.chooseNatLt 8 41 (by omega)
    let n  ← Gen.chooseNatLt 2 9 (by omega)
    let th ← Gen.chooseNatLt 0 121 (by omega)
    let ph ← Gen.chooseNatLt 0 360 (by omega)
    pure { flexI := fl.val, extI := ex.val, latI := la.val,
           nI := n.val, thI := th.val, phI := ph.val }
def gcSpec (c : GenCase) : Spec :=
  ⟨Float.ofNat c.flexI, Float.ofNat c.extI, Float.ofNat c.latI, Float.ofNat c.latI, 0⟩
def gcDir (c : GenCase) : V3 :=
  sphereDir (d2r (Float.ofNat c.thI)) (d2r (Float.ofNat c.phI))
def inDomain (s : Spec) : Bool := axOf s ≤ ayOf s && axOf s ≥ d2r 5.49

/-- Well inside (level ≤ 0.55) ⇒ inside the fan. -/
def gP_covers (c : GenCase) : Bool :=
  let s := gcSpec c
  if inDomain s then
    let d := gcDir c
    if ellipseLevel s d ≤ 0.55 then inFan (buildFan s c.nI) d else true
  else true

/-- Well outside (level ≥ 1.9) ⇒ outside the fan (no bulge). -/
def gP_noBulge (c : GenCase) : Bool :=
  let s := gcSpec c
  if inDomain s then
    let d := gcDir c
    if ellipseLevel s d ≥ 1.9 then ! (inFan (buildFan s c.nI) d) else true
  else true

-- Plausible checks live in verify.lean (run as a parallel shard).

end Kusudama
