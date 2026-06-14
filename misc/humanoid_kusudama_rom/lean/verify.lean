import JointRom
open Kusudama
-- Construction soundness (fast, no minimalN): for random in-domain ellipses, a fixed
-- adequate N=6 fan covers the deep interior (level ≤ 0.35) and never bulges far out
-- (level ≥ 2.5). Per-joint coverage of the CHOSEN minimal N is proven separately by the
-- deterministic #FIT miss% / over% table.
def vCovers (c : GenCase) : Bool :=
  let s := gcSpec c
  if inDomain s then
    let d := gcDir c
    if ellipseLevel s d ≤ 0.35 then inFan (buildFan s 6) d else true
  else true
def vNoBulge (c : GenCase) : Bool :=
  let s := gcSpec c
  if inDomain s then
    let d := gcDir c
    if ellipseLevel s d ≥ 2.5 then ! (inFan (buildFan s 6) d) else true
  else true
#eval Plausible.Testable.check (cfg := { numInst := 5000 }) (∀ c : GenCase, vCovers c = true)
#eval Plausible.Testable.check (cfg := { numInst := 5000 }) (∀ c : GenCase, vNoBulge c = true)
