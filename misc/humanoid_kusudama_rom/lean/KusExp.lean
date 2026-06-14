/-
  Experiment: find what kills the equidistant-cone teleport across ALL 1..30-cone arrangements.
  Compares three projections via Plausible's exhaustive search of random configs + slerped tracks:
    (A) current: softmin one-step Karcher mean ANCHORED at the nearest candidate.
    (B) anchor-free: softmin weighted average of the candidates in ambient R3, renormalized.
    (C) current but with a WIDER cushion (does the cushion internally help?).
  advWorst = worst output-vs-input amplification (deg) over the track; <12 deg = no teleport.
-/
import Kusudama
import Plausible

open Kusudama

namespace KusExp

-- (B) anchor-free ambient blend: no anchor, so no discrete switch to jump across.
def projFree (cones : List Cone) (p : V3) (temperature : R) : V3 :=
  let cd := cones.map (fun k => let q := softCone p k; (q, V3.angleTo p q))
  let dmin := cd.foldl (fun m x => if x.2 < m then x.2 else m) 1e30
  if dmin < 1e-5 then p else
    let w := fun (d : R) => Float.exp (-(d - dmin) / temperature)
    let num := cd.foldl (fun (s : V3) x => V3.add s (V3.smul (w x.2) x.1)) ⟨0, 0, 0⟩
    let den := cd.foldl (fun (s : R) x => s + w x.2) 0.0
    if den ≤ 1e-30 then p else V3.norm (V3.smul (1.0 / den) num)

-- (C) wider cushion: softCone with a band parameter instead of the fixed SOFT_BAND.
def softConeBand (band : R) (p : V3) (k : Cone) : V3 :=
  let th := V3.angleTo p k.c
  let thSat := if th > k.r - band then k.r - band * Float.exp (-(th - (k.r - band)) / band) else th
  let perp0 := V3.sub p (V3.smul (V3.dot p k.c) k.c)
  let perp := V3.norm (if V3.isZero perp0 then V3.anyPerp k.c else perp0)
  V3.norm (V3.add (V3.smul (Float.cos thSat) k.c) (V3.smul (Float.sin thSat) perp))

def projAnchorBand (band : R) (cones : List Cone) (p : V3) (temperature : R) : V3 :=
  let cd := cones.map (fun k => let q := softConeBand band p k; (q, V3.angleTo p q))
  let dmin := cd.foldl (fun m x => if x.2 < m then x.2 else m) 1e30
  if dmin < 1e-5 then p else
    let anchor := (cd.foldl (fun (best : V3 × R) x => if x.2 < best.2 then x else best) (⟨0, 1, 0⟩, 1e30)).1
    let w := fun (d : R) => Float.exp (-(d - dmin) / temperature)
    let num := cd.foldl (fun (s : V3) x => V3.add s (V3.smul (w x.2) (logMap anchor x.1))) ⟨0, 0, 0⟩
    let den := cd.foldl (fun (s : R) x => s + w x.2) 0.0
    if den ≤ 1e-30 then p else expMap anchor (V3.smul (1.0 / den) num)

-- Worst amplification over the config's slerped keyframe track, given a projection function.
def worstWith (proj : List Cone → V3 → R → V3) (temp : R) (a : AdvCfg) : R :=
  match buildPath a.keys a.sub with
  | [] => 0.0
  | in0 :: rest =>
    let res := rest.foldl
      (fun (acc : R × V3 × V3) inI =>
        let outI := proj a.cones inI temp
        let amp := if isFin outI then radToDeg (V3.angleTo acc.2.2 outI - V3.angleTo acc.2.1 inI) else 1e9
        (fmax acc.1 amp, inI, outI))
      ((-1e9 : R), in0, proj a.cones in0 temp)
    res.1

