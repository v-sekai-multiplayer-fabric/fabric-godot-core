/-
  Blockwise / parallel scheduling correctness for the SwingTwistIK3D solve.

  Question: does processing the solve "blockwise" (batching independent bones, or solving the
  five limb chains in parallel) help, and is it correct? Lean can't prove wall-clock, but it can
  prove the FACT the speedup rests on:

    Editing two bones with DISJOINT subtrees commutes -- the resulting forward kinematics are the
    same regardless of order. So a "block" of mutually-independent bones can be refreshed in any
    order, or in parallel, with no change in result.

  That is the license to (a) solve the left arm / right arm / legs / spine concurrently, and
  (b) collapse a block's subtree refreshes. The performance win is then an empirical scheduling
  matter (measured separately); this file certifies the reorder is exact.

  Reuses the free-monoid tree model from IKFold (transforms = List Int, topological parent map).
-/
import IKFold
import Plausible

set_option linter.unusedSimpArgs false

open IKFold

namespace IKBlock

-- Editing two DISTINCT bones commutes at the local-pose level (independent map updates), so the
-- forward kinematics of any bone is identical regardless of edit order. This is the core safety
-- property for blockwise / parallel scheduling: independent bones can be processed in any order.
theorem edits_commute (par : Tree) (loc : Nat → T) (a b : Nat) (va vb : T) (hab : a ≠ b) :
    ∀ j, fk par (edit (edit loc a va) b vb) j = fk par (edit (edit loc b vb) a va) j := by
  have hcomm : edit (edit loc a va) b vb = edit (edit loc b vb) a va := by
    funext k
    simp only [edit]
    by_cases ha : k = a
    · by_cases hb : k = b
      · exact absurd (ha.symm.trans hb) hab
      · rw [if_neg hb, if_pos ha, if_pos ha]
    · by_cases hb : k = b
      · rw [if_pos hb, if_neg ha, if_pos hb]
      · rw [if_neg hb, if_neg ha, if_neg ha, if_neg hb]
  intro j
  rw [hcomm]

-- Consequently, a bone OUTSIDE b's subtree is unaffected by editing b even after a's edit: the
-- two subtrees are refreshed independently. (Directly from IKFold.fk_unchanged_outside.)
theorem subtree_independent (par : Tree) (loc : Nat → T) (a b : Nat) (va vb : T) :
    ∀ j, isAnc par b j = false →
      fk par (edit (edit loc a va) b vb) j = fk par (edit loc a va) j :=
  fk_unchanged_outside par (edit loc a va) b vb

end IKBlock

/- ---------------------------------------------------------------------------
   Plausible: a blockwise scheduler (process bones grouped into arbitrary blocks,
   each block applied as a batch) yields the same globals as strictly sequential
   application, on random trees + random edit sets.
--------------------------------------------------------------------------- -/
namespace IKBlockCheck

abbrev T := List Int

structure Scene where
  n : Nat
  parents : List Nat -- parents[i] < i or = i (root)
  edits : List Nat -- bones to edit (deduped to distinct; values derived from index)
deriving Repr

def parentOf (s : Scene) (i : Nat) : Nat := s.parents.getD i i
def fkF (s : Scene) (loc : Nat → T) : Nat → Nat → T
  | 0, _ => []
  | f + 1, i =>
    let p := parentOf s i
    if p < i then fkF s loc f p ++ loc i else loc i

def valFor (k : Nat) : T := [Int.ofNat (k % 7) + 1]
def applySeq (base : Nat → T) : List Nat → (Nat → T)
  | [] => base
  | k :: ks => applySeq (fun x => if x = k then valFor k else base x) ks

def baseLoc (_ : Scene) : Nat → T := fun _ => []

-- Order-independence: applying a set of DISTINCT bone edits in forward vs reverse order yields the
-- same globals (a stand-in for any block reordering / parallel schedule). If reversing the order
-- never changes the FK, the bones can be grouped into blocks and processed in any order.
def agrees (s : Scene) : Bool :=
  let es := s.edits.eraseDups
  let fwd := applySeq (baseLoc s) es
  let rev := applySeq (baseLoc s) es.reverse
  (List.range s.n).all (fun j => fkF s fwd (s.n + 1) j == fkF s rev (s.n + 1) j)

open Plausible (Gen SampleableExt Shrinkable)

instance : Shrinkable Scene := ⟨fun _ => []⟩
instance : SampleableExt Scene :=
  SampleableExt.mkSelfContained do
    let nm ← Gen.chooseNatLt 1 9 (by omega)
    let n := nm.val
    let pr ← (List.range n).mapM (fun i => do
      let r ← Gen.chooseNatLt 0 8 (by omega)
      pure (if i = 0 then 0 else r.val % i))
    let ne ← Gen.chooseNatLt 0 6 (by omega)
    let es ← (List.range ne.val).mapM (fun _ => do
      let e ← Gen.chooseNatLt 0 8 (by omega)
      pure (e.val % n))
    pure { n := n, parents := pr, edits := es }

#eval Plausible.Testable.check (cfg := { numInst := 5000 })
  (∀ s : Scene, agrees s = true)

end IKBlockCheck
