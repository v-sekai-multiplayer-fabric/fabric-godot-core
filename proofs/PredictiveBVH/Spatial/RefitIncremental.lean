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
    localCoverAt (refitOne t i) i := by sorry
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
    localCoverAt (refitOne t k) j := by sorry
theorem refitOne_preserves_localCover_of_nonchild (t : PbvhTree) (k j : InternalId)
    (hj : j < t.internals.size)
    (hkj : k ≠ j)
    (hkL : ∀ l, (t.internals[j]'hj).left = some l → k ≠ l)
    (hkR : ∀ r, (t.internals[j]'hj).right = some r → k ≠ r)
    (h_cov : localCoverAt t j) :
    localCoverAt (refitOne t k) j := by sorry
theorem refitFull_establishes_cover (t : PbvhTree)
    (hpre : preorderInvariant t) :
    coverInvariant (refitFull t) := by sorry
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
      (walkAndMark parentOf fuel marked i).size = marked.size := by sorry
theorem walkAndMark_preserves_true (parentOf : InternalId → Option InternalId) :
    ∀ (fuel : Nat) (marked : Array Bool) (i : InternalId) (j : Nat),
      marked.getD j false = true →
      (walkAndMark parentOf fuel marked i).getD j false = true := by sorry
theorem walkAndMark_mono_marked (parentOf : InternalId → Option InternalId) :
    ∀ (fuel : Nat) (m1 m2 : Array Bool) (i : InternalId),
      m1.size = m2.size →
      (∀ k, m1.getD k false = true → m2.getD k false = true) →
      ∀ k, (walkAndMark parentOf fuel m1 i).getD k false = true →
           (walkAndMark parentOf fuel m2 i).getD k false = true := by sorry
theorem markAncestors_covers_all_ancestors
    (t : PbvhTree) (dirtyLeafIds : List LeafId)
    (leafToInternal : LeafId → Option InternalId)
    (parentOf : InternalId → Option InternalId)
    (leaf : LeafId) (h_leaf : leaf ∈ dirtyLeafIds)
    (i : InternalId) (hi : i < t.internals.size)
    (h_anc : ∃ start, leafToInternal leaf = some start ∧
        (walkAndMark parentOf t.internals.size
          (Array.replicate t.internals.size false) start).getD i false = true) :
    (markAncestors t dirtyLeafIds leafToInternal parentOf).getD i false = true := by sorry
theorem refitIncrementalSpec_allMarked_eq_refitFull (t : PbvhTree) :
    let allMarked := Array.replicate t.internals.size true
    refitIncrementalSpec t allMarked = refitFull t := by sorry
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
    localCoverAt t2 j := by sorry
theorem refitIncrementalSpec_establishes_cover
    (t : PbvhTree) (marked : Array Bool)
    (hpre : preorderInvariant t)
    (h_marked_covers : ∀ i, i < t.internals.size →
        ¬ marked.getD i false → localCoverAt t i)
    (h_marked_closed : ∀ i (hi : i < t.internals.size),
        ¬ marked.getD i false →
        (∀ l, (t.internals[i]'hi).left = some l → ¬ marked.getD l false) ∧
        (∀ r, (t.internals[i]'hi).right = some r → ¬ marked.getD r false)) :
    coverInvariant (refitIncrementalSpec t marked) := by sorry
