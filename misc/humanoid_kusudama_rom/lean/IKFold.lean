/-
  Forward-kinematics fold equivalence for the SwingTwistIK3D solve speedup.

  scene/3d/swing_twist_ik_3d.cpp used to recompute the WHOLE skeleton's global
  transforms (`gp[o] = gp[parent] * pose`) before processing EVERY bone, inside
  the per-iteration sweep -- O(iters * joints * bones), quadratic in skeleton
  size. The speedup keeps `gp` consistent incrementally: one full FK pass, then
  after editing one bone's local pose, refresh ONLY that bone's subtree.

  This file proves that is exact -- same global transforms as full recompute --
  which is why the optimized solve is bit-identical to the old one and all the
  existing determinism / convergence / clamp tests still pass.

  Transforms are modelled as the free monoid `List Int` (++ = compose, [] = id);
  composition is associative and non-commutative, like rigid transforms. The
  tree is topological: `par i : Option (Fin i)`, so every parent index is < i.

  Core lemma (`fk_unchanged_outside`): editing bone e's local pose does not
  change the global of any bone NOT in e's subtree. Hence refreshing only the
  subtree reproduces full FK. Plausible cross-checks the full equivalence on
  random trees, the same proof+sample style as Kusudama.lean / verify.lean.
-/
import Plausible

namespace IKFold

abbrev T := List Int -- transform = free monoid; (++) composes, [] is identity.

-- Topological parent map: bone i's parent (if any) has index < i.
abbrev Tree := (i : Nat) → Option (Fin i)

-- Forward kinematics: global of i = global(parent i) composed with local i.
def fk (par : Tree) (loc : Nat → T) (i : Nat) : T :=
  match par i with
  | none => loc i
  | some p => fk par loc p.val ++ loc i
termination_by i
decreasing_by exact p.isLt

-- e is an ancestor of j (reflexively: e is in its own subtree).
def isAnc (par : Tree) (e j : Nat) : Bool :=
  if e = j then true
  else
    match par j with
    | none => false
    | some p => isAnc par e p.val
termination_by j
decreasing_by exact p.isLt

-- Edit bone e's local pose to v.
def edit (loc : Nat → T) (e : Nat) (v : T) : Nat → T :=
  fun k => if k = e then v else loc k

-- HEART: a bone outside e's subtree is untouched by editing e. By strong
-- induction along the parent chain -- e is not j and not an ancestor of par j.
theorem fk_unchanged_outside (par : Tree) (loc : Nat → T) (e : Nat) (v : T) :
    ∀ j, isAnc par e j = false → fk par (edit loc e v) j = fk par loc j := by
  intro j
  induction j using Nat.strongRecOn with
  | ind j IH =>
    intro h
    unfold fk
    -- From isAnc: e ≠ j, and (if j has a parent p) e is not an ancestor of p.
    have hne : e ≠ j := by
      intro he; rw [isAnc] at h; simp [he] at h
    cases hp : par j with
    | none =>
      simp only [edit]
      rw [if_neg (Ne.symm hne)]
    | some p =>
      have hanc : isAnc par e p.val = false := by
        rw [isAnc] at h; rw [if_neg hne, hp] at h; exact h
      have := IH p.val p.isLt hanc
      simp only [edit, this]
      rw [if_neg (Ne.symm hne)]

-- A bone IN e's subtree: its global is just full FK of the edited poses (by
-- definition fk already folds the whole chain), so a subtree-only refresh that
-- recomputes fk on the subtree is correct there too. Combined with the lemma
-- above, refreshing exactly the subtree reproduces full FK everywhere:
def refreshed (par : Tree) (loc : Nat → T) (e : Nat) (v : T) (j : Nat) : T :=
  if isAnc par e j then fk par (edit loc e v) j else fk par loc j

theorem refresh_eq_full (par : Tree) (loc : Nat → T) (e : Nat) (v : T) :
    ∀ j, refreshed par loc e v j = fk par (edit loc e v) j := by
  intro j
  unfold refreshed
  by_cases hc : isAnc par e j
  · rw [if_pos hc]
  · rw [if_neg hc]
    have : isAnc par e j = false := by simpa using hc
    exact (fk_unchanged_outside par loc e v j this).symm

end IKFold

/- ---------------------------------------------------------------------------
   Plausible cross-check on random list-encoded trees (executable model),
   mirroring the C++ subtree-refresh against a full recompute.
--------------------------------------------------------------------------- -/
namespace IKFoldCheck

abbrev T := List Int

-- A tree of n bones, all fields Repr-able so Plausible can print counterexamples.
-- parents[i] < i (a real parent) or = i (bone i is parentless); loc i = [locVals[i]].
structure Scene where
  n : Nat
  parents : List Nat
  locVals : List Nat
  e : Nat -- edited bone
  vVal : Nat -- new local pose value (made distinct so an edit is observable)
deriving Repr

def parentOf (s : Scene) (i : Nat) : Nat := s.parents.getD i i
def baseLoc (s : Scene) (i : Nat) : T := [Int.ofNat (s.locVals.getD i 0)]
def editL (s : Scene) : Nat → T :=
  fun k => if k = s.e then [Int.ofNat s.vVal + 100] else baseLoc s k

-- Bounded FK by an explicit fuel (chain length ≤ n); exact for valid topo trees.
def fkF (s : Scene) (loc : Nat → T) : Nat → Nat → T
  | 0, _ => []
  | f + 1, i =>
    let p := parentOf s i
    if p < i then fkF s loc f p ++ loc i else loc i

-- ancestor (reflexive) with fuel.
def ancF (s : Scene) : Nat → Nat → Nat → Bool
  | 0, _, _ => false
  | f + 1, a, j =>
    if a = j then true
    else let p := parentOf s j; if p < j then ancF s f a p else false

-- Incremental: subtree of e gets edited FK, every other bone keeps old FK.
def incr (s : Scene) (j : Nat) : T :=
  if ancF s (s.n + 1) s.e j then fkF s (editL s) (s.n + 1) j
  else fkF s (baseLoc s) (s.n + 1) j

-- Reference: full recompute of the edited poses.
def full (s : Scene) (j : Nat) : T := fkF s (editL s) (s.n + 1) j

def agrees (s : Scene) : Bool := (List.range s.n).all (fun j => incr s j == full s j)

open Plausible (Gen SampleableExt Shrinkable)

instance : Shrinkable Scene := ⟨fun _ => []⟩
instance : SampleableExt Scene :=
  SampleableExt.mkSelfContained do
    let nm ← Gen.chooseNatLt 1 9 (by omega)
    let n := nm.val
    let pr ← (List.range n).mapM (fun i => do
      let r ← Gen.chooseNatLt 0 8 (by omega)
      pure (if i = 0 then 0 else r.val % i)) -- parent i < i; bone 0 parentless
    let lc ← (List.range n).mapM (fun _ => do
      let a ← Gen.chooseNatLt 0 5 (by omega)
      pure a.val)
    let em ← Gen.chooseNatLt 0 8 (by omega)
    let vv ← Gen.chooseNatLt 0 5 (by omega)
    pure { n := n, parents := pr, locVals := lc, e := em.val % n, vVal := vv.val }

#eval Plausible.Testable.check (cfg := { numInst := 5000 })
  (∀ s : Scene, agrees s = true)

end IKFoldCheck