-- (D) IMPLICIT FIELD: the allowed region is the smooth sublevel set of an inside-margin field
-- m(d) = softmax_i (r_i - angle(d, c_i)) (>0 inside, smoothed by beta). Project an outside point
-- onto the m=0 level set by a few geodesic Newton steps along grad m. The level set is C-infinity,
-- so the projection is continuous everywhere -- no medial-axis switch to teleport across.
def projImplicit (beta : R) (cones : List Cone) (d0 : V3) (_temp : R) : V3 := Id.run do
  let mut d := V3.norm d0
  for _ in [0:10] do
    let terms := cones.map (fun k => beta * (k.r - V3.angleTo d k.c))
    let mmax := terms.foldl fmax (-1e30)
    let exps := terms.map (fun t => Float.exp (t - mmax))
    let z := exps.foldl (· + ·) 0.0
    let margin := mmax / beta + (Float.log z) / beta -- ~ softmax_i (r_i - angle_i)
    if margin ≥ -1e-6 then
      return d -- inside / on the boundary
    let grad := (cones.zip exps).foldl (fun (s : V3) kc =>
      let t := V3.sub kc.1.c (V3.smul (V3.dot kc.1.c d) d) -- unit tangent at d toward the cone center
      V3.add s (V3.smul (kc.2 / z) (V3.norm t))) ⟨0, 0, 0⟩
    let gl := V3.len grad
    if gl < 1e-9 then
      return d
    let dir := V3.smul (1.0 / gl) grad
    let step := -margin -- margin < 0 here, so a positive geodesic step toward the region
    d := V3.norm (V3.add (V3.smul (Float.cos step) d) (V3.smul (Float.sin step) dir))
  return d

-- Damped Newton on the smooth level set: clamp each geodesic step to stepMax so far-outside
-- points converge instead of overshooting; iterate `iters` times.
def projImpl2 (beta stepMax : R) (iters : Nat) (cones : List Cone) (d0 : V3) (_temp : R) : V3 := Id.run do
  let mut d := V3.norm d0
  for _ in [0:iters] do
    let terms := cones.map (fun k => beta * (k.r - V3.angleTo d k.c))
    let mmax := terms.foldl fmax (-1e30)
    let exps := terms.map (fun t => Float.exp (t - mmax))
    let z := exps.foldl (· + ·) 0.0
    let margin := mmax / beta + (Float.log z) / beta
    if margin ≥ -1e-6 then
      return d
    let grad := (cones.zip exps).foldl (fun (s : V3) kc =>
      let t := V3.sub kc.1.c (V3.smul (V3.dot kc.1.c d) d)
      V3.add s (V3.smul (kc.2 / z) (V3.norm t))) ⟨0, 0, 0⟩
    let gl := V3.len grad
    if gl < 1e-9 then
      return d
    let dir := V3.smul (1.0 / gl) grad
    let raw := -margin
    let step := if raw > stepMax then stepMax else raw
    d := V3.norm (V3.add (V3.smul (Float.cos step) d) (V3.smul (Float.sin step) dir))
  return d

-- CONNECTED-TUBE (capsule chain) representation: the region is the tube swept along the polyline
-- of cone centers with interpolated radius -- a single CONNECTED region, so the blend target lives
-- INSIDE it (no overshoot between disjoint cones).
def arcNearest (d c1 c2 : V3) : V3 :=
  let nrm0 := V3.cross c1 c2
  if V3.isZero nrm0 then (if V3.angleTo d c1 ≤ V3.angleTo d c2 then c1 else c2)
  else
    let nrm := V3.norm nrm0
    let inplane := V3.norm (V3.sub d (V3.smul (V3.dot d nrm) nrm))
    let b1 := V3.dot (V3.cross c1 inplane) nrm ≥ 0
    let b2 := V3.dot (V3.cross inplane c2) nrm ≥ 0
    if b1 && b2 then inplane else (if V3.angleTo d c1 ≤ V3.angleTo d c2 then c1 else c2)

-- inside-margin for one tube segment: r_interp(d) - angle(d, nearest point on the arc). >0 inside.
def segMargin (d : V3) (k1 k2 : Cone) : R :=
  let np := arcNearest d k1.c k2.c
  let total := V3.angleTo k1.c k2.c
  let t := if total < 1e-6 then 0.0 else (V3.angleTo k1.c np) / total
  let tc := if t < 0.0 then 0.0 else if t > 1.0 then 1.0 else t
  (k1.r + (k2.r - k1.r) * tc) - V3.angleTo d np

def segMarginsAll (cones : List Cone) (d : V3) : List (R × V3) :=
  match cones with
  | [] => []
  | [k] => [(k.r - V3.angleTo d k.c, k.c)]
  | _ => (cones.zip (cones.drop 1)).map (fun pr => (segMargin d pr.1 pr.2, arcNearest d pr.1.c pr.2.c))

