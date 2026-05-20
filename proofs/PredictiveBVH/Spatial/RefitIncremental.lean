-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

import PredictiveBVH.Primitives.Types
import PredictiveBVH.Formulas.LowerBound
import PredictiveBVH.Spatial.Tree

-- ============================================================================
-- REFIT (INCREMENTAL) — Lean spec for pbvh_tree_refit_incremental_
--
-- This module is the load-bearing soundness bridge between:
--   * the high-level query-completeness theorem
--     `aabbQueryN_complete_from_invariants` (Tree.lean:2160), which assumes
--     every internal's bounds cover its subtree's leaves, and
--   * the emitted C function `pbvh_tree_refit_incremental_`
--     (Codegen/TreeC.lean:297), whose job is to *re-establish* that
--     invariant after dirty leaves move.
--
-- Before this module, `pbvh_tree_refit_incremental_` was a hand-templated C
-- string in TreeC.lean with a README-grade soundness argument. A stress
-- bench at 20% dirty / metre-scale motion surfaced a soundness gap (the
-- dedup-break inside the ancestor mark walk silently drops ancestors whose
-- bounds need to grow). This file introduces the Lean spec the C must match;
-- future work wires TreeC.lean to emit FROM this spec rather than freeform.
--
-- Structure:
--   (1) `coverInvariant` — per-internal cover condition.
--   (2) `refitOne`       — refit a single internal from its children's
--                          current bounds.
--   (3) `refitFull`      — post-order refit of every internal.
--   (4) Soundness theorems for (2) and (3).
-- ============================================================================

namespace PbvhTree

open Array

/-- The union of leaf bounds referenced by a leaf-block internal, i.e. the
    slots `sorted[offset .. offset+span)`. `none` for an empty block (span=0);
    otherwise the fold of `unionBounds` over the block. -/
def leafBlockUnion (t : PbvhTree) (offset span : Nat) : Option BoundingBox :=
  (List.range span).foldl (fun (acc : Option BoundingBox) (k : Nat) =>
    match t.leaves[t.sorted[offset + k]!]? with
    | some l =>
      match acc with
      | none   => some l.bounds
      | some a => some (unionBounds a l.bounds)
    | none => acc) none

/-- Pointwise cover condition at a single internal.

    A leaf-block internal (`left = right = none`) must cover the union of its
    leaves' bounds. A full internal (both children present) must cover the
    union of its children's bounds. A half-degenerate internal (exactly one
    child) must cover that child's bounds.

    This is the predicate `pbvh_tree_refit_incremental_` is supposed to
    establish for every ancestor of every dirty leaf, and the precondition
    that `aabbQueryN_complete_from_invariants` consumes when rejecting leaves
    that don't overlap the query at an ancestor. -/
def localCoverAt (t : PbvhTree) (i : InternalId) : Prop :=
  if h : i < t.internals.size then
    let n := t.internals[i]
    match n.left, n.right with
    | none, none =>
      -- Leaf-block: bounds ⊇ leafBlockUnion.
      match leafBlockUnion t n.offset n.span with
      | none    => True
      | some u  => aabbContains n.bounds u
    | some l, none =>
      if hl : l < t.internals.size then
        aabbContains n.bounds t.internals[l].bounds
      else True
    | none, some r =>
      if hr : r < t.internals.size then
        aabbContains n.bounds t.internals[r].bounds
      else True
    | some l, some r =>
      if hl : l < t.internals.size then
        if hr : r < t.internals.size then
          aabbContains n.bounds
            (unionBounds t.internals[l].bounds t.internals[r].bounds)
        else True
      else True
  else True

/-- Global cover invariant: every internal satisfies `localCoverAt`. This is
    the precondition `aabbQueryN_complete_from_invariants` lifts into the
    `h_path_from_root` overlap premise (via `aabbOverlapsDec_lift_through_contains`
    on Tree.lean:2217). -/
def coverInvariant (t : PbvhTree) : Prop :=
  ∀ i, i < t.internals.size → localCoverAt t i

/-- Refit a single internal: overwrite its `bounds` with the union of its
    current children's bounds (or the leaf-block union for leaf-range nodes).
    All other fields — `offset`, `span`, `skip`, `left`, `right` — are
    preserved verbatim. -/
def refitOne (t : PbvhTree) (i : InternalId) : PbvhTree :=
  if h : i < t.internals.size then
    let n := t.internals[i]
    let newBounds : BoundingBox :=
      match n.left, n.right with
      | none, none =>
        match leafBlockUnion t n.offset n.span with
        | some u => u
        | none   => n.bounds  -- empty block: keep old bounds
      | some l, none =>
        if hl : l < t.internals.size then t.internals[l].bounds else n.bounds
      | none, some r =>
        if hr : r < t.internals.size then t.internals[r].bounds else n.bounds
      | some l, some r =>
        if hl : l < t.internals.size then
          if hr : r < t.internals.size then
            unionBounds t.internals[l].bounds t.internals[r].bounds
          else t.internals[l].bounds
        else if hr : r < t.internals.size then t.internals[r].bounds
        else n.bounds
    { t with
      internals := t.internals.set i { n with bounds := newBounds } h }
  else t

/-- `refitOne` touches only `bounds` of node `i`; every other internal's
    entire record is byte-identical before and after. This is the lowered
    counterpart to `refitBucket_preserves_topology` (Tree.lean:660) — topology
    (children/skip/offset/span) is frozen by the build and must not drift
    during per-frame refit. -/
theorem refitOne_preserves_other_internals (t : PbvhTree) (i : InternalId)
    (j : InternalId) (hj : j < t.internals.size) (hij : i ≠ j) :
    (refitOne t i).internals[j]? = t.internals[j]? := by
  unfold refitOne
  by_cases hi : i < t.internals.size
  · simp [hi]
    rw [Array.getElem?_set_ne]
    exact fun hji => hij hji
  · simp [hi]

/-- `refitOne` preserves the *size* of the internals array. Follows from
    `Array.set` being size-preserving; used as a structural precondition by
    every subsequent theorem (so later lemmas can quantify over `i <
    (refitOne t k).internals.size` without extra bookkeeping). -/
theorem refitOne_preserves_size (t : PbvhTree) (i : InternalId) :
    (refitOne t i).internals.size = t.internals.size := by
  unfold refitOne
  by_cases hi : i < t.internals.size
  · simp [hi]
  · simp [hi]

