/-
  Correctness of the two SwingTwistIK3D micro-optimizations, proven before the
  C++ is touched (companion to IKFold.lean, which proved the subtree-refresh).

  Both optimizations are the SAME move: a per-bone value that does NOT change
  during the iterative solve is computed once into a table and indexed, instead
  of being recomputed inside the hot loop.

    (A) CSR children adjacency: replace `Skeleton3D::get_bone_children(b)` (which
        allocates a `Vector<int>` per call) with a flat array built once.
    (B) Downstream-effector lists: replace the per-iteration `_is_ancestor`
        rescan with a per-bone list of downstream effectors built once.

  PROVEN here: indexing a precomputed per-bone table equals recomputing the
  per-bone function (`getD_mapRange`, specialised to children and to downstream).
  Since neither `childrenOf` nor `downstream` depends on the mutable local poses
  -- only on the fixed tree and the fixed effector tips -- hoisting them is exact.

  PLAUSIBLE-CHECKED below: the concrete flat-CSR representation the C++ uses
  (a `flat` index array sliced by per-bone offsets) reads back exactly the true
  children, on 5000 random trees. So the real representation, not just the
  list-of-lists abstraction, matches.
-/
import Plausible

namespace IKFast

universe u
variable {α : Type u}

-- HEART: reading a per-bone precomputed table at b == recomputing f b (for b < n).
-- This is the correctness of hoisting any invariant per-bone computation into a table.
theorem getD_mapRange (f : Nat → α) (n b : Nat) (d : α) (h : b < n) :
    ((List.range n).map f).getD b d = f b := by
  have hb : ((List.range n).map f)[b]? = some (f b) := by
    rw [List.getElem?_map, List.getElem?_range h]
    rfl
  rw [List.getD_eq_getElem?_getD, hb]
  rfl

-- ---- concrete list-encoded tree (parents[i] = i means parentless root) ----
def parentOf (ps : List Nat) (i : Nat) : Nat := ps.getD i i

-- True children of b: every i < n whose parent is b (excluding b itself).
def childrenOf (ps : List Nat) (n b : Nat) : List Nat :=
  (List.range n).filter (fun i => parentOf ps i == b && i != b)

-- reflexive ancestor test, fuel-bounded by chain length.
def isAncF (ps : List Nat) : Nat → Nat → Nat → Bool
  | 0, _, _ => false
  | f + 1, a, j =>
    if a == j then true
    else
      let p := parentOf ps j
      if p < j then isAncF ps f a p else false

-- effectors of bone b = the effector tips that lie in b's subtree.
def downstream (ps : List Nat) (n : Nat) (tips : List Nat) (b : Nat) : List Nat :=
  tips.filter (fun t => isAncF ps (n + 1) b t)

/-- (A) Precomputed children table, indexed at b, equals recomputing children of b. -/
theorem childrenTable_correct (ps : List Nat) (n b : Nat) (h : b < n) :
    ((List.range n).map (childrenOf ps n)).getD b [] = childrenOf ps n b :=
  getD_mapRange (childrenOf ps n) n b [] h

/-- (B) Precomputed downstream-effector table, indexed at b, equals recomputing it. -/
theorem downstreamTable_correct (ps : List Nat) (n : Nat) (tips : List Nat) (b : Nat) (h : b < n) :
    ((List.range n).map (downstream ps n tips)).getD b [] = downstream ps n tips b :=
  getD_mapRange (downstream ps n tips) n b [] h

-- ---- concrete flat CSR (the representation the C++ actually builds) ----
def csrFlat (ps : List Nat) (n : Nat) : List Nat :=
  (List.range n).flatMap (childrenOf ps n)

def csrOffset (ps : List Nat) (n b : Nat) : Nat :=
  (List.range b).foldl (fun acc c => acc + (childrenOf ps n c).length) 0

-- Read b's children out of the flat array: the slice [offset b, offset b + |children b|).
def csrRead (ps : List Nat) (n b : Nat) : List Nat :=
  ((csrFlat ps n).drop (csrOffset ps n b)).take (childrenOf ps n b).length

end IKFast

/- ---------------------------------------------------------------------------
   Plausible: the flat-CSR slice reproduces the true children list, and the
   precomputed downstream table reproduces the per-bone recompute, on random
   trees -- the same proof+sample style as Kusudama.lean / IKFold.lean.
--------------------------------------------------------------------------- -/
namespace IKFastCheck

open IKFast

structure FScene where
  n : Nat
  parents : List Nat -- parents[i] < i (real parent) or = i (root); length n
  tips : List Nat -- effector tip bones
deriving Repr

-- CSR read == true children, for every bone.
def csrAgrees (s : FScene) : Bool :=
  (List.range s.n).all (fun b => csrRead s.parents s.n b == childrenOf s.parents s.n b)

-- precomputed downstream table == per-bone recompute, for every bone.
def downAgrees (s : FScene) : Bool :=
  let tbl := (List.range s.n).map (downstream s.parents s.n s.tips)
  (List.range s.n).all (fun b => tbl.getD b [] == downstream s.parents s.n s.tips b)

open Plausible (Gen SampleableExt Shrinkable)

instance : Shrinkable FScene := ⟨fun _ => []⟩
instance : SampleableExt FScene :=
  SampleableExt.mkSelfContained do
    let nm ← Gen.chooseNatLt 1 9 (by omega)
    let n := nm.val
    let pr ← (List.range n).mapM (fun i => do
      let r ← Gen.chooseNatLt 0 8 (by omega)
      pure (if i = 0 then 0 else r.val % i)) -- parent i < i; bone 0 parentless
    let nt ← Gen.chooseNatLt 0 4 (by omega)
    let tp ← (List.range nt.val).mapM (fun _ => do
      let t ← Gen.chooseNatLt 0 8 (by omega)
      pure (t.val % n))
    pure { n := n, parents := pr, tips := tp }

#eval Plausible.Testable.check (cfg := { numInst := 5000 })
  (∀ s : FScene, csrAgrees s = true)
#eval Plausible.Testable.check (cfg := { numInst := 5000 })
  (∀ s : FScene, downAgrees s = true)

end IKFastCheck