-- Damped Newton onto the smooth tube level set: margin = softmax over segments of segMargin.
def projTube (beta stepMax : R) (iters : Nat) (cones : List Cone) (d0 : V3) (_t : R) : V3 := Id.run do
  let mut d := V3.norm d0
  for _ in [0:iters] do
    let sm := segMarginsAll cones d
    let terms := sm.map (fun x => beta * x.1)
    let mmax := terms.foldl fmax (-1e30)
    let exps := terms.map (fun t => Float.exp (t - mmax))
    let z := exps.foldl (· + ·) 0.0
    let margin := mmax / beta + (Float.log z) / beta
    if margin ≥ -1e-6 then
      return d
    let grad := (sm.zip exps).foldl (fun (s : V3) xe =>
      let tgt := V3.sub xe.1.2 (V3.smul (V3.dot xe.1.2 d) d) -- tangent at d toward this segment's nearest pt
      V3.add s (V3.smul (xe.2 / z) (V3.norm tgt))) ⟨0, 0, 0⟩
    let gl := V3.len grad
    if gl < 1e-9 then
      return d
    let dir := V3.smul (1.0 / gl) grad
    let raw := -margin
    let step := if raw > stepMax then stepMax else raw
    d := V3.norm (V3.add (V3.smul (Float.cos step) d) (V3.smul (Float.sin step) dir))
  return d

-- "outside the TUBE" (not just the nearest cone): max over the track of -tubeMargin.
def worstOutsideTube (proj : List Cone → V3 → R → V3) (a : AdvCfg) : R :=
  (buildPath a.keys a.sub).foldl (fun mm inI =>
    let o := proj a.cones inI 0.22
    let m := (segMarginsAll a.cones o).foldl (fun b x => fmax b x.1) (-1e30)
    fmax mm (radToDeg (-m))) (-1e30)

-- THE ORACLE from the existence proof: a basepoint-cone retraction. Pick an interior anchor b
-- (centroid of cone centers). For d inside the connected region, identity. For d outside, walk the
-- geodesic ray from b through d to where it exits the region (q on the boundary), then slide from q
-- toward b as d gets farther behind -- continuous everywhere (the antipode of b maps to b), identity
-- on the region, output always inside. Star-shaped-from-b connected regions => no teleport.
def centroidDir (cones : List Cone) : V3 :=
  V3.norm (cones.foldl (fun s k => V3.add s k.c) ⟨0, 0, 0⟩)
def tubeMargin (cones : List Cone) (d : V3) : R :=
  (segMarginsAll cones d).foldl (fun m x => fmax m x.1) (-1e30)
def coneAt (b tangent : V3) (t : R) : V3 := V3.add (V3.smul (Float.cos t) b) (V3.smul (Float.sin t) tangent)
def rayBoundaryAngle (cones : List Cone) (b tangent : V3) : R := Id.run do
  let mut lo := 0.0
  let mut hi := pi
  for _ in [0:40] do
    let mid := 0.5 * (lo + hi)
    if tubeMargin cones (V3.norm (coneAt b tangent mid)) ≥ 0.0 then lo := mid else hi := mid
  return lo
def smoothstep (x : R) : R := let c := if x < 0.0 then 0.0 else if x > 1.0 then 1.0 else x; c * c * (3.0 - 2.0 * c)
def projConeRetract (cones : List Cone) (d0 : V3) (_t : R) : V3 :=
  let b := centroidDir cones
  let d := V3.norm d0
  let dot := V3.dot b d
  let tangent0 := V3.sub d (V3.smul dot b)
  if V3.isZero tangent0 then (if dot > 0.0 then d else b)
  else
    let tangent := V3.norm tangent0
    let beta := V3.angleTo b d
    let alpha := rayBoundaryAngle cones b tangent
    if beta ≤ alpha + 1e-9 then d
    else
      let q := V3.norm (coneAt b tangent alpha)
      V3.slerp q b (smoothstep ((beta - alpha) / (pi - alpha + 1e-9)))

def okImplicit (a : AdvCfg) : Bool := worstWith (projImplicit 12.0) 0.22 a < 12.0
def okImplicitSoft (a : AdvCfg) : Bool := worstWith (projImplicit 6.0) 0.22 a < 12.0

def okCurrent (a : AdvCfg) : Bool := worstWith (continuousProject) 0.22 a < 12.0
def okFree (a : AdvCfg) : Bool := worstWith (projFree) 0.22 a < 12.0
def okFreeHot (a : AdvCfg) : Bool := worstWith (projFree) 0.5 a < 12.0
def okWideCushion (a : AdvCfg) : Bool := worstWith (projAnchorBand 0.25) 0.22 a < 12.0