/-- `refitOne` doesn't touch `leaves`. Trivial from the record update. -/
theorem refitOne_preserves_leaves (t : PbvhTree) (k : InternalId) :
    (refitOne t k).leaves = t.leaves := by
  unfold refitOne
  split <;> rfl

/-- `refitOne` doesn't touch `sorted`. Trivial from the record update. -/
theorem refitOne_preserves_sorted (t : PbvhTree) (k : InternalId) :
    (refitOne t k).sorted = t.sorted := by
  unfold refitOne
  split <;> rfl

/-- `leafBlockUnion` depends only on `leaves` and `sorted`, both preserved by
    `refitOne`, so the union is unchanged. -/
theorem refitOne_preserves_leafBlockUnion (t : PbvhTree) (k : InternalId)
    (off sp : Nat) :
    leafBlockUnion (refitOne t k) off sp = leafBlockUnion t off sp := by
  unfold leafBlockUnion
  rw [refitOne_preserves_leaves, refitOne_preserves_sorted]

/-- `refitOne` at index `k` only changes node `k`'s `bounds`; for any other
    index `j ≠ k`, the entire record — including `left`, `right`, `offset`,
    `span`, `skip` — is byte-identical. This is the operational form of
    `refitOne_preserves_other_internals` phrased as a direct getElem equality
    (easier to use in downstream proofs that match on child fields). -/
theorem refitOne_getElem_eq_of_ne (t : PbvhTree) (k j : InternalId)
    (hj : j < (refitOne t k).internals.size) (hkj : k ≠ j) :
    have hj' : j < t.internals.size :=
      (refitOne_preserves_size t k) ▸ hj
    (refitOne t k).internals[j]'hj = t.internals[j]'hj' := by
  have hj' : j < t.internals.size := (refitOne_preserves_size t k) ▸ hj
  have h_opt : (refitOne t k).internals[j]? = t.internals[j]? :=
    refitOne_preserves_other_internals t k j hj' hkj
  have hlhs := Array.getElem?_eq_getElem hj
  have hrhs := Array.getElem?_eq_getElem hj'
  rw [hlhs] at h_opt
  rw [hrhs] at h_opt
  exact Option.some.inj h_opt

/-- `refitOne` at index `k` preserves the `left` field of every node (even
    node `k` itself — only `bounds` is mutated there via `{n with bounds := ...}`). -/
