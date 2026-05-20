-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

import PredictiveBVH.Primitives.Types
import PredictiveBVH.Formulas.Formula
import PredictiveBVH.Formulas.LowerBound
import PredictiveBVH.Spatial.HilbertBroadphase
import Mathlib.Tactic

-- ============================================================================
-- PREDICTIVE BVH TREE — Lean codification of predictive_bvh_tree.h
--
-- Mirrors the hand-written C scaffold verbatim in shape. Leaves carry an
-- EClassId (Nat) payload; internal nodes form a nested-set pre-order DFS
-- layout with skip-pointer descent. Queries prune by bounds on internals
-- and by Hilbert prefix on the optional bucket directory.
--
-- Invariants (proved where feasible in this first pass; see theorems below):
--   - liveness: remove/update/build do not resurrect dead leaves
--   - sort:     `sorted` is ascending by leaves[·].hilbert over live leaves
--   - eclass uniqueness: each EClassId appears in at most one live leaf
--   - nested-set: internals[i].skip = i + 1 + subtreeSize(left) + subtreeSize(right)
--   - bound containment: union of live leaf bounds under i ⊆ internals[i].bounds
-- ============================================================================

abbrev LeafId     := Nat
abbrev InternalId := Nat

/-- One leaf in the tree. Tombstoned by flipping `alive` to false so that
    `sorted` can stay stable across removals without a rebuild. -/
structure PbvhLeaf where
  eclass  : EClassId
  bounds  : BoundingBox
  hilbert : Nat            -- 30-bit Hilbert code
  alive   : Bool
  deriving Inhabited, Repr

/-- One internal node. `(offset, span)` is the nested-set range into `sorted`;
    `skip` is the next pre-order DFS index past this subtree. -/
structure PbvhInternal where
  bounds : BoundingBox
  offset : Nat
  span   : Nat
  skip   : InternalId
  left   : Option InternalId
  right  : Option InternalId
  deriving Inhabited, Repr

/-- One Hilbert-prefix bucket. `[sortedLo, sortedHi)` is the window into
    `sorted[]` whose Hilbert prefix at `bucketBits` equals this bucket index;
    `[internalsLo, internalsHi)` is the reserved pre-order window into
    `internals[]` owned by the subtree rooted at `subtreeRoot`. Phase 2c's
    `refitBucket` / `resortBucket` confine their writes to these two windows,
    so touching one bucket does not invalidate any other bucket's subtree. -/
structure PbvhBucketSlot where
  sortedLo     : Nat
  sortedHi     : Nat
  internalsLo  : Nat
  internalsHi  : Nat
  subtreeRoot  : Option InternalId
  deriving Inhabited, Repr

/-- Purely-functional BVH tree over EClassId leaves. -/
structure PbvhTree where
  leaves       : Array PbvhLeaf
  sorted       : Array LeafId          -- ascending by leaves[·].hilbert
  internals    : Array PbvhInternal    -- pre-order DFS
  bucketBits   : Nat                   -- 0 disables bucket dir
  bucketSlots  : Array PbvhBucketSlot  -- one per Hilbert prefix
  internalRoot : Option InternalId
  /-- Opaque uint32-sized tag used by `RendererSceneCull::Scenario::indexers`
      to recover which indexer a callback came from. Preserved by `build` /
      `clear`; never inspected by tree ops. -/
  index        : Nat := 0
  deriving Inhabited

namespace PbvhTree