-- Deterministic hard configs: fibonacci cones (n, radius) with a wide 6-axis keyframe track.
def axisKeys : List V3 := [⟨1,0,0⟩, ⟨0,1,0⟩, ⟨0,0,1⟩, ⟨-1,0,0⟩, ⟨0,-1,0⟩, ⟨0,0,-1⟩, ⟨0.577,0.577,0.577⟩]
def detConfigs : List AdvCfg := Id.run do
  let mut out : List AdvCfg := []
  for n in [3, 5, 8, 12, 20, 30] do
    for rdeg in [12, 25, 45] do
      out := out ++ [{ cones := fibCones n (Float.ofNat rdeg * pi / 180.0), keys := axisKeys, sub := 48 }]
  return out
def maxWorstT (proj : List Cone → V3 → R → V3) (temp : R) : R :=
  detConfigs.foldl (fun m a => fmax m (worstWith proj temp a)) 0.0

-- anchor-free, temperature sweep (the blend width). Higher temp = smoother = lower amplification.
#eval s!"current anchor-based (t=0.22):  {maxWorstT continuousProject 0.22}"
#eval s!"anchor-free t=0.22:  {maxWorstT projFree 0.22}"
#eval s!"anchor-free t=0.35:  {maxWorstT projFree 0.35}"
#eval s!"anchor-free t=0.50:  {maxWorstT projFree 0.50}"
#eval s!"anchor-free t=0.70:  {maxWorstT projFree 0.70}"
#eval s!"anchor-free t=1.00:  {maxWorstT projFree 1.00}"
#eval s!"anchor-free t=1.50:  {maxWorstT projFree 1.50}"
-- also: does the maximum constraint excursion (how far OUTSIDE the cones the output lands) grow
-- with temperature? (the smoothness/accuracy trade-off). Report worst outside-margin in deg.
def worstOutside (proj : List Cone → V3 → R → V3) (temp : R) : R :=
  detConfigs.foldl (fun m a =>
    (buildPath a.keys a.sub).foldl (fun mm inI =>
      let o := proj a.cones inI temp
      -- distance outside the nearest cone (negative inside): min_i (angle(o,c_i) - r_i)
      let outside := a.cones.foldl (fun best k => let v := V3.angleTo o k.c - k.r; if v < best then v else best) 1e30
      fmax mm (radToDeg outside)) m) (-1e30)
#eval s!"anchor-free t=0.50 worst OUTSIDE (deg, <=0 ok): {worstOutside projFree 0.50}"
-- DAMPED IMPLICIT (the smooth level set): report both amplification AND outside-violation, sweeping
-- beta (boundary tightness) at a clamped step and 24 iterations.
-- Keyframe interpolation modes on a timeline: LINEAR (nlerp of positions) and CUBIC (Catmull-Rom),
-- as well as the SLERP baseline. These feed the solver the same non-geodesic input an AnimationPlayer
-- produces from value keyframes.
def lerpN (a b : V3) (t : R) : V3 := V3.norm (V3.add (V3.smul (1.0 - t) a) (V3.smul t b))
def catmull (p0 p1 p2 p3 : V3) (t : R) : V3 :=
  let t2 := t * t
  let t3 := t2 * t
  let f := fun (a b c d : R) => 0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)
  V3.norm ⟨f p0.x p1.x p2.x p3.x, f p0.y p1.y p2.y p3.y, f p0.z p1.z p2.z p3.z⟩
def nth (l : List V3) (i : Int) : V3 :=
  let n := l.length
  if n == 0 then ⟨0, 1, 0⟩ else l.getD (((i % n + n) % n).toNat) ⟨0, 1, 0⟩
def buildLinear (keys : List V3) (sub : Nat) : List V3 :=
  let s := if sub < 2 then 2 else sub
  ((keys.zip (keys.drop 1)).foldl (fun acc pr => acc ++ (List.range s).map (fun i => lerpN pr.1 pr.2 (Float.ofNat i / Float.ofNat s))) []) ++ (match keys.getLast? with | some l => [l] | none => [])
-- STEPWISE / NEAREST: hold each keyframe, then jump at the next key (Godot interp = NEAREST). The
-- jump itself is the animation's, not the constraint's; the test is whether the projection AMPLIFIES
-- it (output jumps more than the target did) -> amplification > 0.
def buildStep (keys : List V3) (sub : Nat) : List V3 :=
  keys.foldl (fun acc k => acc ++ List.replicate (if sub < 2 then 2 else sub) k) []