theorem refitOne_preserves_left (t : PbvhTree) (k j : InternalId)
    (hj : j < (refitOne t k).internals.size) :
    have hj' : j < t.internals.size :=
      (refitOne_preserves_size t k) ▸ hj
    ((refitOne t k).internals[j]'hj).left = (t.internals[j]'hj').left := by
  have hj' : j < t.internals.size := (refitOne_preserves_size t k) ▸ hj
  by_cases hkj : k = j
  · -- j = k: the set record is `{ n with bounds := newBounds }`, same left.
    subst hkj
    unfold refitOne
    by_cases hk : k < t.internals.size
    · simp only [hk, dif_pos]
      rw [Array.getElem_set_self]
    · -- k ≥ size contradicts hj'
      exact absurd hj' hk
  · -- j ≠ k: entire record unchanged.
    have h_eq := refitOne_getElem_eq_of_ne t k j hj hkj
    rw [h_eq]

/-- `refitOne` at index `k` preserves the `right` field of every node. -/
theorem refitOne_preserves_right (t : PbvhTree) (k j : InternalId)
    (hj : j < (refitOne t k).internals.size) :
    have hj' : j < t.internals.size :=
      (refitOne_preserves_size t k) ▸ hj
    ((refitOne t k).internals[j]'hj).right = (t.internals[j]'hj').right := by
  have hj' : j < t.internals.size := (refitOne_preserves_size t k) ▸ hj
  by_cases hkj : k = j
  · subst hkj
    unfold refitOne
    by_cases hk : k < t.internals.size
    · simp only [hk, dif_pos]
      rw [Array.getElem_set_self]
    · exact absurd hj' hk
  · have h_eq := refitOne_getElem_eq_of_ne t k j hj hkj
    rw [h_eq]

/-- `refitOne` at index `k` preserves `offset` at every node. -/
theorem refitOne_preserves_offset (t : PbvhTree) (k j : InternalId)
    (hj : j < (refitOne t k).internals.size) :
    have hj' : j < t.internals.size :=
      (refitOne_preserves_size t k) ▸ hj
    ((refitOne t k).internals[j]'hj).offset = (t.internals[j]'hj').offset := by
  have hj' : j < t.internals.size := (refitOne_preserves_size t k) ▸ hj
  by_cases hkj : k = j
  · subst hkj
    unfold refitOne
    by_cases hk : k < t.internals.size
    · simp only [hk, dif_pos]
      rw [Array.getElem_set_self]
    · exact absurd hj' hk
  · have h_eq := refitOne_getElem_eq_of_ne t k j hj hkj
    rw [h_eq]

/-- `refitOne` at index `k` preserves `span` at every node. -/
theorem refitOne_preserves_span (t : PbvhTree) (k j : InternalId)
    (hj : j < (refitOne t k).internals.size) :
    have hj' : j < t.internals.size :=
      (refitOne_preserves_size t k) ▸ hj
    ((refitOne t k).internals[j]'hj).span = (t.internals[j]'hj').span := by
  have hj' : j < t.internals.size := (refitOne_preserves_size t k) ▸ hj
  by_cases hkj : k = j
  · subst hkj
    unfold refitOne
    by_cases hk : k < t.internals.size
    · simp only [hk, dif_pos]
      rw [Array.getElem_set_self]
    · exact absurd hj' hk
  · have h_eq := refitOne_getElem_eq_of_ne t k j hj hkj
    rw [h_eq]

/-- `refitOne` at index `k` preserves `bounds` at every node *except* `k`. -/
theorem refitOne_preserves_bounds_of_ne (t : PbvhTree) (k j : InternalId)
    (hj : j < (refitOne t k).internals.size) (hkj : k ≠ j) :
    have hj' : j < t.internals.size :=
      (refitOne_preserves_size t k) ▸ hj
    ((refitOne t k).internals[j]'hj).bounds = (t.internals[j]'hj').bounds := by
  have hj' : j < t.internals.size := (refitOne_preserves_size t k) ▸ hj
  have h_eq := refitOne_getElem_eq_of_ne t k j hj hkj
  rw [h_eq]

/-- Pre-order DFS topology invariant: every child's index is strictly
    greater than its parent's index. Holds by construction of `buildSubtree`
    (left child = parent + 1, right child = skip[left child] > left child), but
    stated here as an explicit predicate so `refitFull_establishes_cover` can
    consume it without re-deriving the topology. -/
def preorderInvariant (t : PbvhTree) : Prop :=
  ∀ (i : InternalId) (hi : i < t.internals.size),
    (∀ l, (t.internals[i]'hi).left  = some l → i < l) ∧
    (∀ r, (t.internals[i]'hi).right = some r → i < r)

/-- `refitOne` preserves `preorderInvariant`. Follows because it only mutates
    `bounds`; the `left`/`right` fields (which the invariant constrains) are
    preserved at every index by `refitOne_preserves_left`/`_right`. -/
theorem refitOne_preserves_preorderInvariant (t : PbvhTree) (k : InternalId)
    (hpre : preorderInvariant t) : preorderInvariant (refitOne t k) := by
  intro i hi
  have hi' : i < t.internals.size := (refitOne_preserves_size t k) ▸ hi
  have hleft  := refitOne_preserves_left  t k i hi
  have hright := refitOne_preserves_right t k i hi
  obtain ⟨hL, hR⟩ := hpre i hi'
  refine ⟨?_, ?_⟩
  · intro l hl
    rw [hleft] at hl
    exact hL l hl
  · intro r hr
    rw [hright] at hr
    exact hR r hr

/-- The local cover bound produced by `refitOne` at node `i` is, by
    construction, a container for the relevant union:
      * leaf-block  : `bounds = leafBlockUnion` (exact equality, hence ⊇ reflexively)
      * both kids   : `bounds = unionBounds left right` (⊇ each)
      * one kid     : `bounds = that child's bounds` (⊇ reflexively)
    This is the "refit establishes the local cover" micro-lemma, which the
    global `refitFull_establishes_cover` below bootstraps via induction on
    internal index. -/
theorem refitOne_establishes_local_cover_at_i (t : PbvhTree) (i : InternalId)
    (hi : i < t.internals.size) :
    localCoverAt (refitOne t i) i := by
  unfold localCoverAt
  -- After refitOne, the size is unchanged, so `i <` still holds.
  have hsz : (refitOne t i).internals.size = t.internals.size :=
    refitOne_preserves_size t i
  have hi' : i < (refitOne t i).internals.size := hsz ▸ hi
  simp only [hi', dif_pos]
  -- Unfold refitOne to read off the new node at i.
  unfold refitOne
  simp only [hi, dif_pos]
  -- The set-at-i slot reads back the freshly-built record.
  rw [Array.getElem_set_self]
  -- Split into cases. We can't use generalize on `t.internals[i]` (the body
  -- of `refitOne` projects `.left, .right` into bindings `l`, `r` which then
  -- index `t.internals[l]`, `t.internals[r]` independently of our `n`). So
  -- instead, we do a direct cases on `t.internals[i].left` and `.right`.
  -- The trick: name the discriminants as the cases proceed, using `match`
  -- at term level via `match` keyword for the right-hand side analysis.
  set n := t.internals[i] with hn_def
  match hleft : n.left, hright : n.right with
  | none, none =>
    -- Leaf block: newBounds = (leafBlockUnion ...).getD n.bounds. Either
    -- branch of the getD satisfies the block invariant trivially.
    simp only [hleft, hright]
    cases hblock : leafBlockUnion t n.offset n.span with
    | none => simp [hblock]
    | some u =>
      simp only [hblock]
      -- bounds = u; localCoverAt for leaf block requires bounds ⊇ u.
      exact aabbContains_refl u
  | some l, none =>
    simp only [hleft, hright]
    by_cases hl : l < t.internals.size
    · simp [hl]
      exact aabbContains_refl _
    · simp [hl]
  | none, some r =>
    simp only [hleft, hright]
    by_cases hr : r < t.internals.size
    · simp [hr]
      exact aabbContains_refl _
    · simp [hr]
  | some l, some r =>
    simp only [hleft, hright]
    by_cases hl : l < t.internals.size
    · by_cases hr : r < t.internals.size
      · simp [hl, hr]
        exact aabbContains_refl _
      · simp [hl, hr]
        exact aabbContains_refl _
    · by_cases hr : r < t.internals.size
      · simp [hl, hr]
        exact aabbContains_refl _
      · simp [hl, hr]
def refitFull (t : PbvhTree) : PbvhTree :=
  (List.range t.internals.size).foldr (fun i acc => refitOne acc i) t

/-- `refitFull` preserves the internals array size. -/
theorem refitFull_preserves_size (t : PbvhTree) :
    (refitFull t).internals.size = t.internals.size := by
  unfold refitFull
  induction List.range t.internals.size with
  | nil => simp
  | cons k ks ih =>
    simp only [List.foldr_cons]
    rw [refitOne_preserves_size]
    exact ih

/- `refitFull` establishes the global cover invariant.
    PROOF SKETCH (for future mechanisation):
    Let n = t.internals.size.  Define:
      step k t₀ := (List.range k).foldr refitOne t₀   (processes k-1 … 0)
    We prove by induction on k (downward from n to 0):
      ∀ j < k, localCoverAt (step k t₀) j.
    Base (k = 0): vacuous.
    Step (k → k+1):
      step (k+1) t₀ = refitOne k (step k t₀).
      (a) j = k: refitOne_establishes_local_cover_at_i gives localCoverAt. ✓
      (b) j < k (IH): refitOne at k only modifies node k's bounds.
          Node j's children have index > j.  Two sub-cases:
          • child index > k: those bounds are unchanged by refitOne k
            (by refitOne_preserves_other_internals), so j's localCoverAt
            is preserved from the IH directly.
          • child index ≤ k (= k itself, since j < k ≤ child): child k was
            just refit; j's bounds may now be too tight.  But j is
            processed at step j < k, so step j+1 … refitOne j … reads
            the correct, already-updated child bounds at that later point.
            Because step (k+1) = refitOne k ∘ step k, and j < k, j's
            refitOne fires *after* k's.  At the time refitOne j fires it
            reads k's final (correct) bounds.  After that, no refitOne at
            any index ≠ j changes j's bounds.  So j's final bounds are
            correct.
    The argument for the full fold is: at the very end, every node i had
    refitOne i applied *after* all its children's refitOne applications,
    and no later refitOne changes i's bounds. -/
/-- Congruence for `localCoverAt`: if two trees agree on `leaves`, `sorted`,
    internals size, and on the records at `j` and at `j`'s children, then
    `localCoverAt` transfers from one to the other. This is the frame lemma
    used both by `refitOne_preserves_localCover_higher`/`_of_nonchild` and by
    the incremental cover proof (`refitIncrementalSpec_establishes_cover`). -/
theorem localCoverAt_of_records_eq
    (t1 t2 : PbvhTree) (j : InternalId)
    (hsz : t1.internals.size = t2.internals.size)
    (hleaves : t1.leaves = t2.leaves)
    (hsorted : t1.sorted = t2.sorted)
    (hj : j < t1.internals.size)
    (hnode : t1.internals[j]'hj = t2.internals[j]'(hsz ▸ hj))
    (hchildL : ∀ l (hl : l < t1.internals.size),
        (t1.internals[j]'hj).left = some l →
        t1.internals[l]'hl = t2.internals[l]'(hsz ▸ hl))
    (hchildR : ∀ r (hr : r < t1.internals.size),
        (t1.internals[j]'hj).right = some r →
        t1.internals[r]'hr = t2.internals[r]'(hsz ▸ hr))
    (h_cov : localCoverAt t1 j) :
    localCoverAt t2 j := by
  have hj2 : j < t2.internals.size := hsz ▸ hj
  unfold localCoverAt at h_cov ⊢
  rw [dif_pos hj] at h_cov
  rw [dif_pos hj2]
  -- The node read on the t2 side equals (via hnode) the node on the t1 side.
  rw [← hnode]
  -- leafBlockUnion frame lemma since leaves & sorted agree.
  have hleafBlock_eq : ∀ (off sp : Nat),
      leafBlockUnion t2 off sp = leafBlockUnion t1 off sp := by
    intro off sp
    unfold leafBlockUnion
    rw [hleaves, hsorted]
  -- Generalise the discriminant record so both `match` instances in the goal
  -- reduce in lockstep, then destructure (avoids the rcases-generalize fail
  -- on n.left / n.right in Lean 4.26).
  generalize hn : t1.internals[j]'hj = n
  -- Push hn into hchildL/hchildR so they apply post-destructuring.
  have hchildL' : ∀ l (hl : l < t1.internals.size),
      n.left = some l →
      t1.internals[l]'hl = t2.internals[l]'(hsz ▸ hl) := by
    intro l hl heq; exact hchildL l hl (hn ▸ heq)
  have hchildR' : ∀ r (hr : r < t1.internals.size),
      n.right = some r →
      t1.internals[r]'hr = t2.internals[r]'(hsz ▸ hr) := by
    intro r hr heq; exact hchildR r hr (hn ▸ heq)
  clear hn hchildL hchildR
  obtain ⟨bounds, offset, span, skip, left, right⟩ := n
  -- `n.left` / `n.right` reduce to `left` / `right` after destructure.
  simp only at hchildL' hchildR'
  cases left with
  | none =>
    cases right with
    | none =>
      rw [hleafBlock_eq]
      exact h_cov
    | some r =>
      by_cases hr_sz : r < t1.internals.size
      · have hr_sz2 : r < t2.internals.size := hsz ▸ hr_sz
        have h_r_eq := hchildR' r hr_sz rfl
        simp only [hr_sz, dif_pos] at h_cov
        simp only [hr_sz2, dif_pos]
        rw [← h_r_eq]
        exact h_cov
      · have hr_sz2 : ¬ (r < t2.internals.size) := hsz.symm ▸ hr_sz
        simp only [hr_sz, dif_neg, not_false_iff] at h_cov
        simp only [hr_sz2, dif_neg, not_false_iff]
        trivial
  | some l =>
    cases right with
    | none =>
      by_cases hl_sz : l < t1.internals.size
      · have hl_sz2 : l < t2.internals.size := hsz ▸ hl_sz
        have h_l_eq := hchildL' l hl_sz rfl
        simp only [hl_sz, dif_pos] at h_cov
        simp only [hl_sz2, dif_pos]
        rw [← h_l_eq]
        exact h_cov
      · have hl_sz2 : ¬ (l < t2.internals.size) := hsz.symm ▸ hl_sz
        simp only [hl_sz, dif_neg, not_false_iff] at h_cov
        simp only [hl_sz2, dif_neg, not_false_iff]
        trivial
    | some r =>
      by_cases hl_sz : l < t1.internals.size
      · have hl_sz2 : l < t2.internals.size := hsz ▸ hl_sz
        by_cases hr_sz : r < t1.internals.size
        · have hr_sz2 : r < t2.internals.size := hsz ▸ hr_sz
          have h_l_eq := hchildL' l hl_sz rfl
          have h_r_eq := hchildR' r hr_sz rfl
          simp only [hl_sz, hr_sz, dif_pos] at h_cov
          simp only [hl_sz2, hr_sz2, dif_pos]
          rw [← h_l_eq, ← h_r_eq]
          exact h_cov
        · have hr_sz2 : ¬ (r < t2.internals.size) := hsz.symm ▸ hr_sz
          simp only [hl_sz, hr_sz, dif_pos, dif_neg, not_false_iff] at h_cov
          simp only [hl_sz2, hr_sz2, dif_pos, dif_neg, not_false_iff]
          trivial
      · have hl_sz2 : ¬ (l < t2.internals.size) := hsz.symm ▸ hl_sz
        simp only [hl_sz, dif_neg, not_false_iff] at h_cov
        simp only [hl_sz2, dif_neg, not_false_iff]
        trivial

/-- Key helper for `refitFull_establishes_cover`: refitting a lower-indexed
    node `k` preserves `localCoverAt` at a higher-indexed node `j`.
    Intuition: `refitOne k` only changes node `k`'s `bounds`. Node `j`'s own
    fields are unchanged (j ≠ k). By `preorderInvariant`, j's children have
    indices > j > k, so they are ≠ k, and their bounds are also unchanged.
    Hence the cover condition at j evaluates identically. -/
theorem refitOne_preserves_localCover_higher (t : PbvhTree) (k j : InternalId)
    (hpre : preorderInvariant t) (hkj : k < j)
    (hj : j < t.internals.size)
    (h_cov : localCoverAt t j) :
    localCoverAt (refitOne t k) j := by
  -- Strategy: reduce to `localCoverAt_of_records_eq`, which doesn't need
  -- the problematic `rcases : n.left` generalize. We need to show that
  -- `t` and `refitOne t k` agree at j and at j's children. j ≠ k from
  -- k < j; children of j have index > j > k, so also ≠ k.
  have hsz : (refitOne t k).internals.size = t.internals.size :=
    refitOne_preserves_size t k
  have hkj_ne : k ≠ j := Nat.ne_of_lt hkj
  obtain ⟨hL_ord, hR_ord⟩ := hpre j hj
  refine localCoverAt_of_records_eq t (refitOne t k) j hsz.symm
    (refitOne_preserves_leaves t k).symm (refitOne_preserves_sorted t k).symm
    hj ?_ ?_ ?_ h_cov
  · -- node at j unchanged
    have hj_refit : j < (refitOne t k).internals.size := hsz ▸ hj
    exact (refitOne_getElem_eq_of_ne t k j hj_refit hkj_ne).symm
  · -- left child unchanged
    intro l hl hleft
    have hL_gt : j < l := hL_ord l hleft
    have hL_ne : k ≠ l := Nat.ne_of_lt (Nat.lt_trans hkj hL_gt)
    have hl_refit : l < (refitOne t k).internals.size := hsz ▸ hl
    exact (refitOne_getElem_eq_of_ne t k l hl_refit hL_ne).symm
  · -- right child unchanged
    intro r hr hright
    have hR_gt : j < r := hR_ord r hright
    have hR_ne : k ≠ r := Nat.ne_of_lt (Nat.lt_trans hkj hR_gt)
    have hr_refit : r < (refitOne t k).internals.size := hsz ▸ hr
    exact (refitOne_getElem_eq_of_ne t k r hr_refit hR_ne).symm
theorem refitOne_preserves_localCover_of_nonchild (t : PbvhTree) (k j : InternalId)
    (hj : j < t.internals.size)
    (hkj : k ≠ j)
    (hkL : ∀ l, (t.internals[j]'hj).left = some l → k ≠ l)
    (hkR : ∀ r, (t.internals[j]'hj).right = some r → k ≠ r)
    (h_cov : localCoverAt t j) :
    localCoverAt (refitOne t k) j := by
  -- Same strategy as `_higher` — reduce to `localCoverAt_of_records_eq`.
  have hsz : (refitOne t k).internals.size = t.internals.size :=
    refitOne_preserves_size t k
  refine localCoverAt_of_records_eq t (refitOne t k) j hsz.symm
    (refitOne_preserves_leaves t k).symm (refitOne_preserves_sorted t k).symm
    hj ?_ ?_ ?_ h_cov
  · -- node at j unchanged
    have hj_refit : j < (refitOne t k).internals.size := hsz ▸ hj
    exact (refitOne_getElem_eq_of_ne t k j hj_refit hkj).symm
  · -- left child unchanged
    intro l hl hleft
    have hL_ne : k ≠ l := hkL l hleft
    have hl_refit : l < (refitOne t k).internals.size := hsz ▸ hl
    exact (refitOne_getElem_eq_of_ne t k l hl_refit hL_ne).symm
  · -- right child unchanged
    intro r hr hright
    have hR_ne : k ≠ r := hkR r hright
    have hr_refit : r < (refitOne t k).internals.size := hsz ▸ hr
    exact (refitOne_getElem_eq_of_ne t k r hr_refit hR_ne).symm
theorem refitFull_establishes_cover (t : PbvhTree)
    (hpre : preorderInvariant t) :
    coverInvariant (refitFull t) := by
  suffices h : ∀ (k : Nat) (acc : PbvhTree),
      acc.internals.size = t.internals.size →
      preorderInvariant acc →
      (∀ j, k ≤ j → j < t.internals.size → localCoverAt acc j) →
      ∀ j, j < t.internals.size →
        localCoverAt ((List.range k).foldr (fun i acc => refitOne acc i) acc) j by
    intro i hi
    have h_full := h t.internals.size t rfl hpre
      (fun j hj hj' => absurd hj' (Nat.not_lt_of_ge hj))
      i hi
    exact h_full
  intro k
  induction k with
  | zero =>
    intro acc hsz hpre' h_cov j hj
    simp only [List.range_zero, List.foldr_nil]
    exact h_cov j (Nat.zero_le _) hj
  | succ k ih =>
    intro acc hsz hpre' h_cov j hj
    -- Rewrite (List.range (k+1)).foldr refitOne acc
    --       = (List.range k).foldr refitOne (refitOne k acc)
    have h_range : List.range (k + 1) = List.range k ++ [k] := List.range_succ
    rw [h_range, List.foldr_append]
    simp only [List.foldr_cons, List.foldr_nil]
    set acc' := refitOne acc k with hacc'_def
    -- acc' has same size as t
    have hsz' : acc'.internals.size = t.internals.size := by
      rw [hacc'_def, refitOne_preserves_size]; exact hsz
    have hpre'_acc' : preorderInvariant acc' :=
      refitOne_preserves_preorderInvariant acc k hpre'
    -- Show the IH premise holds for acc' with threshold k
    have h_cov' : ∀ j, k ≤ j → j < t.internals.size → localCoverAt acc' j := by
      intro j' hkj' hj'
      by_cases hjk_eq : j' = k
      · -- j' = k: use refitOne_establishes_local_cover_at_i
        subst hjk_eq
        have hj'_acc : j' < acc.internals.size := hsz ▸ hj'
        exact refitOne_establishes_local_cover_at_i acc j' hj'_acc
      · -- j' > k: use refitOne_preserves_localCover_higher
        have hk_lt_j : k < j' := Nat.lt_of_le_of_ne hkj' (Ne.symm hjk_eq)
        have hj'_acc : j' < acc.internals.size := hsz ▸ hj'
        have h_cov_acc : localCoverAt acc j' :=
          h_cov j' (Nat.le_of_lt hk_lt_j) hj'
        exact refitOne_preserves_localCover_higher acc k j' hpre' hk_lt_j
          hj'_acc h_cov_acc
    exact ih acc' hsz' hpre'_acc' h_cov' j hj
private def walkAndMark
    (parentOf : InternalId → Option InternalId)
    (fuel : Nat) (marked : Array Bool) (i : InternalId) : Array Bool :=
  match fuel with
  | 0 => marked
  | fuel + 1 =>
    let marked' := if h : i < marked.size then marked.set i true h else marked
    match parentOf i with
    | none   => marked'
    | some p => walkAndMark parentOf fuel marked' p

/-- Mark every ancestor of every dirty leaf.
    `leafToInternal leaf_id` = the enclosing leaf-range internal for that
    leaf (the bottom of its ancestor chain).
    `parentOf i` = the parent internal of `i` (`none` at the root).
    Returns a `Bool` array of length `t.internals.size`; entry `i` is `true`
    iff internal `i` is an ancestor of at least one dirty leaf. -/
def markAncestors
    (t : PbvhTree) (dirtyLeafIds : List LeafId)
    (leafToInternal : LeafId → Option InternalId)
    (parentOf : InternalId → Option InternalId) : Array Bool :=
  dirtyLeafIds.foldl (fun marked leafId =>
    match leafToInternal leafId with
    | none       => marked
    | some start => walkAndMark parentOf t.internals.size marked start
  ) (Array.replicate t.internals.size false)

/-- Incremental refit: apply `refitOne` only to marked internals, in
    descending index order (children before parents, same as `refitFull`). -/
def refitIncrementalSpec
    (t : PbvhTree) (marked : Array Bool) : PbvhTree :=
  (List.range t.internals.size).foldr (fun i t' =>
    if marked.getD i false then refitOne t' i else t'
  ) t

-- ============================================================================
-- Part IV — soundness of refitIncrementalSpec
-- ============================================================================

/-- `walkAndMark` preserves the size of its `marked` argument. Follows because
    the only mutation is `Array.set` (size-preserving) or no-op. -/
theorem walkAndMark_preserves_size (parentOf : InternalId → Option InternalId) :
    ∀ (fuel : Nat) (marked : Array Bool) (i : InternalId),
      (walkAndMark parentOf fuel marked i).size = marked.size := by
  intro fuel
  induction fuel with
  | zero =>
    intro marked i
    unfold walkAndMark
    rfl
  | succ k ih =>
    intro marked i
    unfold walkAndMark
    by_cases hi : i < marked.size
    · simp only [hi, dif_pos]
      split
      · simp [Array.size_set]
      · rw [ih]; simp [Array.size_set]
    · simp only [hi, dif_neg, not_false_iff]
      split
      · rfl
      · rw [ih]
theorem walkAndMark_preserves_true (parentOf : InternalId → Option InternalId) :
    ∀ (fuel : Nat) (marked : Array Bool) (i : InternalId) (j : Nat),
      marked.getD j false = true →
      (walkAndMark parentOf fuel marked i).getD j false = true := by
  intro fuel
  induction fuel with
  | zero =>
    intro marked i j hj
    unfold walkAndMark
    exact hj
  | succ k ih =>
    intro marked i j hj
    unfold walkAndMark
    -- The step: set i to true (if in bounds), then recurse on parentOf i.
    -- First show: the intermediate `marked'` still has j = true.
    have h_step : (if hi : i < marked.size then marked.set i true hi else marked).getD j false = true := by
      by_cases hi : i < marked.size
      · simp only [hi, dif_pos]
        -- Case: j = i or j ≠ i
        by_cases hji : j = i
        · subst hji
          simp [Array.getD, hi]
        · simp [Array.getD, Array.getElem_set, hji]
          intro hj_sz
          have hj_marked : j < marked.size := hj_sz
          simp [Array.getD, hj_marked] at hj
          exact hj
      · simp only [hi, dif_neg]
        exact hj
    -- Now split on parentOf i.
    cases h_parent : parentOf i with
    | none =>
      simp only [h_parent]
      exact h_step
    | some p =>
      simp only [h_parent]
      exact ih _ p j h_step
theorem walkAndMark_mono_marked (parentOf : InternalId → Option InternalId) :
    ∀ (fuel : Nat) (m1 m2 : Array Bool) (i : InternalId),
      m1.size = m2.size →
      (∀ k, m1.getD k false = true → m2.getD k false = true) →
      ∀ k, (walkAndMark parentOf fuel m1 i).getD k false = true →
           (walkAndMark parentOf fuel m2 i).getD k false = true := by
  intro fuel
  induction fuel with
  | zero =>
    intro m1 m2 i hsz hmono k hk
    unfold walkAndMark at hk ⊢
    exact hmono k hk
  | succ f ih =>
    intro m1 m2 i hsz hmono k hk
    unfold walkAndMark at hk ⊢
    -- Let m1' and m2' be the after-set arrays
    have hsz_eq : m1.size = m2.size := hsz
    have h_in1 : (i < m1.size) ↔ (i < m2.size) := by rw [hsz_eq]
    have hmono' : ∀ k,
        (if hi : i < m1.size then m1.set i true hi else m1).getD k false = true →
        (if hi : i < m2.size then m2.set i true hi else m2).getD k false = true := by
      intro k'
      by_cases hi1 : i < m1.size
      · have hi2 : i < m2.size := h_in1.mp hi1
        simp only [hi1, hi2, dif_pos]
        intro hk'
        by_cases hk'i : k' = i
        · subst hk'i
          simp [Array.getD, hi2]
        · simp [Array.getD, Array.getElem_set, hk'i] at hk' ⊢
          intro hk'_lt2
          have hk'_m2 : k' < m2.size := hk'_lt2
          have hk'_m1 : k' < m1.size := hsz_eq.symm ▸ hk'_m2
          simp [Array.getD, hk'_m1] at hk'
          replace hk' := hk' hk'_m1
          have hk'_getD : m1.getD k' false = true := by
            simp [Array.getD, hk'_m1]; exact hk'
          have hk'_m2_getD : m2.getD k' false = true := hmono k' hk'_getD
          simp [Array.getD, hk'_m2] at hk'_m2_getD
          exact hk'_m2_getD
      · have hi2 : ¬ i < m2.size := fun h => hi1 (h_in1.mpr h)
        simp only [hi1, hi2, dif_neg, not_false_iff]
        exact hmono k'
    -- Size of m1' equals size of m2'
    have hsz' : (if hi : i < m1.size then m1.set i true hi else m1).size =
                (if hi : i < m2.size then m2.set i true hi else m2).size := by
      by_cases hi : i < m1.size
      · have hi2 : i < m2.size := h_in1.mp hi
        simp only [hi, hi2, dif_pos, Array.size_set]
        exact hsz_eq
      · have hi2 : ¬ i < m2.size := fun h => hi (h_in1.mpr h)
        simp only [hi, hi2, dif_neg, not_false_iff]
        exact hsz_eq
    -- Case on parentOf i
    cases h_parent : parentOf i with
    | none =>
      simp only [h_parent] at hk ⊢
      exact hmono' k hk
    | some p =>
      simp only [h_parent] at hk ⊢
      exact ih _ _ p hsz' hmono' k hk
theorem markAncestors_covers_all_ancestors
    (t : PbvhTree) (dirtyLeafIds : List LeafId)
    (leafToInternal : LeafId → Option InternalId)
    (parentOf : InternalId → Option InternalId)
    (leaf : LeafId) (h_leaf : leaf ∈ dirtyLeafIds)
    (i : InternalId) (hi : i < t.internals.size)
    (h_anc : ∃ start, leafToInternal leaf = some start ∧
        (walkAndMark parentOf t.internals.size
          (Array.replicate t.internals.size false) start).getD i false = true) :
    (markAncestors t dirtyLeafIds leafToInternal parentOf).getD i false = true := by
  unfold markAncestors
  obtain ⟨start, h_leaf_to, h_walk⟩ := h_anc
  -- Helper: the foldl body.
  set step := fun (marked : Array Bool) (leafId : LeafId) =>
    match leafToInternal leafId with
    | none       => marked
    | some start => walkAndMark parentOf t.internals.size marked start with hstep_def
  -- Size invariant: foldl preserves size = t.internals.size.
  have hsz_inv : ∀ (l : List LeafId) (acc : Array Bool),
      acc.size = t.internals.size →
      (l.foldl step acc).size = t.internals.size := by
    intro l
    induction l with
    | nil => intro acc h; exact h
    | cons hd tl ih_l =>
      intro acc hacc
      simp only [List.foldl_cons]
      apply ih_l
      unfold_let step
      simp only
      cases h : leafToInternal hd with
      | none => exact hacc
      | some s =>
        simp only [h]
        rw [walkAndMark_preserves_size]
        exact hacc
  -- Monotonicity of foldl over step (preserves trues).
  have hmono_foldl : ∀ (l : List LeafId) (acc : Array Bool) (j : Nat),
      acc.getD j false = true →
      (l.foldl step acc).getD j false = true := by
    intro l
    induction l with
    | nil => intro acc j h; exact h
    | cons hd tl ih_l =>
      intro acc j hj
      simp only [List.foldl_cons]
      apply ih_l
      unfold_let step
      simp only
      cases h : leafToInternal hd with
      | none => exact hj
      | some s =>
        simp only [h]
        exact walkAndMark_preserves_true parentOf _ _ _ j hj
  -- Split the list at `leaf`.
  obtain ⟨pre, post, h_split⟩ := List.append_of_mem h_leaf
  rw [h_split]
  rw [List.foldl_append]
  simp only [List.foldl_cons]
  -- After processing pre: some accumulator acc_pre with size = n.
  set acc_pre := pre.foldl step (Array.replicate t.internals.size false) with hacc_pre_def
  have hacc_pre_size : acc_pre.size = t.internals.size :=
    hsz_inv pre _ (by simp [Array.size_replicate])
  -- Now apply step at `leaf`:
  have h_step_leaf : step acc_pre leaf =
      walkAndMark parentOf t.internals.size acc_pre start := by
    unfold_let step
    simp only [h_leaf_to]
  rw [h_step_leaf]
  set acc_post_leaf := walkAndMark parentOf t.internals.size acc_pre start
    with hacc_post_leaf_def
  -- Claim: acc_post_leaf has entry i = true.
  have hi_true_post_leaf : acc_post_leaf.getD i false = true := by
    rw [hacc_post_leaf_def]
    have hsz_eq : (Array.replicate t.internals.size false).size = acc_pre.size := by
      rw [Array.size_replicate, hacc_pre_size]
    have hmono_mk : ∀ j,
        (Array.replicate t.internals.size false).getD j false = true → acc_pre.getD j false = true := by
      intro j h
      simp [Array.getD, Array.getElem_replicate] at h
    exact walkAndMark_mono_marked parentOf t.internals.size
      (Array.replicate t.internals.size false) acc_pre start
      hsz_eq hmono_mk i h_walk
  -- Apply monotonic foldl to preserve truth through `post`.
  exact hmono_foldl post acc_post_leaf i hi_true_post_leaf
theorem refitIncrementalSpec_allMarked_eq_refitFull (t : PbvhTree) :
    let allMarked := Array.replicate t.internals.size true
    refitIncrementalSpec t allMarked = refitFull t := by
  simp only [refitIncrementalSpec, refitFull]
  congr 1
  funext i
  funext t'
  simp [Array.getD, Array.replicate]
-- Moved earlier in file (before refitOne_preserves_localCover_higher).
-- See line ~410 in the source file.
theorem refitIncrementalSpec_establishes_cover
    (t : PbvhTree) (marked : Array Bool)
    (hpre : preorderInvariant t)
    (h_marked_covers : ∀ i, i < t.internals.size →
        ¬ marked.getD i false → localCoverAt t i)
    (h_marked_closed : ∀ i (hi : i < t.internals.size),
        ¬ marked.getD i false →
        (∀ l, (t.internals[i]'hi).left = some l → ¬ marked.getD l false) ∧
        (∀ r, (t.internals[i]'hi).right = some r → ¬ marked.getD r false)) :
    coverInvariant (refitIncrementalSpec t marked) := by
  suffices h : ∀ (k : Nat) (acc : PbvhTree)
      (hsz : acc.internals.size = t.internals.size),
      acc.leaves = t.leaves →
      acc.sorted = t.sorted →
      preorderInvariant acc →
      (∀ j (hj : j < t.internals.size), ¬ marked.getD j false →
          acc.internals[j]'(hsz ▸ hj) = t.internals[j]'hj) →
      (∀ j, k ≤ j → j < t.internals.size → localCoverAt acc j) →
      ∀ j, j < t.internals.size →
        localCoverAt ((List.range k).foldr
          (fun i t' => if marked.getD i false then refitOne t' i else t') acc) j by
    intro i hi
    have hfinal := h t.internals.size t rfl rfl rfl hpre
      (fun j _ _ => rfl)
      (fun j hj hj' => absurd hj' (Nat.not_lt_of_ge hj))
      i hi
    exact hfinal
  intro k
  induction k with
  | zero =>
    intro acc hsz hleaves hsorted hpre' hmatch h_cov j hj
    simp only [List.range_zero, List.foldr_nil]
    exact h_cov j (Nat.zero_le _) hj
  | succ k ih =>
    intro acc hsz hleaves hsorted hpre' hmatch h_cov j hj
    rw [List.range_succ, List.foldr_append]
    simp only [List.foldr_cons, List.foldr_nil]
    -- Case-split on marked[k] to get a concrete acc'.
    by_cases hm : marked.getD k false
    · -- marked[k] = true: acc' = refitOne acc k
      simp only [hm, if_true]
      set acc' := refitOne acc k with hacc'_def
      have hsz' : acc'.internals.size = t.internals.size := by
        rw [hacc'_def, refitOne_preserves_size]; exact hsz
      have hleaves' : acc'.leaves = t.leaves := by
        rw [hacc'_def, refitOne_preserves_leaves]; exact hleaves
      have hsorted' : acc'.sorted = t.sorted := by
        rw [hacc'_def, refitOne_preserves_sorted]; exact hsorted
      have hpre'_acc' : preorderInvariant acc' :=
        refitOne_preserves_preorderInvariant acc k hpre'
      -- hmatch preservation: for unmarked j', refitOne at (marked) k doesn't touch j'.
      have hmatch' : ∀ j' (hj' : j' < t.internals.size),
          ¬ marked.getD j' false →
          acc'.internals[j']'(hsz' ▸ hj') = t.internals[j']'hj' := by
        intro j' hj' hunm
        have hkj : k ≠ j' := by
          intro hkj_eq
          rw [hkj_eq] at hm
          exact hunm hm
        have hj'_acc : j' < acc.internals.size := hsz ▸ hj'
        have hj'_refit : j' < (refitOne acc k).internals.size :=
          (refitOne_preserves_size acc k).symm ▸ hj'_acc
        have h_step : (refitOne acc k).internals[j']'hj'_refit = acc.internals[j']'hj'_acc :=
          refitOne_getElem_eq_of_ne acc k j' hj'_refit hkj
        calc acc'.internals[j']'(hsz' ▸ hj')
            = (refitOne acc k).internals[j']'hj'_refit := rfl
          _ = acc.internals[j']'hj'_acc := h_step
          _ = t.internals[j']'hj' := hmatch j' hj' hunm
      -- Cover preservation: extend threshold from k+1 down to k.
      have h_cov' : ∀ j', k ≤ j' → j' < t.internals.size → localCoverAt acc' j' := by
        intro j' hkj' hj'
        by_cases hjk_eq : j' = k
        · -- j' = k: fresh refit.
          subst hjk_eq
          have hj'_acc : j' < acc.internals.size := hsz ▸ hj'
          exact refitOne_establishes_local_cover_at_i acc j' hj'_acc
        · -- j' > k: use Higher lemma via preorderInvariant.
          have hk_lt_j : k < j' := Nat.lt_of_le_of_ne hkj' (Ne.symm hjk_eq)
          have hj'_acc : j' < acc.internals.size := hsz ▸ hj'
          have hcov_acc : localCoverAt acc j' :=
            h_cov j' (Nat.succ_le_of_lt hk_lt_j) hj'
          exact refitOne_preserves_localCover_higher acc k j' hpre' hk_lt_j
            hj'_acc hcov_acc
      exact ih acc' hsz' hleaves' hsorted' hpre'_acc' hmatch' h_cov' j hj
    · -- marked[k] = false: acc' = acc
      simp only [hm, if_false]
      -- Invariants for acc are inherited as-is.
      -- Cover preservation: j = k covered by hmatch + h_marked_covers via congr.
      have h_cov' : ∀ j', k ≤ j' → j' < t.internals.size → localCoverAt acc j' := by
        intro j' hkj' hj'
        by_cases hjk_eq : j' = k
        · -- j' = k, unmarked. Transfer from t.
          subst hjk_eq
          -- hmatch gives acc.internals[j'] = t.internals[j'].
          have h_node_eq : acc.internals[j']'(hsz ▸ hj') = t.internals[j']'hj' :=
            hmatch j' hj' hm
          -- children of unmarked j' are unmarked, so also match.
          obtain ⟨hL_closed, hR_closed⟩ := h_marked_closed j' hj' hm
          have hchildL : ∀ l (hl : l < t.internals.size),
              (t.internals[j']'hj').left = some l →
              t.internals[l]'hl = acc.internals[l]'(hsz ▸ hl) := by
            intro l hl hleft
            have hl_unm := hL_closed l hleft
            have := hmatch l hl hl_unm
            exact this.symm
          have hchildR : ∀ r (hr : r < t.internals.size),
              (t.internals[j']'hj').right = some r →
              t.internals[r]'hr = acc.internals[r]'(hsz ▸ hr) := by
            intro r hr hright
            have hr_unm := hR_closed r hright
            have := hmatch r hr hr_unm
            exact this.symm
          -- Invoke congr lemma, transferring from t to acc.
          exact localCoverAt_of_records_eq t acc j' hsz.symm hleaves.symm hsorted.symm
            hj' h_node_eq.symm hchildL hchildR
            (h_marked_covers j' hj' hm)
        · -- j' > k: use IH directly.
          have hk_lt_j : k < j' := Nat.lt_of_le_of_ne hkj' (Ne.symm hjk_eq)
          exact h_cov j' (Nat.succ_le_of_lt hk_lt_j) hj'
      exact ih acc hsz hleaves hsorted hpre' hmatch h_cov' j hj