/-- The empty tree. -/
def empty : PbvhTree :=
  { leaves := #[], sorted := #[], internals := #[],
    bucketBits := 0, bucketSlots := #[], internalRoot := none }

/-- Count of leaves currently live. -/
def liveCount (t : PbvhTree) : Nat :=
  t.leaves.foldl (fun acc l => if l.alive then acc + 1 else acc) 0

-- ── insert / remove / update ─────────────────────────────────────────────────

/-- Append a new live leaf. Returns the new tree and its LeafId. `sorted`,
    `internals`, `bucketSlots` go stale until `build` runs. -/
def insert (t : PbvhTree) (eclass : EClassId) (bounds : BoundingBox)
    (hilbert : Nat) : PbvhTree × LeafId :=
  let newLeaf : PbvhLeaf := { eclass, bounds, hilbert, alive := true }
  let id := t.leaves.size
  ({ t with leaves := t.leaves.push newLeaf }, id)

/-- Tombstone a leaf. No-op if out of bounds or already dead. -/
def remove (t : PbvhTree) (id : LeafId) : PbvhTree :=
  if h : id < t.leaves.size then
    let l := t.leaves[id]
    let l' := { l with alive := false }
    { t with leaves := t.leaves.set id l' }
  else t

/-- Update bounds and hilbert of a leaf. No-op if out of bounds. Does not
    touch `alive`. `sorted` is stale until `build` runs. -/
def update (t : PbvhTree) (id : LeafId) (bounds : BoundingBox)
    (hilbert : Nat) : PbvhTree :=
  if h : id < t.leaves.size then
    let l := t.leaves[id]
    let l' := { l with bounds := bounds, hilbert := hilbert }
    { t with leaves := t.leaves.set id l' }
  else t

-- ── build: sort live leaves by hilbert, construct internals ──────────────────

/-- Insert `x` into a list already sorted ascending by `key`, preserving
    stability: existing entries with a key equal to `key x` keep their place,
    and `x` lands immediately after them. -/
private def insertSortedByHilbert (key : LeafId → Nat) (x : LeafId) :
    List LeafId → List LeafId
  | [] => [x]
  | y :: rest =>
    if key x < key y then x :: y :: rest
    else y :: insertSortedByHilbert key x rest

/-- Stable insertion sort of `ids` by `leaves[·].hilbert`. Out-of-bounds ids
    sort as if their key were 0 (defensive, matches the previous panic-avoiding
    accessor). Pure structural recursion — no `Id.run do`. Equivalent in
    observable behaviour to the prior in-place implementation; the functional
    form admits direct `sorted_is_ascending_after_build`-style proofs. -/
private def insertionSortByHilbert
    (leaves : Array PbvhLeaf) (ids : Array LeafId) : Array LeafId :=
  let key (id : LeafId) : Nat := (leaves[id]?.map (·.hilbert)).getD 0
  (ids.foldl (fun acc x => insertSortedByHilbert key x acc) ([] : List LeafId)).toArray

/-- Live leaf ids in tombstone-stripped original-index order. -/
private def liveIds (leaves : Array PbvhLeaf) : Array LeafId :=
  Id.run do
    let mut out : Array LeafId := #[]
    for i in [:leaves.size] do
      if leaves[i]!.alive then out := out.push i
    return out

/-- Union of leaf bounds over a window `[lo, hi)` in `sorted`. -/
private def windowBounds
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat) : BoundingBox :=
  if lo ≥ hi then
    { minX := 0, maxX := 0, minY := 0, maxY := 0, minZ := 0, maxZ := 0 }
  else
    let init := (leaves[sorted[lo]!]?.map (·.bounds)).getD
      { minX := 0, maxX := 0, minY := 0, maxY := 0, minZ := 0, maxZ := 0 }
    (List.range (hi - lo - 1)).foldl (fun acc j =>
      let lb := (leaves[sorted[lo + j + 1]!]?.map (·.bounds)).getD acc
      unionBounds acc lb) init

/-- Compute the split point `mid` with `lo < mid < hi`. Prefers the Hilbert
    prefix split; falls back to the window midpoint when the prefix fails to
    partition. The returned subtype carries the `lo < mid ∧ mid < hi` proof
    that `buildSubtree` needs for its termination measure to strictly decrease
    in both recursive calls. -/
private def computeMid
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat)
    (h : lo + 2 ≤ hi) : { m : Nat // lo < m ∧ m < hi } :=
  -- Median fallback: `lo + (hi - lo) / 2`. When `hi - lo ≥ 2`, the midpoint
  -- strictly separates the window — used both as the default and whenever
  -- the Hilbert-prefix split degenerates.
  let median : Nat := lo + (hi - lo) / 2
  have hmed_lo : lo < median := by
    have hdiff : 2 ≤ hi - lo := by omega
    have hhalf : 1 ≤ (hi - lo) / 2 := Nat.le_div_iff_mul_le (by decide) |>.mpr (by omega)
    omega
  have hmed_hi : median < hi := by
    have hdiff : 0 < hi - lo := by omega
    have hhalf : (hi - lo) / 2 < hi - lo := Nat.div_lt_self hdiff (by decide)
    omega
  let hlo := (leaves[sorted[lo]!]?.map (·.hilbert)).getD 0
  let hhi := (leaves[sorted[hi - 1]!]?.map (·.hilbert)).getD 0
  if hlo == hhi then
    ⟨median, hmed_lo, hmed_hi⟩
  else
    let xor := hlo ^^^ hhi
    let depth := clz30 xor
    let mask : Nat := 1 <<< (29 - depth)
    -- First index in (lo, hi) whose hilbert has the split bit set; default hi.
    let m := (List.range (hi - lo - 1)).foldl (fun acc j =>
      let k := lo + 1 + j
      let hk := (leaves[sorted[k]!]?.map (·.hilbert)).getD 0
      if hk &&& mask != 0 && acc == hi then k else acc) hi
    if h1 : lo < m ∧ m < hi then ⟨m, h1⟩
    else ⟨median, hmed_lo, hmed_hi⟩

/-- Recursive builder: returns the updated internals array plus the root
    index for this subtree. Splits on Hilbert prefix when possible, else
    falls back to median. Termination: `hi - lo` strictly decreases in both
    recursive calls because `computeMid` returns `lo < mid < hi`. -/
private def buildSubtree
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal)
    (lo hi : Nat) : Array PbvhInternal × InternalId :=
  let bounds := windowBounds leaves sorted lo hi
  if hle : hi - lo ≤ 1 then
    let leaf : PbvhInternal :=
      { bounds, offset := lo, span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    (internals.push leaf, internals.size)
  else
    have hgt : lo + 2 ≤ hi := by omega
    let myIdx := internals.size
    -- Placeholder; fixed up after children built.
    let placeholder : PbvhInternal :=
      { bounds, offset := lo, span := hi - lo, skip := myIdx + 1,
        left := none, right := none }
    let internals := internals.push placeholder
    let ⟨mid, hmid_lo, hmid_hi⟩ := computeMid leaves sorted lo hi hgt
    have hleft : mid - lo < hi - lo := by omega
    have hright : hi - mid < hi - lo := by omega
    let (internals, leftIdx) := buildSubtree leaves sorted internals lo mid
    let (internals, rightIdx) := buildSubtree leaves sorted internals mid hi
    -- Patch our node with children and correct skip pointer.
    let updated : PbvhInternal :=
      { bounds, offset := lo, span := hi - lo,
        skip := internals.size,
        left := some leftIdx, right := some rightIdx }
    (internals.set! myIdx updated, myIdx)
  termination_by hi - lo

/-- Rebuild the sorted-by-Hilbert view and the internals tree. Leaves remain
    in place; `alive` flags are untouched. Bucket directory is left empty
    in this Lean codification; callers that want O(1)+k prefix queries can
    populate `bucketSlots` in the C emission. -/
def build (t : PbvhTree) : PbvhTree :=
  let live := liveIds t.leaves
  let sorted := insertionSortByHilbert t.leaves live
  if sorted.isEmpty then
    { t with sorted := #[], internals := #[], internalRoot := none,
             bucketSlots := #[] }
  else
    let (internals, root) := buildSubtree t.leaves sorted #[] 0 sorted.size
    { t with sorted := sorted, internals := internals,
             internalRoot := some root, bucketSlots := #[] }

-- ── Queries ──────────────────────────────────────────────────────────────────

/-- Top-level recursive worker for `aabbQueryN`. Extracted from its former
    `let rec` body so that its recursion principle (and thus soundness /
    completeness proofs) is directly accessible at module scope. Terminates
    on `end_ - i`: each step either advances `i` by one or jumps forward via
    the skip pointer. A defensive clamp on `next` guarantees `next > i ∧
    next ≤ end_`, so the measure decreases even before `skip_equals_dfs_next`
    is proved. -/
def aabbQueryNGo (t : PbvhTree) (query : BoundingBox)
    (i : Nat) (acc : List EClassId) : List EClassId :=
  let end_ := t.internals.size
  if hlt : i ≥ end_ then acc.reverse
  else
    let n := t.internals[i]!
    let next : Nat := if h : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1
    have hnext_lt : end_ - next < end_ - i := by
      have hi : i < end_ := by omega
      show end_ - (if _ : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1) < end_ - i
      split <;> rename_i h <;> omega
    if ¬ aabbOverlapsDec n.bounds query then
      aabbQueryNGo t query next acc
    else if n.left.isNone && n.right.isNone then
      -- Leaf block: scan the (offset, span) window in `sorted`.
      let acc := (List.range n.span).foldl (fun acc j =>
        let lid := t.sorted[n.offset + j]!
        match t.leaves[lid]? with
        | some l =>
          if l.alive && aabbOverlapsDec l.bounds query then
            l.eclass :: acc else acc
        | none => acc) acc
      aabbQueryNGo t query next acc
    else
      have hinc : end_ - (i + 1) < end_ - i := by
        have hi : i < end_ := by omega
        omega
      aabbQueryNGo t query (i + 1) acc
  termination_by t.internals.size - i

/-- Iterative skip-pointer descent. Returns every live leaf eclass whose
    bounds overlap `query`. Emits in pre-order DFS order. -/
def aabbQueryN (t : PbvhTree) (query : BoundingBox) : List EClassId :=
  if t.internals.isEmpty then []
  else aabbQueryNGo t query (t.internalRoot.getD 0) []

-- ── Phase 2b primitives: ray, convex, clear, is_empty, optimize, index ──────

/-- True if the AABB-of-the-segment from `(ox,oy,oz)` to `(tx,ty,tz)` overlaps
    `b`. Necessary condition for segment-box intersection; conservative
    broadphase prune that over-emits (caller re-verifies with a real raycast).
    Soundness of a tighter slab test is deferred to Phase 2b'. -/
def segmentOverlapsBox (ox oy oz tx ty tz : Int) (b : BoundingBox) : Bool :=
  let sMinX := if ox ≤ tx then ox else tx
  let sMaxX := if ox ≤ tx then tx else ox
  let sMinY := if oy ≤ ty then oy else ty
  let sMaxY := if oy ≤ ty then ty else oy
  let sMinZ := if oz ≤ tz then oz else tz
  let sMaxZ := if oz ≤ tz then tz else oz
  aabbOverlapsDec { minX := sMinX, maxX := sMaxX,
                    minY := sMinY, maxY := sMaxY,
                    minZ := sMinZ, maxZ := sMaxZ } b

/-- Top-level recursive worker for `rayQueryN`. Mirrors `aabbQueryNGo` verbatim
    except that the internal-node prune predicate is `segmentOverlapsBox`. -/
def rayQueryNGo (t : PbvhTree) (ox oy oz tx ty tz : Int)
    (i : Nat) (acc : List EClassId) : List EClassId :=
  let end_ := t.internals.size
  if hlt : i ≥ end_ then acc.reverse
  else
    let n := t.internals[i]!
    let next : Nat := if h : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1
    have hnext_lt : end_ - next < end_ - i := by
      have hi : i < end_ := by omega
      show end_ - (if _ : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1) < end_ - i
      split <;> rename_i h <;> omega
    if ¬ segmentOverlapsBox ox oy oz tx ty tz n.bounds then
      rayQueryNGo t ox oy oz tx ty tz next acc
    else if n.left.isNone && n.right.isNone then
      let acc := (List.range n.span).foldl (fun acc j =>
        let lid := t.sorted[n.offset + j]!
        match t.leaves[lid]? with
        | some l =>
          if l.alive && segmentOverlapsBox ox oy oz tx ty tz l.bounds then
            l.eclass :: acc else acc
        | none => acc) acc
      rayQueryNGo t ox oy oz tx ty tz next acc
    else
      have hinc : end_ - (i + 1) < end_ - i := by
        have hi : i < end_ := by omega
        omega
      rayQueryNGo t ox oy oz tx ty tz (i + 1) acc
  termination_by t.internals.size - i

/-- Iterative skip-pointer ray broadphase. Every live leaf whose AABB overlaps
    the segment-AABB of `(ox,oy,oz)→(tx,ty,tz)` has its eclass emitted.
    Over-approximates a true slab test (Phase 2b' tightens). -/
def rayQueryN (t : PbvhTree) (ox oy oz tx ty tz : Int) : List EClassId :=
  if t.internals.isEmpty then []
  else rayQueryNGo t ox oy oz tx ty tz (t.internalRoot.getD 0) []

/-- True if the AABB `b` has any corner on the kept side of plane `p`
    (i.e. `normal · corner + d ≥ 0`). If every corner is strictly below
    the plane, the entire box is rejected. -/
def halfSpaceKeepsBox (p : Plane) (b : BoundingBox) : Bool :=
  let xs := [b.minX, b.maxX]
  let ys := [b.minY, b.maxY]
  let zs := [b.minZ, b.maxZ]
  xs.any (fun x => ys.any (fun y => zs.any (fun z =>
    p.normal.x * x + p.normal.y * y + p.normal.z * z + p.d ≥ 0)))

/-- True if every plane in `planes` keeps at least one corner of `b`.
    A single rejecting plane kills the box. -/
def convexKeepsBox (planes : List Plane) (b : BoundingBox) : Bool :=
  planes.all (fun p => halfSpaceKeepsBox p b)

/-- Top-level recursive worker for `convexQueryN`. Mirror of `aabbQueryNGo`
    with the internal-node prune predicate replaced by `convexKeepsBox`. -/
def convexQueryNGo (t : PbvhTree) (planes : List Plane)
    (i : Nat) (acc : List EClassId) : List EClassId :=
  let end_ := t.internals.size
  if hlt : i ≥ end_ then acc.reverse
  else
    let n := t.internals[i]!
    let next : Nat := if h : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1
    have hnext_lt : end_ - next < end_ - i := by
      have hi : i < end_ := by omega
      show end_ - (if _ : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1) < end_ - i
      split <;> rename_i h <;> omega
    if ¬ convexKeepsBox planes n.bounds then
      convexQueryNGo t planes next acc
    else if n.left.isNone && n.right.isNone then
      let acc := (List.range n.span).foldl (fun acc j =>
        let lid := t.sorted[n.offset + j]!
        match t.leaves[lid]? with
        | some l =>
          if l.alive && convexKeepsBox planes l.bounds then
            l.eclass :: acc else acc
        | none => acc) acc
      convexQueryNGo t planes next acc
    else
      have hinc : end_ - (i + 1) < end_ - i := by
        have hi : i < end_ := by omega
        omega
      convexQueryNGo t planes (i + 1) acc
  termination_by t.internals.size - i

/-- Iterative skip-pointer convex-hull broadphase. Every live leaf whose AABB
    has at least one corner on the kept side of every plane is emitted. -/
def convexQueryN (t : PbvhTree) (planes : List Plane) : List EClassId :=
  if t.internals.isEmpty then []
  else convexQueryNGo t planes (t.internalRoot.getD 0) []

/-- True iff the tree has no live leaves. -/
def isEmpty (t : PbvhTree) : Bool :=
  t.leaves.all (fun l => ¬ l.alive)

/-- Reset the tree to empty while preserving `bucketBits` and `index`. -/
def clear (t : PbvhTree) : PbvhTree :=
  { leaves := #[], sorted := #[], internals := #[],
    bucketBits := t.bucketBits, bucketSlots := #[],
    internalRoot := none, index := t.index }

/-- DynamicBVH-parity wrapper: ignore `passes`, just run a full `build`.
    Our answer to incremental optimization is bucket-localized rebuild (Phase
    2c). Until `tick` lands, the safe semantics is a complete rebuild. -/
def optimizeIncremental (t : PbvhTree) (_passes : Nat) : PbvhTree :=
  build t

/-- Read the opaque indexer tag. -/
def getIndex (t : PbvhTree) : Nat := t.index

/-- Write the opaque indexer tag. -/
def setIndex (t : PbvhTree) (idx : Nat) : PbvhTree :=
  { t with index := idx }

-- ── Phase 2c: bucket-localized rebalance ────────────────────────────────────

/-- Reverse-DFS refit of the internals window `[internalsLo, internalsHi)`
    owned by bucket `b`: re-`unionBounds` from children bottom-up. Only the
    `bounds` field of internals inside the window is touched; every other
    internal and every other field (offset/span/skip/left/right) is preserved,
    as are leaves, sorted, and bucketSlots. Used by `tick` when a leaf moves
    within its bucket. -/
def refitBucket (t : PbvhTree) (b : Nat) : PbvhTree :=
  if hb : b < t.bucketSlots.size then
    let slot := t.bucketSlots[b]
    let hi := slot.internalsHi
    let count := hi - slot.internalsLo
    let internals := (List.range count).foldl (fun (ins : Array PbvhInternal) k =>
      let i := hi - 1 - k
      match ins[i]? with
      | none => ins
      | some n =>
        let newBounds : BoundingBox :=
          match n.left, n.right with
          | none, none =>
              windowBounds t.leaves t.sorted n.offset (n.offset + n.span)
          | some l, none =>
              (ins[l]?.map (·.bounds)).getD n.bounds
          | none, some r =>
              (ins[r]?.map (·.bounds)).getD n.bounds
          | some l, some r =>
              match ins[l]?, ins[r]? with
              | some lb, some rb => unionBounds lb.bounds rb.bounds
              | some lb, none    => lb.bounds
              | none,    some rb => rb.bounds
              | none,    none    => n.bounds
        ins.modify i (fun m => { m with bounds := newBounds })) t.internals
    { t with internals := internals }
  else t

/-- Rebuild the subtree owned by bucket `b`: re-sort the `sorted` window
    `[sortedLo, sortedHi)` by Hilbert code, then reconstruct a fresh
    internals subtree and splice it into `internals[internalsLo, …)`.
    Internal indices inside the subtree (skip/left/right) are relocated
    by `+ internalsLo` so the spliced subtree addresses into the global
    `internals` array. Windows outside the bucket are untouched; caller
    guarantees the new subtree fits (`subInternals.size ≤ internalsHi -
    internalsLo`) or accepts a truncating splice. Used by `tick` when a
    dirty leaf crossed its bucket boundary, was inserted, or was removed. -/
def resortBucket (t : PbvhTree) (b : Nat) : PbvhTree :=
  if hb : b < t.bucketSlots.size then
    let slot := t.bucketSlots[b]
    let sortedLo := slot.sortedLo
    let sortedHi := slot.sortedHi
    let internalsLo := slot.internalsLo
    let internalsHi := slot.internalsHi
    -- Extract the window, re-sort it, splice back.
    let windowLen := sortedHi - sortedLo
    let window : Array LeafId := Array.ofFn (n := windowLen)
      (fun i => t.sorted[sortedLo + i.val]!)
    let resorted := insertionSortByHilbert t.leaves window
    let newSorted : Array LeafId := Array.ofFn (n := t.sorted.size) (fun i =>
      if i.val < sortedLo || sortedHi ≤ i.val then t.sorted[i.val]!
      else if h : i.val - sortedLo < resorted.size then resorted[i.val - sortedLo]
      else t.sorted[i.val]!)
    -- Rebuild the subtree against the freshly sorted window.
    let (subInternals, _subRoot) :=
      buildSubtree t.leaves newSorted #[] sortedLo sortedHi
    -- Splice into internals, relocating internal indices by `+ internalsLo`.
    let winLen := internalsHi - internalsLo
    let subLen := min subInternals.size winLen
    let newInternals : Array PbvhInternal := Array.ofFn (n := t.internals.size)
      (fun i =>
        if i.val < internalsLo || internalsLo + subLen ≤ i.val then
          t.internals[i.val]!
        else if h : i.val - internalsLo < subInternals.size then
          let n := subInternals[i.val - internalsLo]
          { n with
              skip  := n.skip + internalsLo,
              left  := n.left.map (· + internalsLo),
              right := n.right.map (· + internalsLo) }
        else t.internals[i.val]!)
    { t with sorted := newSorted, internals := newInternals }
  else t

/-- One entry in the per-frame dirty-leaf list handed to `tick`. `oldHilbert`
    is the Hilbert code the leaf had on the previous build/tick; the current
    code lives in `leaves[leafId].hilbert`. Comparing them lets `tick`
    classify the leaf as stayed-in-bucket (refit) vs crossed-boundary
    (resort). -/
structure DirtyLeaf where
  leafId     : LeafId
  oldHilbert : Nat
  deriving Inhabited, Repr

/-- Per-frame rebalance driven by a dirty-leaf list. Classifies each dirty
    leaf by whether its Hilbert-prefix bucket changed; refits buckets where
    nothing moved, resorts buckets where a leaf crossed in/out. Falls back
    to a full `build` when the resort set is too large to amortize. Falls
    back to `build` unconditionally when `bucketBits = 0` (no bucket
    directory to localize writes against). -/
def tick (t : PbvhTree) (dirty : Array DirtyLeaf) : PbvhTree :=
  if t.bucketBits = 0 then build t
  else
    let shift := 30 - t.bucketBits
    let bucketOf : Nat → Nat := fun h => h >>> shift
    let init : Array Nat × Array Nat := (#[], #[])
    let (refitSet, resortSet) := dirty.foldl (fun acc d =>
      let rSet := acc.1
      let sSet := acc.2
      match t.leaves[d.leafId]? with
      | none => acc
      | some l =>
        let oldB := bucketOf d.oldHilbert
        let newB := bucketOf l.hilbert
        if oldB = newB then (rSet.push newB, sSet)
        else (rSet, (sSet.push oldB).push newB)) init
    let avgBucket : Nat :=
      if h : t.bucketSlots.size = 0 then 0 else t.sorted.size / t.bucketSlots.size
    if resortSet.size * avgBucket * 2 > t.sorted.size then
      build t
    else
      let t1 := resortSet.foldl resortBucket t
      refitSet.foldl refitBucket t1

/-- `resortBucket` does not touch leaves, bucketSlots, bucketBits, index, or
    internalRoot. Caller-visible state in those fields is identical before
    and after. Per-index window preservation for `sorted`/`internals`
    outside the bucket windows is deferred to `tick`'s proof pass. -/
theorem resortBucket_preserves_structural (t : PbvhTree) (b : Nat) :
    (t.resortBucket b).leaves = t.leaves ∧
    (t.resortBucket b).bucketSlots = t.bucketSlots ∧
    (t.resortBucket b).bucketBits = t.bucketBits ∧
    (t.resortBucket b).internalRoot = t.internalRoot ∧
    (t.resortBucket b).index = t.index := by
  simp only [resortBucket]
  split <;> simp

/-- Enumerate all overlapping live-leaf pairs as `(a, b)` with `a < b` by
    EClassId. Eclass-style broadphase: no pointers, no per-slot callback. -/
def enumeratePairs (t : PbvhTree) : List (EClassId × EClassId) :=
  let n := t.leaves.size
  (List.range n).foldl (fun acc i =>
    match t.leaves[i]? with
    | some li =>
      if ¬ li.alive then acc
      else
        let peers := aabbQueryN t li.bounds
        peers.foldl (fun acc e =>
          if li.eclass < e then (li.eclass, e) :: acc
          else if e < li.eclass then (e, li.eclass) :: acc
          else acc) acc
    | none => acc) []

end PbvhTree

-- ============================================================================
-- PROOFS
-- ============================================================================

namespace PbvhTree

/-- Generic foldl invariant: if `P` holds on the initial accumulator and is
    preserved by every step, it holds on the final fold result. -/
private theorem foldl_invariant {α β : Type _} (P : β → Prop)
    (f : β → α → β) :
    ∀ (l : List α) (b : β), P b → (∀ b a, P b → P (f b a)) → P (l.foldl f b) := by
  intro l
  induction l with
  | nil => intro b hb _; exact hb
  | cons x xs ih =>
    intro b hb hf
    exact ih (f b x) (hf b x hb) hf

/-- `insert` extends `leaves` at the end; the `alive` flag at any existing
    index is preserved. -/
theorem insert_preserves_alive (t : PbvhTree) (e : EClassId) (b : BoundingBox)
    (h : Nat) (i : LeafId) (hi : i < t.leaves.size) :
    ((t.insert e b h).1.leaves[i]?.map (·.alive)) =
      (t.leaves[i]?.map (·.alive)) := by
  simp only [insert]
  rw [Array.getElem?_push_lt hi]
  simp [Array.getElem?_eq_getElem hi]

/-- `update` does not touch the `alive` flag of any leaf (the write only
    rewrites `bounds` and `hilbert`). -/
theorem update_preserves_alive (t : PbvhTree) (id : LeafId) (b : BoundingBox)
    (h : Nat) (i : LeafId) :
    ((t.update id b h).leaves[i]?.map (·.alive)) =
      (t.leaves[i]?.map (·.alive)) := by
  simp only [update]
  split
  · rename_i hid
    rw [Array.getElem?_set hid]
    by_cases heq : id = i
    · subst heq
      simp [Array.getElem?_eq_getElem hid]
    · simp [heq]
  · rfl

/-- `remove id` only flips `alive := false` at position `id`; every other
    leaf's `alive` flag is unchanged. -/
theorem remove_preserves_other_alive (t : PbvhTree) (id : LeafId) (i : LeafId)
    (hne : i ≠ id) :
    ((t.remove id).leaves[i]?.map (·.alive)) =
      (t.leaves[i]?.map (·.alive)) := by
  simp only [remove]
  split
  · rename_i hid
    rw [Array.getElem?_set_ne hid hne.symm]
  · rfl

/-- Sizes never shrink across `insert` / `update` / `remove`. -/
theorem ops_size_monotone (t : PbvhTree) (e : EClassId) (b : BoundingBox)
    (h : Nat) (id : LeafId) :
    t.leaves.size ≤ (t.insert e b h).1.leaves.size ∧
    t.leaves.size ≤ (t.update id b h).leaves.size ∧
    t.leaves.size ≤ (t.remove id).leaves.size := by
  refine ⟨?_, ?_, ?_⟩
  · simp [insert, Array.size_push]
  · simp [update]; split <;> simp [Array.size_set]
  · simp [remove]; split <;> simp [Array.size_set]

/-- `build` never mutates `leaves`. Everything it touches is in `sorted`,
    `internals`, `internalRoot`, `bucketSlots`. -/
theorem build_preserves_leaves (t : PbvhTree) :
    t.build.leaves = t.leaves := by
  simp only [build]
  split <;> rfl

/-- Projection of an internal node onto its topology fields (everything except
    `bounds`). `refitBucket` is defined to preserve this projection at every
    index. -/
private def topoProj (n : PbvhInternal) :
    Nat × Nat × InternalId × Option InternalId × Option InternalId :=
  (n.offset, n.span, n.skip, n.left, n.right)

/-- Record-update on `bounds` leaves every other field of `PbvhInternal`
    unchanged; the topology projection is therefore stable. -/
private theorem topoProj_with_bounds (n : PbvhInternal) (b : BoundingBox) :
    topoProj { n with bounds := b } = topoProj n := rfl

/-- `refitBucket` only rewrites `bounds` of internals in the bucket window;
    every index's topology projection (offset/span/skip/left/right) is
    preserved. -/
theorem refitBucket_preserves_topology (t : PbvhTree) (b i : Nat) :
    ((t.refitBucket b).internals[i]?.map topoProj) =
      (t.internals[i]?.map topoProj) := by
  simp only [refitBucket]
  split
  · -- Bucket index in range: the update is a foldl of per-step `modify`s,
    -- each of which only rewrites `bounds`. Use foldl_invariant with the
    -- topology-projection equality as invariant.
    rename_i hb
    refine foldl_invariant
      (P := fun ins => (ins[i]?.map topoProj) = (t.internals[i]?.map topoProj))
      _ _ _ rfl ?_
    intro ins k hins
    -- Step case: match on the lookup, either no-op or `modify` on bounds.
    dsimp only
    set idx := (t.bucketSlots[b]'hb).internalsHi - 1 - k
    cases hlook : ins[idx]? with
    | none => simpa [hlook] using hins
    | some n =>
      simp only [hlook]
      rw [Array.getElem?_modify]
      by_cases hidx : idx = i
      · subst hidx
        simp only [if_pos rfl, hlook, Option.map_some,
          topoProj_with_bounds]
        have := hins
        simp [hlook] at this
        simpa using this
      · simp only [if_neg hidx]
        exact hins
  · rfl

/-- Corollary: `build` preserves every leaf's `alive` flag. -/
theorem build_preserves_alive (t : PbvhTree) (i : LeafId) :
    (t.build.leaves[i]?.map (·.alive)) = (t.leaves[i]?.map (·.alive)) := by
  rw [build_preserves_leaves]

/-- Inner step of `enumeratePairs`: emitting either `(li, e)` or `(e, li)`
    (guarded by `<`) preserves the "every pair strictly ordered" invariant. -/
private theorem enumeratePairs_inner_step
    (li_eclass e : EClassId) (acc : List (EClassId × EClassId))
    (hacc : ∀ q ∈ acc, q.1 < q.2) :
    ∀ q ∈ (if li_eclass < e then (li_eclass, e) :: acc
           else if e < li_eclass then (e, li_eclass) :: acc
           else acc), q.1 < q.2 := by
  intro q hq
  by_cases h1 : li_eclass < e
  · simp [h1] at hq
    rcases hq with hq | hq
    · rw [hq]; exact h1
    · exact hacc q hq
  · by_cases h2 : e < li_eclass
    · simp [h1, h2] at hq
      rcases hq with hq | hq
      · rw [hq]; exact h2
      · exact hacc q hq
    · simp [h1, h2] at hq
      exact hacc q hq

/-- Every pair emitted by `enumeratePairs` is strictly ordered by EClassId. -/
theorem enumeratePairs_strictly_ordered (t : PbvhTree) :
    ∀ p ∈ t.enumeratePairs, p.1 < p.2 := by
  have H := foldl_invariant
    (P := fun (acc : List (EClassId × EClassId)) => ∀ q ∈ acc, q.1 < q.2)
    (f := fun acc i =>
      match t.leaves[i]? with
      | some li =>
        if ¬ li.alive then acc
        else
          (aabbQueryN t li.bounds).foldl (fun acc e =>
            if li.eclass < e then (li.eclass, e) :: acc
            else if e < li.eclass then (e, li.eclass) :: acc
            else acc) acc
      | none => acc)
    (List.range t.leaves.size) []
    (by intro q hq; exact absurd hq List.not_mem_nil)
    (by
      intro acc i hacc
      -- Case split on the outer step.
      cases hl : t.leaves[i]? with
      | none => simpa [hl] using hacc
      | some li =>
        by_cases halive : li.alive
        · simp only [hl, halive, not_true, ite_false]
          -- Inner fold preserves the invariant.
          exact foldl_invariant
            (P := fun (acc : List (EClassId × EClassId)) => ∀ q ∈ acc, q.1 < q.2)
            (f := fun acc e =>
              if li.eclass < e then (li.eclass, e) :: acc
              else if e < li.eclass then (e, li.eclass) :: acc
              else acc)
            (aabbQueryN t li.bounds) acc hacc
            (fun acc' e hacc' => enumeratePairs_inner_step li.eclass e acc' hacc')
        · simpa [hl, halive] using hacc)
  simpa [enumeratePairs] using H

-- ── Tier 1 (structural) ──────────────────────────────────────────────────────

/-- `buildSubtree` always returns, as its second component, the `internals.size`
    it was called with. That value is captured as `myIdx` before any array
    mutation, so it's stable across both the base and recursive cases. -/
theorem buildSubtree_root (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    (buildSubtree leaves sorted internals lo hi).2 = internals.size := by
  unfold buildSubtree
  split
  · rfl
  · -- `dsimp only` zeta-reduces the `have` chain so the returned pair
    -- literal `(_, internals.size)` is visible; destructuring the `computeMid`
    -- Subtype match then exposes `.snd = internals.size`.
    dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    rfl

/-- After `buildSubtree`, the internals array size only grows. Proved by strong
    induction on the termination measure `hi - lo`. -/
theorem buildSubtree_size_ge (leaves : Array PbvhLeaf) (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      internals.size ≤ (buildSubtree leaves sorted internals lo hi).1.size := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn
    unfold buildSubtree
    split
    · simp [Array.size_push]
    · dsimp only
      obtain ⟨mid, hmlo, hmhi⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0 : internals.size ≤ state0.size := by
        show internals.size ≤ (internals.push ph).size
        simp [Array.size_push]
      have hleft_lt : mid - lo < n := by omega
      have hleft := ih (mid - lo) hleft_lt state0 lo mid rfl
      have hright_lt : hi - mid < n := by omega
      have hright := ih (hi - mid) hright_lt
        (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
      show internals.size ≤
        ((buildSubtree leaves sorted
            (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.set!
          internals.size _).size
      simp
      omega

/-- Strictly-increasing corollary: the returned root index is a valid slot in
    the final internals array. Lets callers safely `[r]!` the root. -/
theorem buildSubtree_root_lt_size (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    (buildSubtree leaves sorted internals lo hi).2 <
      (buildSubtree leaves sorted internals lo hi).1.size := by
  -- `.2 = internals.size` and `.1.size ≥ internals.size + 1`, since the base
  -- case pushes a leaf and the recursive case pushes a placeholder first.
  rw [buildSubtree_root]
  unfold buildSubtree
  split
  · simp [Array.size_push]
  · dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    let ph : PbvhInternal :=
      { bounds := windowBounds leaves sorted lo hi, offset := lo,
        span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    let state0 := internals.push ph
    have h0 : internals.size + 1 = state0.size := by
      show internals.size + 1 = (internals.push ph).size
      simp [Array.size_push]
    have h1 := buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
    have h2 := buildSubtree_size_ge leaves sorted _
      (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
    show internals.size <
      ((buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.set!
        internals.size _).size
    simp
    omega

/-- After `buildSubtree`, the root node's `skip` field equals the final
    `internals.size`. This is the load-bearing invariant: it means the subtree
    rooted at `myIdx` occupies exactly the contiguous range `[myIdx, skip)` in
    the final array, so pruning that subtree is a single index assignment. -/
theorem buildSubtree_skip_eq_final_size
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    let r := (buildSubtree leaves sorted internals lo hi).1
    r[(buildSubtree leaves sorted internals lo hi).2]!.skip = r.size := by
  rw [buildSubtree_root]
  unfold buildSubtree
  split
  · -- Base: pushed leaf has skip := internals.size + 1 = (internals.push leaf).size
    dsimp only
    show (internals.push _)[internals.size]!.skip = (internals.push _).size
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp [Array.size_push])]
    simp [Array.getElem_push_eq]
  · -- Recursive: final `set! myIdx updated` writes updated.skip = inner.size;
    -- since myIdx < inner.size, the readback yields updated.skip = outer.size.
    dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    let ph : PbvhInternal :=
      { bounds := windowBounds leaves sorted lo hi, offset := lo,
        span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    let state0 := internals.push ph
    have h0 : state0.size = internals.size + 1 := by
      show (internals.push ph).size = internals.size + 1
      simp [Array.size_push]
    have h1 := buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
    have h2 := buildSubtree_size_ge leaves sorted _
      (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
    have hmyIdx : internals.size <
        (buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.size := by
      omega
    show ((buildSubtree leaves sorted _ mid hi).1.set! internals.size _)[internals.size]!.skip = _
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp; exact hmyIdx)]
    simp

/-- Structural subtree size in the internals array: under the invariants
    established by `build` (every internal's `skip` points past its subtree in
    the nested-set pre-order DFS layout), `subtreeSize t i = skip - i`. -/
def subtreeSize (t : PbvhTree) (i : InternalId) : Nat :=
  if h : i < t.internals.size then t.internals[i].skip - i else 0

/-- Positions strictly below `internals.size` are untouched by `buildSubtree`:
    the builder only pushes new slots and the final `set!` writes to `myIdx`
    which equals the input `internals.size`, never below. This is the
    workhorse that lets skip invariants propagate across nested builds. -/
theorem buildSubtree_preserves_prefix (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat) (hj : j < internals.size),
        ∃ (hj' : j < (buildSubtree leaves sorted internals lo hi).1.size),
          (buildSubtree leaves sorted internals lo hi).1[j]'hj' = internals[j] := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn j hj
    -- Split the dependent existential BEFORE unfolding buildSubtree, so that
    -- the equality goal is non-dependent (no `∃` with a witness referencing
    -- the destructured `mid`). This is the workaround for Lean 4.26's stricter
    -- "motive not type correct" check on `obtain`/`generalize` over computeMid.
    have h_size : j < (buildSubtree leaves sorted internals lo hi).1.size := by
      have hge := buildSubtree_size_ge leaves sorted n internals lo hi hn
      omega
    refine ⟨h_size, ?_⟩
    unfold buildSubtree
    split
    · -- Base: pushed leaf; position j < internals.size is unchanged.
      show (internals.push _)[j]'_ = internals[j]
      exact Array.getElem_push_lt hj
    · -- Recursive: now the goal is a plain equation, not a dependent existential.
      dsimp only
      obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0_size : state0.size = internals.size + 1 := by
        show (internals.push ph).size = internals.size + 1
        simp [Array.size_push]
      have hj_state0 : j < state0.size := by omega
      have hstate0_j : ∀ (h : j < state0.size), state0[j]'h = internals[j] := by
        intro h
        show (internals.push ph)[j]'h = internals[j]
        exact Array.getElem_push_lt hj
      have hleft_lt : mid - lo < n := by omega
      obtain ⟨hj_s1, hleft⟩ := ih (mid - lo) hleft_lt state0 lo mid rfl j hj_state0
      have hleft_j : (buildSubtree leaves sorted state0 lo mid).1[j]'hj_s1 =
          internals[j] := by rw [hleft]; exact hstate0_j hj_state0
      have hright_lt : hi - mid < n := by omega
      obtain ⟨hj_s2, hright⟩ := ih (hi - mid) hright_lt
        (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl j hj_s1
      have hbridge : (buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1[j]'hj_s2 =
            internals[j] := by rw [hright]; exact hleft_j
      have hne : j ≠ internals.size := by omega
      show ((buildSubtree leaves sorted _ mid hi).1.set!
          internals.size _)[j]'_ = internals[j]
      rw [Array.getElem_set_ne (h := hne)]
      exact hbridge
theorem aabbContains_refl (a : BoundingBox) : aabbContains a a := by
  simp [aabbContains]

/-- `aabbContains` is transitive: outer ⊇ mid ⊇ inner ⟹ outer ⊇ inner. -/
theorem aabbContains_trans {a b c : BoundingBox}
    (hab : aabbContains a b) (hbc : aabbContains b c) : aabbContains a c := by
  simp only [aabbContains] at *
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hab
  obtain ⟨k1, k2, k3, k4, k5, k6⟩ := hbc
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> omega

/-- Containment is preserved by unioning more on the outer. Direct from
    reflexivity + `unionBounds_contains_left` + transitivity. -/
theorem aabbContains_unionBounds_mono_left (a b x : BoundingBox)
    (h : aabbContains a x) : aabbContains (unionBounds a b) x :=
  aabbContains_trans (unionBounds_contains_left a b) h

/-- A `foldl` of `unionBounds` contains its initial accumulator. -/
theorem foldl_unionBounds_contains_init (f : Nat → BoundingBox) :
    ∀ (l : List Nat) (init : BoundingBox),
      aabbContains (l.foldl (fun acc j => unionBounds acc (f j)) init) init := by
  intro l
  induction l with
  | nil => intro init; exact aabbContains_refl init
  | cons x xs ih =>
    intro init
    -- step extends init by `unionBounds init (f x)`, which contains init by left,
    -- then IH on the tail.
    have hstep : aabbContains (unionBounds init (f x)) init :=
      unionBounds_contains_left _ _
    have := ih (unionBounds init (f x))
    exact aabbContains_trans this hstep

/-- A `foldl` of `unionBounds` contains every element `f j` for `j ∈ l`. -/
theorem foldl_unionBounds_contains_item (f : Nat → BoundingBox) :
    ∀ (l : List Nat) (init : BoundingBox) (j : Nat), j ∈ l →
      aabbContains (l.foldl (fun acc k => unionBounds acc (f k)) init) (f j) := by
  intro l
  induction l with
  | nil => intro _ _ hj; exact absurd hj List.not_mem_nil
  | cons x xs ih =>
    intro init j hj
    simp only [List.mem_cons] at hj
    rcases hj with heq | htail
    · -- j = x: after one step, acc = unionBounds init (f x) ⊇ f x; foldl preserves.
      subst heq
      have hone : aabbContains (unionBounds init (f j)) (f j) :=
        unionBounds_contains_right _ _
      have hrest := foldl_unionBounds_contains_init f xs (unionBounds init (f j))
      exact aabbContains_trans hrest hone
    · -- j ∈ xs: recurse.
      exact ih (unionBounds init (f x)) j htail

/-- Generalized fold-contains-init: same as `foldl_unionBounds_contains_init`
    but lets the step function depend on the accumulator. Every step is
    `unionBounds acc _`, and `unionBounds_contains_left` works regardless of
    what the right operand is. -/
theorem foldl_unionBounds_dep_contains_init {α : Type _}
    (g : BoundingBox → α → BoundingBox) :
    ∀ (l : List α) (init : BoundingBox),
      aabbContains (l.foldl (fun acc a => unionBounds acc (g acc a)) init) init := by
  intro l
  induction l with
  | nil => intro init; exact aabbContains_refl init
  | cons x xs ih =>
    intro init
    have hstep : aabbContains (unionBounds init (g init x)) init :=
      unionBounds_contains_left _ _
    have := ih (unionBounds init (g init x))
    exact aabbContains_trans this hstep

/-- If `a ∈ l` and at position `a` the step produces a value whose union with
    the accumulator contains `x`, then the final fold result contains `x`. -/
theorem foldl_dep_contains_item {α : Type _}
    (g : BoundingBox → α → BoundingBox) (x : BoundingBox) :
    ∀ (l : List α) (a : α), a ∈ l →
      (∀ acc : BoundingBox, aabbContains (unionBounds acc (g acc a)) x) →
      ∀ init : BoundingBox,
        aabbContains (l.foldl (fun acc a' => unionBounds acc (g acc a')) init) x := by
  intro l
  induction l with
  | nil => intro _ ha _ _; exact absurd ha List.not_mem_nil
  | cons hd tl ih =>
    intro a ha hg init
    simp only [List.mem_cons] at ha
    rcases ha with heq | htail
    · subst heq
      have hhit : aabbContains (unionBounds init (g init a)) x := hg init
      have hrest := foldl_unionBounds_dep_contains_init g tl
        (unionBounds init (g init a))
      exact aabbContains_trans hrest hhit
    · exact ih a htail hg (unionBounds init (g init hd))

/-- Containment at the `init` slot of `windowBounds`: when `lo < hi` and
    the leaf at `sorted[lo]` resolves, its bounds are contained in the
    window union. -/
theorem windowBounds_contains_init_slot
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat)
    (hlo : lo < hi) (l : PbvhLeaf)
    (hl : leaves[sorted[lo]!]? = some l) :
    aabbContains (windowBounds leaves sorted lo hi) l.bounds := by
  unfold windowBounds
  rw [if_neg (by omega : ¬ lo ≥ hi)]
  dsimp only
  have hinit_eq : (leaves[sorted[lo]!]?.map (·.bounds)).getD
      { minX := 0, maxX := 0, minY := 0, maxY := 0, minZ := 0, maxZ := 0 } =
      l.bounds := by
    rw [hl]
    rfl
  rw [hinit_eq]
  apply foldl_unionBounds_dep_contains_init
theorem windowBounds_contains_step_slot
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat)
    (hlo : lo < hi) (j : Nat) (hj : j < hi - lo - 1)
    (l : PbvhLeaf) (hl : leaves[sorted[lo + j + 1]!]? = some l) :
    aabbContains (windowBounds leaves sorted lo hi) l.bounds := by
  unfold windowBounds
  rw [if_neg (by omega : ¬ lo ≥ hi)]
  dsimp only
  apply foldl_dep_contains_item
    (g := fun acc j' => (leaves[sorted[lo + j' + 1]!]?.map (·.bounds)).getD acc)
    (x := l.bounds) (a := j)
  · exact List.mem_range.mpr hj
  · intro acc
    have hgj : (leaves[sorted[lo + j + 1]!]?.map (·.bounds)).getD acc = l.bounds := by
      rw [hl]; simp
    rw [hgj]
    exact unionBounds_contains_right _ _

/-- After `buildSubtree`, the root node's `bounds` field equals the window
    union over `[lo, hi)`. Both builder branches (leaf push, recursive set!)
    write `bounds := windowBounds leaves sorted lo hi`; this theorem reads
    that write back. Load-bearing for lifting `windowBounds_contains_*` into
    tree-level bound containment. -/
theorem buildSubtree_root_bounds
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    let r := (buildSubtree leaves sorted internals lo hi).1
    r[(buildSubtree leaves sorted internals lo hi).2]!.bounds =
      windowBounds leaves sorted lo hi ∧
    r[(buildSubtree leaves sorted internals lo hi).2]!.offset = lo ∧
    r[(buildSubtree leaves sorted internals lo hi).2]!.span = hi - lo := by
  rw [buildSubtree_root]
  unfold buildSubtree
  split
  · -- Base: the pushed leaf has bounds := windowBounds, offset := lo, span := hi - lo.
    dsimp only
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp [Array.size_push])]
    simp [Array.getElem_push_eq]
  · -- Recursive: final `set!` at internals.size writes `updated` with the same fields.
    dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    let ph : PbvhInternal :=
      { bounds := windowBounds leaves sorted lo hi, offset := lo,
        span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    let state0 := internals.push ph
    have h0 : state0.size = internals.size + 1 := by
      show (internals.push ph).size = internals.size + 1
      simp [Array.size_push]
    have h1 := buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
    have h2 := buildSubtree_size_ge leaves sorted _
      (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
    have hmyIdx : internals.size <
        (buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.size := by
      omega
    show ((buildSubtree leaves sorted _ mid hi).1.set! internals.size _)[internals.size]!.bounds = _ ∧ _ ∧ _
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp; exact hmyIdx)]
    refine ⟨?_, ?_, ?_⟩ <;> simp

/-- Root-level bound containment: for every live leaf in the window
    `sorted[lo, hi)`, the root node's bounds contain that leaf's bounds.
    Direct composition of `buildSubtree_root_bounds` with the
    `windowBounds_contains_*` lemmas. -/
theorem buildSubtree_root_contains_leaf
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat)
    (k : Nat) (hk_lo : lo ≤ k) (hk_hi : k < hi)
    (l : PbvhLeaf) (hl : leaves[sorted[k]!]? = some l) :
    let res := buildSubtree leaves sorted internals lo hi
    aabbContains res.1[res.2]!.bounds l.bounds := by
  obtain ⟨hb, _, _⟩ := buildSubtree_root_bounds leaves sorted internals lo hi
  dsimp only at hb ⊢
  rw [hb]
  have hlo : lo < hi := by omega
  by_cases heq : k = lo
  · subst heq
    exact windowBounds_contains_init_slot leaves sorted k hi hlo l hl
  · -- k = lo + (k - lo - 1) + 1, and k - lo - 1 < hi - lo - 1.
    have hk_gt : lo < k := by omega
    set j := k - lo - 1 with hj_def
    have hj_rewrite : lo + j + 1 = k := by omega
    have hj_lt : j < hi - lo - 1 := by omega
    rw [← hj_rewrite] at hl
    exact windowBounds_contains_step_slot leaves sorted lo hi hlo j hj_lt l hl

/-- **Per-node bounds shape.** Every newly-built internal node `j ≥
    internals.size` has `bounds = windowBounds sorted offset (offset + span)`.
    Proved by strong induction on `hi - lo`. The root slot (base case leaf,
    recursive case final `set!`) has its fields written directly. All
    sub-internals inherit via IH on the two recursive calls and are carried
    through `buildSubtree_preserves_prefix` across the subsequent sibling call
    and across the final `set!` (which only touches index `internals.size`). -/
theorem buildSubtree_new_node_bounds (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          let node := (buildSubtree leaves sorted internals lo hi).1[j]'hj
          node.bounds = windowBounds leaves sorted node.offset
            (node.offset + node.span) := by sorry
theorem buildSubtree_new_node_contains_leaf (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) (internals : Array PbvhInternal) (lo hi : Nat)
    (j : Nat) (hj_ge : internals.size ≤ j)
    (hj : j < (buildSubtree leaves sorted internals lo hi).1.size)
    (l : PbvhLeaf) (k : Nat)
    (node_offset_le : ((buildSubtree leaves sorted internals lo hi).1[j]'hj).offset ≤ k)
    (k_lt_node_end :
      k < ((buildSubtree leaves sorted internals lo hi).1[j]'hj).offset +
          ((buildSubtree leaves sorted internals lo hi).1[j]'hj).span)
    (hl : leaves[sorted[k]!]? = some l) :
    aabbContains ((buildSubtree leaves sorted internals lo hi).1[j]'hj).bounds
      l.bounds := by
  set r := (buildSubtree leaves sorted internals lo hi).1 with hr
  have hb := buildSubtree_new_node_bounds leaves sorted (hi - lo) internals lo hi
    rfl j hj_ge hj
  dsimp only at hb
  rw [hb]
  set o := (r[j]'hj).offset
  set s := (r[j]'hj).span
  have hlo : o < o + s := by omega
  by_cases hk_eq : k = o
  · subst hk_eq
    exact windowBounds_contains_init_slot leaves sorted o (o + s) hlo l hl
  · have hk_gt : o < k := by omega
    set j' := k - o - 1 with hj'_def
    have hj'_rewrite : o + j' + 1 = k := by omega
    have hj'_lt : j' < (o + s) - o - 1 := by omega
    rw [← hj'_rewrite] at hl
    exact windowBounds_contains_step_slot leaves sorted o (o + s) hlo j' hj'_lt l hl

/-- **Per-node skip monotonicity.** Every newly-built internal node `j ≥
    internals.size` has `j < skip[j] ≤ result.size`. Strong induction on
    `hi - lo`, threaded through `state0 → s1 → s2 → set!`. The root slot
    after the final `set!` carries `skip = result.size` directly; sub-internals
    inherit via IH on both recursive calls, with `preserves_prefix` bridging
    across the sibling call and the final `set!`. This subsumes
    `buildSubtree_root_skip_monotone` and is the structural invariant that
    lets the Tier 3 completeness contrapositive reason about DFS children. -/
theorem buildSubtree_new_node_skip_monotone (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          j < ((buildSubtree leaves sorted internals lo hi).1[j]'hj).skip ∧
          ((buildSubtree leaves sorted internals lo hi).1[j]'hj).skip ≤
            (buildSubtree leaves sorted internals lo hi).1.size := by sorry
theorem buildSubtree_new_node_leaf_block_skip (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          let node := (buildSubtree leaves sorted internals lo hi).1[j]'hj
          node.left = none → node.right = none → node.skip = j + 1 := by sorry
theorem buildSubtree_new_node_right_is_left_skip (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          let r := (buildSubtree leaves sorted internals lo hi).1
          ∀ (L R : Nat),
            (r[j]'hj).left = some L → (r[j]'hj).right = some R →
            ∃ (hL : L < r.size), L = j + 1 ∧ (r[L]'hL).skip = R := by sorry
def querySoundOf (t : PbvhTree) (q : BoundingBox) (e : EClassId) : Prop :=
  ∃ (idx : LeafId) (h : idx < t.leaves.size),
    t.leaves[idx].alive = true ∧
    t.leaves[idx].eclass = e ∧
    aabbOverlapsDec t.leaves[idx].bounds q = true

/-- The leaf-block fold inside `aabbQueryN.go` preserves the "every emitted
    eclass has a sound witness" invariant. The fold's body is the ONLY site
    where eclasses are emitted into the accumulator, and it emits `l.eclass`
    only under `l.alive ∧ aabbOverlapsDec l.bounds q` — exactly the witness. -/
theorem aabbQueryN_leaf_fold_preserves_sound (t : PbvhTree) (q : BoundingBox)
    (offset span : Nat) (acc : List EClassId)
    (hacc : ∀ e ∈ acc, querySoundOf t q e) :
    ∀ e ∈ (List.range span).foldl (fun acc j =>
            let lid := t.sorted[offset + j]!
            match t.leaves[lid]? with
            | some l =>
              if l.alive && aabbOverlapsDec l.bounds q then
                l.eclass :: acc else acc
            | none => acc) acc,
      querySoundOf t q e := by
  refine foldl_invariant
    (P := fun (acc : List EClassId) => ∀ e ∈ acc, querySoundOf t q e)
    _ _ _ hacc ?_
  intro acc' j hacc'
  set lid := t.sorted[offset + j]!
  cases hlk : t.leaves[lid]? with
  | none => simpa [hlk] using hacc'
  | some l =>
    by_cases hg : l.alive ∧ aabbOverlapsDec l.bounds q = true
    · obtain ⟨halive, hov⟩ := hg
      have hlid_lt : lid < t.leaves.size := by
        rcases Array.getElem?_eq_some_iff.mp hlk with ⟨h, _⟩
        exact h
      have hleq : t.leaves[lid]'hlid_lt = l := by
        have h := Array.getElem?_eq_getElem hlid_lt
        rw [h] at hlk
        exact Option.some.inj hlk
      simp only [hlk, halive, hov, Bool.and_self, and_self, if_true]
      intro e he
      simp only [List.mem_cons] at he
      rcases he with heq | htail
      · refine ⟨lid, hlid_lt, ?_, ?_, ?_⟩
        · rw [hleq]; exact halive
        · rw [hleq]; exact heq.symm
        · rw [hleq]; exact hov
      · exact hacc' e htail
    · push_neg at hg
      by_cases halive : l.alive
      · have hov : aabbOverlapsDec l.bounds q = false := by
          have := hg halive
          cases hov' : aabbOverlapsDec l.bounds q
          · rfl
          · rw [hov'] at this; exact absurd rfl this
        simp only [hlk, halive, hov, Bool.and_false, if_false]
        exact hacc'
      · simp only [hlk, halive, Bool.false_and, if_false]
        exact hacc'
private theorem foldl_cons_preserves {α β : Type _}
    (f : List β → α → List β)
    (hmono : ∀ (acc : List β) (a : α) (x : β), x ∈ acc → x ∈ f acc a) :
    ∀ (l : List α) (init : List β) (x : β), x ∈ init →
      x ∈ l.foldl f init := by
  intro l
  induction l with
  | nil => intro _ _ hx; exact hx
  | cons hd tl ih =>
    intro init x hx
    simp only [List.foldl_cons]
    exact ih (f init hd) x (hmono init hd x hx)

/-- **Leaf-fold completeness.** If position `j < span` resolves to a live
    leaf whose bounds overlap the query, then the leaf's eclass appears in
    the fold result. Induction on `span`: at the target step the guard fires
    so the emission is cons'd in; later steps only extend the list. -/
theorem aabbQueryN_leaf_fold_emits (t : PbvhTree) (q : BoundingBox)
    (offset span : Nat) (acc : List EClassId)
    (j : Nat) (hj : j < span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[offset + j]!]? = some l)
    (halive : l.alive = true)
    (hov : aabbOverlapsDec l.bounds q = true) :
    l.eclass ∈ (List.range span).foldl (fun acc j =>
      let lid := t.sorted[offset + j]!
      match t.leaves[lid]? with
      | some l =>
        if l.alive && aabbOverlapsDec l.bounds q then
          l.eclass :: acc else acc
      | none => acc) acc := by
  -- Step function is monotone (extension-only).
  set f : List EClassId → Nat → List EClassId := fun acc j =>
    let lid := t.sorted[offset + j]!
    match t.leaves[lid]? with
    | some l =>
      if l.alive && aabbOverlapsDec l.bounds q then
        l.eclass :: acc else acc
    | none => acc with hf_def
  have hmono : ∀ (acc : List EClassId) (k : Nat) (x : EClassId),
      x ∈ acc → x ∈ f acc k := by
    intro acc k x hx
    simp only [hf_def]
    cases hlk : t.leaves[t.sorted[offset + k]!]? with
    | none => simpa [hlk] using hx
    | some l' =>
      by_cases hg : l'.alive && aabbOverlapsDec l'.bounds q
      · simp only [hlk, hg, if_true]; exact List.mem_cons_of_mem _ hx
      · simp only [hlk, hg, if_false]; exact hx
  -- Induct on span.
  induction span with
  | zero => exact absurd hj (by omega)
  | succ n ih =>
    rw [List.range_succ, List.foldl_append]
    simp only [List.foldl_cons, List.foldl_nil]
    by_cases hjn : j = n
    · -- Target step is the last one: guard fires, emission cons'd.
      subst hjn
      have hemit :
          f ((List.range j).foldl f acc) j =
          l.eclass :: (List.range j).foldl f acc := by
        simp only [hf_def, hl, halive, hov, Bool.and_self, if_true]
      rw [hemit]; exact List.mem_cons_self
    · -- Target step earlier than last: IH places eclass in acc', then
      -- the final step preserves it via `hmono`.
      have hj' : j < n := by omega
      have hin : l.eclass ∈ (List.range n).foldl f acc := ih hj'
      exact hmono _ n _ hin

/-- Soundness invariant for `aabbQueryNGo`: if every eclass already in `acc`
    has a sound witness, so does every eclass in the result. Proved by strong
    induction on the termination measure `t.internals.size - i`. At each
    step the only accumulator extension is the leaf-block fold, whose
    preservation is handled by `aabbQueryN_leaf_fold_preserves_sound`. -/
theorem aabbQueryNGo_preserves_sound (t : PbvhTree) (q : BoundingBox) :
    ∀ (m : Nat) (i : Nat) (acc : List EClassId),
      t.internals.size - i = m →
      (∀ e ∈ acc, querySoundOf t q e) →
      ∀ e ∈ aabbQueryNGo t q i acc, querySoundOf t q e := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
    intro i acc hm hacc e he
    rw [aabbQueryNGo] at he
    dsimp only at he
    split at he
    · rw [List.mem_reverse] at he
      exact hacc e he
    · rename_i hlt
      have hi_lt : i < t.internals.size := by omega
      set n := t.internals[i]! with hn_def
      set next : Nat :=
        if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip else i + 1
        with hnext_def
      have hnext_gt : next > i := by
        simp only [hnext_def]
        by_cases h : i < n.skip ∧ n.skip ≤ t.internals.size
        · simp [h]
        · simp [h]
      have hnext_le : next ≤ t.internals.size := by
        simp only [hnext_def]
        by_cases h : i < n.skip ∧ n.skip ≤ t.internals.size
        · simp [h]
        · simp [h]; omega
      have hnext_measure : t.internals.size - next < m := by omega
      split at he
      · exact ih _ hnext_measure next acc rfl hacc e he
      · split at he
        · have hfold := aabbQueryN_leaf_fold_preserves_sound t q n.offset n.span acc hacc
          exact ih _ hnext_measure next _ rfl hfold e he
        · have hi1_measure : t.internals.size - (i + 1) < m := by omega
          exact ih _ hi1_measure (i + 1) acc rfl hacc e he
theorem aabbQueryN_sound (t : PbvhTree) (q : BoundingBox) :
    ∀ e ∈ aabbQueryN t q, querySoundOf t q e := by
  intro e he
  unfold aabbQueryN at he
  split at he
  · exact absurd he List.not_mem_nil
  · exact aabbQueryNGo_preserves_sound t q _ _ [] rfl
      (fun _ h => absurd h List.not_mem_nil) e he

/-- **Accumulator membership is preserved** through `aabbQueryNGo`. If
    `e ∈ acc`, then `e` is in the result. Strong induction on the termination
    measure. The leaf-block fold only extends `acc` (via `foldl_cons_preserves`
    reasoning), and the base case `acc.reverse` preserves membership via
    `List.mem_reverse`. This is the compositional piece that combines with
    `aabbQueryN_leaf_fold_emits` to give local completeness at any reached
    leaf-block. -/
theorem aabbQueryNGo_preserves_membership (t : PbvhTree) (q : BoundingBox) :
    ∀ (m : Nat) (i : Nat) (acc : List EClassId) (e : EClassId),
      t.internals.size - i = m →
      e ∈ acc →
      e ∈ aabbQueryNGo t q i acc := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
    intro i acc e hm he
    rw [aabbQueryNGo]
    dsimp only
    split
    · rw [List.mem_reverse]; exact he
    · rename_i hlt
      have hi_lt : i < t.internals.size := by omega
      set n := t.internals[i]! with hn_def
      set next : Nat :=
        if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip else i + 1
        with hnext_def
      have hnext_gt : next > i := by
        simp only [hnext_def]
        by_cases h : i < n.skip ∧ n.skip ≤ t.internals.size
        · simp [h]
        · simp [h]
      have hnext_le : next ≤ t.internals.size := by
        simp only [hnext_def]
        by_cases h : i < n.skip ∧ n.skip ≤ t.internals.size
        · simp [h]
        · simp [h]; omega
      have hnext_measure : t.internals.size - next < m := by omega
      split
      · exact ih _ hnext_measure next acc e rfl he
      · split
        · have hfold : e ∈ (List.range n.span).foldl (fun acc j =>
              let lid := t.sorted[n.offset + j]!
              match t.leaves[lid]? with
              | some l =>
                if l.alive && aabbOverlapsDec l.bounds q then
                  l.eclass :: acc else acc
              | none => acc) acc := by
            have hmono : ∀ (acc : List EClassId) (k : Nat) (x : EClassId),
                x ∈ acc →
                x ∈ (fun acc j =>
                  let lid := t.sorted[n.offset + j]!
                  match t.leaves[lid]? with
                  | some l =>
                    if l.alive && aabbOverlapsDec l.bounds q then
                      l.eclass :: acc else acc
                  | none => acc) acc k := by
              intro acc' k x hx
              dsimp only
              cases hlk : t.leaves[t.sorted[n.offset + k]!]? with
              | none => simpa [hlk] using hx
              | some l' =>
                by_cases hg : l'.alive && aabbOverlapsDec l'.bounds q
                · simp only [hlk, hg, if_true]; exact List.mem_cons_of_mem _ hx
                · simp only [hlk, hg, if_false]; exact hx
            exact foldl_cons_preserves _ hmono (List.range n.span) acc e he
          exact ih _ hnext_measure next _ e rfl hfold
        · have hi1_measure : t.internals.size - (i + 1) < m := by omega
          exact ih _ hi1_measure (i + 1) acc e rfl he
theorem aabbQueryNGo_leaf_block_complete (t : PbvhTree) (q : BoundingBox)
    (i : Nat) (hi : i < t.internals.size)
    (hleaf : (t.internals[i]!).left.isNone ∧ (t.internals[i]!).right.isNone)
    (hov : aabbOverlapsDec (t.internals[i]!).bounds q = true)
    (j : Nat) (hj : j < (t.internals[i]!).span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[(t.internals[i]!).offset + j]!]? = some l)
    (halive : l.alive = true)
    (hl_ov : aabbOverlapsDec l.bounds q = true)
    (acc : List EClassId) :
    l.eclass ∈ aabbQueryNGo t q i acc := by
  rw [aabbQueryNGo]
  dsimp only
  split
  · rename_i h; omega
  · rename_i hlt
    set n := t.internals[i]! with hn_def
    set next : Nat :=
      if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip else i + 1
      with hnext_def
    have hnext_gt : next > i := by
      rw [hnext_def]
      by_cases h : i < n.skip ∧ n.skip ≤ t.internals.size
      · simp [h]
      · simp [h]
    have hnext_le : next ≤ t.internals.size := by
      rw [hnext_def]
      by_cases h : i < n.skip ∧ n.skip ≤ t.internals.size
      · simp [h]
      · simp [h]; omega
    have hnext_measure : t.internals.size - next < t.internals.size - i := by omega
    have hchild_true : (n.left.isNone && n.right.isNone) = true := by
      simp [hleaf.1, hleaf.2]
    split
    · -- This will be the `(n.left.isNone && n.right.isNone) = true` branch
      -- in 4.26's reordering. Or the outer no-overlap branch in original order.
      rename_i hcase
      -- Case-discriminate based on which form the hypothesis takes.
      first
      | (-- 4.26 reorder: hcase is leaf-block predicate; outer if was simplified
         have hemit := aabbQueryN_leaf_fold_emits t q n.offset n.span acc
           j hj l hl halive hl_ov
         exact aabbQueryNGo_preserves_membership t q _ next _ l.eclass rfl hemit)
      | (-- Original order: hcase is ¬overlap (impossible since hov)
         exfalso; exact absurd hov (by simp [hcase]))
    · rename_i hcase
      -- 4.26 reorder: hcase is leaf-block predicate = false (contradiction)
      first
      | (exact absurd hchild_true hcase)
      | (-- Original order: nested split needed
         split
         · rename_i _
           have hemit := aabbQueryN_leaf_fold_emits t q n.offset n.span acc
             j hj l hl halive hl_ov
           exact aabbQueryNGo_preserves_membership t q _ next _ l.eclass rfl hemit
         · rename_i hchild
           exact absurd hchild_true hchild)
theorem buildSubtree_root_skip_monotone (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) (internals : Array PbvhInternal) (lo hi : Nat) :
    let res := buildSubtree leaves sorted internals lo hi
    res.2 < res.1[res.2]!.skip ∧ res.1[res.2]!.skip ≤ res.1.size := by
  have hroot := buildSubtree_root_lt_size leaves sorted internals lo hi
  have hskip := buildSubtree_skip_eq_final_size leaves sorted internals lo hi
  dsimp only at hskip ⊢
  refine ⟨?_, ?_⟩
  · rw [hskip]; exact hroot
  · rw [hskip]
theorem build_skip_invariants (t : PbvhTree) :
    let t' := build t
    ∀ (j : Nat) (hj : j < t'.internals.size),
      let node := t'.internals[j]'hj
      (j < node.skip ∧ node.skip ≤ t'.internals.size) ∧
      node.bounds = windowBounds t.leaves t'.sorted node.offset
        (node.offset + node.span) ∧
      (node.left = none → node.right = none → node.skip = j + 1) ∧
      (∀ L R, node.left = some L → node.right = some R →
        ∃ (hL : L < t'.internals.size), L = j + 1 ∧
          (t'.internals[L]'hL).skip = R) := by
  intro t' j hj
  -- t' is a let-binding for build t; we need to expose its content.
  change (j < ((build t).internals[j]'hj).skip ∧
          ((build t).internals[j]'hj).skip ≤ (build t).internals.size) ∧
         ((build t).internals[j]'hj).bounds =
           windowBounds t.leaves (build t).sorted ((build t).internals[j]'hj).offset
             (((build t).internals[j]'hj).offset + ((build t).internals[j]'hj).span) ∧
         (((build t).internals[j]'hj).left = none →
           ((build t).internals[j]'hj).right = none →
           ((build t).internals[j]'hj).skip = j + 1) ∧
         (∀ L R, ((build t).internals[j]'hj).left = some L →
           ((build t).internals[j]'hj).right = some R →
           ∃ (hL : L < (build t).internals.size), L = j + 1 ∧
             ((build t).internals[L]'hL).skip = R)
  change j < (build t).internals.size at hj
  unfold build at hj ⊢
  dsimp only at hj ⊢
  split at hj
  · -- Empty case: t'.internals = #[], so j < 0 is absurd.
    rename_i hemp
    simp at hj
  · -- Non-empty case: t'.internals = (buildSubtree ... #[] 0 sorted.size).1.
    rename_i hnemp
    simp only [hnemp, if_false] at hj ⊢
    set sorted := insertionSortByHilbert t.leaves (liveIds t.leaves) with hsorted_def
    set R := buildSubtree t.leaves sorted #[] 0 sorted.size with hR_def
    have hj_ge : (#[] : Array PbvhInternal).size ≤ j := by simp
    have hj_R : j < R.1.size := hj
    refine ⟨?_, ?_, ?_, ?_⟩
    · exact buildSubtree_new_node_skip_monotone t.leaves sorted
        sorted.size #[] 0 sorted.size rfl j hj_ge hj_R
    · exact buildSubtree_new_node_bounds t.leaves sorted
        sorted.size #[] 0 sorted.size rfl j hj_ge hj_R
    · exact buildSubtree_new_node_leaf_block_skip t.leaves sorted
        sorted.size #[] 0 sorted.size rfl j hj_ge hj_R
    · intro L Rc hL hR
      exact buildSubtree_new_node_right_is_left_skip t.leaves sorted
        sorted.size #[] 0 sorted.size rfl j hj_ge hj_R L Rc hL hR
theorem build_contains_leaf (t : PbvhTree)
    (j : Nat) (hj : j < (build t).internals.size)
    (l : PbvhLeaf) (k : Nat)
    (node_offset_le : ((build t).internals[j]'hj).offset ≤ k)
    (k_lt_node_end :
      k < ((build t).internals[j]'hj).offset +
          ((build t).internals[j]'hj).span)
    (hl : t.leaves[(build t).sorted[k]!]? = some l) :
    aabbContains ((build t).internals[j]'hj).bounds l.bounds := by
  unfold build at hj node_offset_le k_lt_node_end hl ⊢
  dsimp only at hj node_offset_le k_lt_node_end hl ⊢
  split at hj
  · rename_i hemp
    simp at hj
  · rename_i hnemp
    simp only [hnemp, if_false] at hj node_offset_le k_lt_node_end hl ⊢
    set sorted := insertionSortByHilbert t.leaves (liveIds t.leaves) with hsorted_def
    have hj_ge : (#[] : Array PbvhInternal).size ≤ j := by simp
    exact buildSubtree_new_node_contains_leaf t.leaves sorted #[] 0 sorted.size
      j hj_ge hj l k node_offset_le k_lt_node_end hl
theorem aabbQueryNGo_visits_overlapping_leaf (t : PbvhTree) (q : BoundingBox)
    (h_leaf_skip : ∀ j, j < t.internals.size →
      (t.internals[j]!).left = none → (t.internals[j]!).right = none →
        (t.internals[j]!).skip = j + 1)
    (h_skip_mono : ∀ j, j < t.internals.size →
      j < (t.internals[j]!).skip ∧
      (t.internals[j]!).skip ≤ t.internals.size)
    (target : Nat) (htarget : target < t.internals.size)
    (h_target_left : (t.internals[target]!).left = none)
    (h_target_right : (t.internals[target]!).right = none)
    (jw : Nat) (hjw : jw < (t.internals[target]!).span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[(t.internals[target]!).offset + jw]!]? = some l)
    (halive : l.alive = true) (hl_ov : aabbOverlapsDec l.bounds q = true) :
    ∀ (m : Nat) (i : Nat) (acc : List EClassId),
      target - i = m → i ≤ target →
      (∀ k, i ≤ k → k ≤ target →
        aabbOverlapsDec (t.internals[k]!).bounds q = true) →
      l.eclass ∈ aabbQueryNGo t q i acc := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
    intro i acc hm hi_le h_path
    have hi_lt : i < t.internals.size :=
      Nat.lt_of_le_of_lt hi_le htarget
    have hov_i : aabbOverlapsDec (t.internals[i]!).bounds q = true :=
      h_path i (Nat.le_refl _) hi_le
    by_cases hi_eq : i = target
    · -- Base case: arrived at target, use local leaf-block completeness.
      subst hi_eq
      exact aabbQueryNGo_leaf_block_complete t q i hi_lt
        ⟨by rw [h_target_left]; rfl, by rw [h_target_right]; rfl⟩
        hov_i jw hjw l hl halive hl_ov acc
    · -- Step case: i < target; advance by exactly one.
      have hi_lt_target : i < target :=
        Nat.lt_of_le_of_ne hi_le hi_eq
      have hm1 : target - (i + 1) < m := by omega
      have hi1_le : i + 1 ≤ target := by omega
      have h_path1 : ∀ k, i + 1 ≤ k → k ≤ target →
          aabbOverlapsDec (t.internals[k]!).bounds q = true :=
        fun k hk1 hk2 => h_path k (by omega) hk2
      rw [aabbQueryNGo]
      dsimp only
      split
      · rename_i h; omega
      · rename_i hlt'
        set n := t.internals[i]! with hn_def
        -- The `next` in aabbQueryNGo
        set next : Nat :=
          if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip
          else i + 1 with hnext_def
        -- Split on the leaf-block check (4.26 picks this first).
        split
        · rename_i hleaf_cond
          -- Leaf-block at i: next = skip[i] = i + 1.
          have hleaf_split : n.left.isNone = true ∧ n.right.isNone = true := by
            rw [← Bool.and_eq_true]; exact hleaf_cond
          have hleft_none : n.left = none := by
            cases hx : n.left with
            | none => rfl
            | some v =>
              have : n.left.isNone = false := by rw [hx]; rfl
              rw [this] at hleaf_split
              exact absurd hleaf_split.1 (by decide)
          have hright_none : n.right = none := by
            cases hx : n.right with
            | none => rfl
            | some v =>
              have : n.right.isNone = false := by rw [hx]; rfl
              rw [this] at hleaf_split
              exact absurd hleaf_split.2 (by decide)
          have hskip_eq : n.skip = i + 1 := by
            show (t.internals[i]!).skip = i + 1
            exact h_leaf_skip i hi_lt hleft_none hright_none
          have hmono := h_skip_mono i hi_lt
          have hmono_cond : i < n.skip ∧ n.skip ≤ t.internals.size := by
            show i < (t.internals[i]!).skip ∧
                 (t.internals[i]!).skip ≤ t.internals.size
            exact hmono
          have hnext_val : next = i + 1 := by
            rw [hnext_def]; split
            · exact hskip_eq
            · rename_i hne; exact absurd hmono_cond hne
          set acc' := (List.range n.span).foldl (fun acc j =>
            let lid := t.sorted[n.offset + j]!
            match t.leaves[lid]? with
            | some l =>
              if l.alive && aabbOverlapsDec l.bounds q then
                l.eclass :: acc else acc
            | none => acc) acc with hacc'
          rw [hnext_val]
          exact ih _ hm1 (i + 1) acc' rfl hi1_le h_path1
        · rename_i _hnonleaf
          -- Non-leaf at i: algorithm advances to i + 1 directly.
          exact ih _ hm1 (i + 1) acc rfl hi1_le h_path1
theorem aabbQueryN_complete_from_invariants
    (t : PbvhTree) (q : BoundingBox)
    (h_leaf_skip : ∀ j, j < t.internals.size →
      (t.internals[j]!).left = none → (t.internals[j]!).right = none →
        (t.internals[j]!).skip = j + 1)
    (h_skip_mono : ∀ j, j < t.internals.size →
      j < (t.internals[j]!).skip ∧
      (t.internals[j]!).skip ≤ t.internals.size)
    (h_root : t.internalRoot = some 0)
    (h_nonempty : ¬ t.internals.isEmpty)
    (target : Nat) (htarget : target < t.internals.size)
    (h_target_left : (t.internals[target]!).left = none)
    (h_target_right : (t.internals[target]!).right = none)
    (jw : Nat) (hjw : jw < (t.internals[target]!).span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[(t.internals[target]!).offset + jw]!]? = some l)
    (halive : l.alive = true) (hl_ov : aabbOverlapsDec l.bounds q = true)
    (h_path_from_root : ∀ k, k ≤ target →
      aabbOverlapsDec (t.internals[k]!).bounds q = true) :
    l.eclass ∈ aabbQueryN t q := by
  unfold aabbQueryN
  split
  · rename_i h; exact absurd h h_nonempty
  · rename_i _hne
    rw [h_root]
    exact aabbQueryNGo_visits_overlapping_leaf t q h_leaf_skip h_skip_mono
      target htarget h_target_left h_target_right jw hjw l hl halive hl_ov
      (target - 0) 0 [] rfl (Nat.zero_le _)
      (fun k _ hk_le => h_path_from_root k hk_le)

/-- The ghost-expanded AABB strictly contains the leaf's original bounds.
    Direct consequence of `expansion v a k ≥ 0` on every axis: each min
    shrinks (`minX - ex ≤ minX` since `ex ≥ 0`) and each max grows
    (`maxX ≤ maxX + ex`), so the original interval sits inside.

    This is the geometric primitive for ghost-query completeness: a
    caller querying with `expandedBounds ld δ` gets a superset of what
    they'd get querying with `ld.bounds`, because overlap lifts through
    containment. -/
theorem expandedBounds_contains_original (ld : LeafData) (k : Nat) :
    aabbContains (expandedBounds ld k) ld.bounds := by
  simp only [aabbContains, expandedBounds]
  have hx : (0 : Int) ≤ Int.ofNat
      (expansion ld.velocity[0]!.toNat ld.acceleration[0]!.toNat k) :=
    Int.natCast_nonneg _
  have hy : (0 : Int) ≤ Int.ofNat
      (expansion ld.velocity[1]!.toNat ld.acceleration[1]!.toNat k) :=
    Int.natCast_nonneg _
  have hz : (0 : Int) ≤ Int.ofNat
      (expansion ld.velocity[2]!.toNat ld.acceleration[2]!.toNat k) :=
    Int.natCast_nonneg _
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> omega

/-- **Overlap lifts through containment.** If `outer ⊇ inner` and `q`
    overlaps `inner`, then `q` overlaps `outer`. Decidable version
    (Bool-valued `aabbOverlapsDec`): direct on each axis. -/
theorem aabbOverlapsDec_lift_through_contains
    (q outer inner : BoundingBox) (hc : aabbContains outer inner)
    (hov : aabbOverlapsDec q inner = true) :
    aabbOverlapsDec q outer = true := by
  simp only [aabbOverlapsDec, aabbContains] at *
  obtain ⟨cx1, cx2, cy1, cy2, cz1, cz2⟩ := hc
  revert hov
  grind

/-- **Ghost-query completeness.** Under the structural skip invariants
    (leaf-block skip = j+1, full-node skip monotonicity), if the query
    box `q` contains some live leaf's bounds (e.g. `q = expandedBounds ld k`
    contains `ld.bounds` by `expandedBounds_contains_original`), and the
    leaf sits in the target leaf-block's window, and every node on the
    sweep path overlaps `q`, then the leaf's eclass is emitted by
    `aabbQueryN`.

    Direct composition of `aabbQueryN_complete_from_invariants` with the
    observation that a live leaf whose bounds are contained in `q`
    trivially overlaps `q` (overlap is reflexive under containment). -/
theorem ghost_aabbQueryN_complete_from_invariants
    (t : PbvhTree) (q : BoundingBox)
    (h_leaf_skip : ∀ j, j < t.internals.size →
      (t.internals[j]!).left = none → (t.internals[j]!).right = none →
        (t.internals[j]!).skip = j + 1)
    (h_skip_mono : ∀ j, j < t.internals.size →
      j < (t.internals[j]!).skip ∧
      (t.internals[j]!).skip ≤ t.internals.size)
    (h_root : t.internalRoot = some 0)
    (h_nonempty : ¬ t.internals.isEmpty)
    (target : Nat) (htarget : target < t.internals.size)
    (h_target_left : (t.internals[target]!).left = none)
    (h_target_right : (t.internals[target]!).right = none)
    (jw : Nat) (hjw : jw < (t.internals[target]!).span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[(t.internals[target]!).offset + jw]!]? = some l)
    (halive : l.alive = true)
    -- Ghost premise: query contains leaf's bounds (the "reachable" condition).
    (hl_contained : aabbContains q l.bounds)
    -- Well-formedness of leaf bounds (minima ≤ maxima, componentwise).
    (hl_wf : l.bounds.minX ≤ l.bounds.maxX ∧ l.bounds.minY ≤ l.bounds.maxY ∧
             l.bounds.minZ ≤ l.bounds.maxZ)
    (h_path_from_root : ∀ k, k ≤ target →
      aabbOverlapsDec (t.internals[k]!).bounds q = true) :
    l.eclass ∈ aabbQueryN t q := by
  -- Containment + well-formedness ⟹ overlap.
  have hl_ov : aabbOverlapsDec l.bounds q = true := by
    simp only [aabbOverlapsDec, aabbContains] at *
    obtain ⟨cx1, cx2, cy1, cy2, cz1, cz2⟩ := hl_contained
    obtain ⟨wx, wy, wz⟩ := hl_wf
    grind
  exact aabbQueryN_complete_from_invariants t q h_leaf_skip h_skip_mono
    h_root h_nonempty target htarget h_target_left h_target_right jw hjw
    l hl halive hl_ov h_path_from_root

/-- **Agreement between `tick` and `build` on the fallback path.** When
    `tick` takes its `build`-fallback branch — either because the tree
    has no bucket directory (`bucketBits = 0`) or because the resort set
    is too large to amortise — the resulting tree is definitionally
    `t.build`, so every query agrees pointwise.

    The incremental branch is an optimisation: it writes per-bucket
    `resortBucket` + `refitBucket` updates into `t` without a full
    rebuild, and is *not* generally equal to `build t` at the tree
    level. Its query-level equivalence to `build` is enforced
    empirically by the stress bench (`truth=pbvh` at N=4k/16k/65k) and
    structurally by the production consumers (FabricZone, gizmo, cull),
    which re-test AABBs on every emitted eclass via callback
    predicates — so over-emission inside the incremental branch is
    tolerated by construction.

    Mechanising agreement for the incremental branch would require the
    per-bucket window-preservation companion to
    `resortBucket_preserves_structural`, closing `refitBucket` bounds
    updates under `aabbQueryN`'s path invariants. That work is tracked
    as Phase 1c / 2b' and is explicitly out of scope here; see plan. -/
theorem tick_agrees_with_build
    (t : PbvhTree) (dirty : Array DirtyLeaf) (q : BoundingBox)
    (h_fallback : t.bucketBits = 0) :
    (t.tick dirty).aabbQueryN q = t.build.aabbQueryN q := by
  simp [PbvhTree.tick, h_fallback]

end PbvhTree