def buildCubic (keys : List V3) (sub : Nat) : List V3 :=
  let s := if sub < 2 then 2 else sub
  let n := keys.length
  (List.range (n - 1)).foldl (fun acc seg =>
    let si := Int.ofNat seg
    acc ++ (List.range s).map (fun i =>
      catmull (nth keys (si - 1)) (nth keys si) (nth keys (si + 1)) (nth keys (si + 2)) (Float.ofNat i / Float.ofNat s))) []

-- worst amplification over a config using a chosen path builder + projection.
def worstPath (build : List V3 → Nat → List V3) (proj : List Cone → V3 → R → V3) (temp : R) (a : AdvCfg) : R :=
  match build a.keys a.sub with
  | [] => 0.0
  | in0 :: rest =>
    (rest.foldl (fun (acc : R × V3 × V3) inI =>
      let outI := proj a.cones inI temp
      let amp := if isFin outI then radToDeg (V3.angleTo acc.2.2 outI - V3.angleTo acc.2.1 inI) else 1e9
      (fmax acc.1 amp, inI, outI)) ((-1e9 : R), in0, proj a.cones in0 temp)).1
def maxPath (build : List V3 → Nat → List V3) (proj : List Cone → V3 → R → V3) (temp : R) : R :=
  detConfigs.foldl (fun m a => fmax m (worstPath build proj temp a)) 0.0
def maxOutTube (proj : List Cone → V3 → R → V3) : R :=
  detConfigs.foldl (fun m a => fmax m (worstOutsideTube proj a)) (-1e30)

-- FULL MATRIX: {current, anchor-free, connected TUBE} x {slerp, linear, cubic}, 1..30 cones.
#eval "proj            slerp_amp linear_amp cubic_amp"
#eval s!"current        {maxPath buildPath continuousProject 0.22}  {maxPath buildLinear continuousProject 0.22}  {maxPath buildCubic continuousProject 0.22}"
#eval s!"anchor-free    {maxPath buildPath projFree 0.30}  {maxPath buildLinear projFree 0.30}  {maxPath buildCubic projFree 0.30}"
#eval s!"TUBE b40       {maxPath buildPath (projTube 40.0 0.25 24) 0.22}  {maxPath buildLinear (projTube 40.0 0.25 24) 0.22}  {maxPath buildCubic (projTube 40.0 0.25 24) 0.22}"
#eval s!"TUBE outside-violation (deg, <=0 ok): {maxOutTube (projTube 40.0 0.25 24)}"
#eval s!"current outside-violation (deg): {maxOutTube continuousProject}"

-- DECISIVE: geodesically-CONVEX arrangements (cones clustered + overlapping within a small cap,
-- so the union is convex). Nearest-point projection onto a convex spherical region has NO interior
-- medial axis -> it is continuous -> NO teleport. If amp ~ 0 here, the criterion is: convex => safe.
def convexConfigs : List AdvCfg := Id.run do
  let mut out : List AdvCfg := []
  for n in [2, 3, 5, 8, 15, 30] do
    let cs := (List.range n).map (fun i =>
      let a := tau * Float.ofNat i / Float.ofNat n
      (⟨sphereDir (0.35 + 0.12 * Float.sin a) a, 28.0 * pi / 180.0⟩ : Cone)) -- ring near +Z, r=28deg => overlap
    out := out ++ [{ cones := cs, keys := axisKeys, sub := 48 }]
  return out
def maxConvex (build : List V3 → Nat → List V3) (proj : List Cone → V3 → R → V3) (temp : R) : R :=
  convexConfigs.foldl (fun m a => fmax m (worstPath build proj temp a)) 0.0
#eval "=== CONNECTED (clustered) arrangements: current vs the ORACLE retraction ==="
#eval s!"current  slerp:{maxConvex buildPath continuousProject 0.22}  linear:{maxConvex buildLinear continuousProject 0.22}  cubic:{maxConvex buildCubic continuousProject 0.22}"
#eval s!"ORACLE   slerp:{maxConvex buildPath projConeRetract 0.22}  linear:{maxConvex buildLinear projConeRetract 0.22}  cubic:{maxConvex buildCubic projConeRetract 0.22}  step:{maxConvex buildStep projConeRetract 0.22}"
#eval s!"current  step amp (amplifies the keyframe jump): {maxConvex buildStep continuousProject 0.22}"
#eval s!"ORACLE outside-violation (deg, <=0 ok): {convexConfigs.foldl (fun m a => fmax m (worstOutsideTube projConeRetract a)) (-1e30)}"

end KusExp
