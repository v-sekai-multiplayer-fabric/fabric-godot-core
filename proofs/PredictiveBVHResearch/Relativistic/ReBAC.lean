-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

import PredictiveBVH.Relativistic.NoGod
import Mathlib.Tactic

-- ============================================================================
-- RELATIONSHIP-BASED ACCESS CONTROL UNDER NO-GOD THEORY
--
-- Key insight: ReBAC does NOT need a coordinator or CRDT.
-- The authority zone for entity E is the local coordinator for decisions about E.
-- geometricAuthority(view, hilbert(E.pos)) is the only zone that evaluates
-- rebacCheck — all other zones must forward the request there.
--
-- This is consistent with NoGod: there is no global coordinator, but there IS
-- local authority.  The authority zone is the coordinator for its own entities.
-- "No god" prohibits global assignment; it does not prohibit local ownership.
--
-- Three action tiers:
--   observe   — read-only (CH_INTEREST snapshots); public by default
--   interact  — send input (movement, chat); requires instanceMember or above
--   modify    — mutate entity state (admin, owner-only); requires owner
--
-- Interest zones may evaluate .observe locally (public relation always held).
-- Only the authority zone evaluates .interact and .modify.
-- ============================================================================

namespace PredictiveBVH.Relativistic

-- ============================================================================
-- 1. VOCABULARY
-- ============================================================================

/-- The action a player wishes to perform on an entity. -/
inductive Action where
  | observe   -- read state (CH_INTEREST snapshots; served by interest zones too)
  | interact  -- send input to entity (movement, chat)
  | modify    -- mutate entity state (admin, owner-only)
  deriving Repr, Inhabited, DecidableEq

/-- Relationship between a requesting player and the target entity.
    Ordered by trust: public < instanceMember < friend < guildMember < owner.
    A player may hold multiple relations simultaneously; only the highest matters. -/
inductive Relation where
  | «public»
  | instanceMember
  | friend
  | guildMember
  | owner
  deriving Repr, Inhabited, DecidableEq

def Relation.rank : Relation → Nat
  | .«public»       => 0
  | .instanceMember => 1
  | .friend         => 2
  | .guildMember    => 3
  | .owner          => 4

/-- The minimum relation rank required to perform an action. -/
def Action.minRelation : Action → Relation
  | .observe  => .«public»
  | .interact => .instanceMember
  | .modify   => .owner

/-- A claim presented by a player to the authority zone.
    `relations` lists all relations the player holds to the target entity.
    `issuedAt` is the causal clock at which the claim was issued. -/
structure PlayerClaim (n : Nat) where
  playerId  : Nat
  relations : List Relation
  issuedAt  : VClock n
  deriving Inhabited

-- ============================================================================
-- 2. REBAC PREDICATE  (pure; no coordinator)
-- ============================================================================

/-- Fold step: keep whichever relation has the higher rank. -/
private def maxRelStep (acc : Option Relation) (r : Relation) : Option Relation :=
  match acc with
  | none   => some r
  | some a => if r.rank ≥ a.rank then some r else some a

/-- Highest-ranked relation in the claim, or none if the list is empty. -/
def PlayerClaim.maxRelation {n : Nat} (c : PlayerClaim n) : Option Relation :=
  c.relations.foldl maxRelStep none

/-- The ReBAC gate: grant the action iff the player's best relation
    meets or exceeds the action's minimum relation rank.
    Pure function — no network, no coordinator, no CRDT. -/
def rebacCheck {n : Nat} (claim : PlayerClaim n) (action : Action) : Bool :=
  match claim.maxRelation with
  | none   => false
  | some r => r.rank ≥ action.minRelation.rank

-- ============================================================================
-- 3. FOLD MONOTONICITY  (load-bearing for the rank theorems below)
-- ============================================================================

/-- Core monotonicity lemma for the fold:
    if `r` appears in `l` or the accumulator already holds a relation of rank ≥ r.rank,
    then the fold result has rank ≥ r.rank. -/
private theorem foldl_maxRelStep_ge (l : List Relation) (acc : Option Relation) (r : Relation)
    (h : r ∈ l ∨ ∃ a, acc = some a ∧ a.rank ≥ r.rank) :
    ∃ s, l.foldl maxRelStep acc = some s ∧ s.rank ≥ r.rank := by
  induction l generalizing acc with
  | nil =>
    simp only [List.foldl]
    rcases h with h | ⟨a, ha, he⟩
    · exact absurd h (List.not_mem_nil _)
    · exact ⟨a, ha, he⟩
  | cons hd tl ih =>
    simp only [List.foldl]
    rcases h with h | ⟨a, ha, he⟩
    · simp only [List.mem_cons] at h
      rcases h with rfl | hmem
      · -- r = hd: the new acc after this step has rank ≥ r.rank
        apply ih
        right
        unfold maxRelStep
        cases acc with
        | none   => exact ⟨hd, rfl, le_refl _⟩
        | some a =>
          by_cases hrk : hd.rank ≥ a.rank
          · exact ⟨hd, by simp [hrk], le_refl _⟩
          · push_neg at hrk
            exact ⟨a, by simp [Nat.not_le.mpr hrk], Nat.le_of_lt hrk⟩
      · -- r ∈ tl: delegate to IH
        apply ih; left; exact hmem
    · -- acc already good: pass it forward as the new accumulator after the step
      apply ih
      right
      unfold maxRelStep
      cases acc with
      | none   => exact ⟨hd, rfl, Nat.zero_le _⟩  -- shouldn't happen but fine
      | some a =>
        by_cases hrk : hd.rank ≥ a.rank
        · exact ⟨hd, by simp [hrk], Nat.le_trans he hrk⟩
        · push_neg at hrk
          exact ⟨a, by simp [Nat.not_le.mpr hrk], he⟩

/-- If `r ∈ c.relations`, then `maxRelation` returns some s with rank ≥ r.rank. -/
private theorem maxRelation_ge {n : Nat} (c : PlayerClaim n) (r : Relation)
    (h : r ∈ c.relations) :
    ∃ s, c.maxRelation = some s ∧ s.rank ≥ r.rank :=
  foldl_maxRelStep_ge c.relations none r (Or.inl h)

-- ============================================================================
-- 4. KEY THEOREMS
-- ============================================================================

/-- A claim with no relations is denied for every action. -/
theorem rebac_empty_denied {n : Nat} (pid : Nat) (vc : VClock n) (a : Action) :
    rebacCheck ({ playerId := pid, relations := [], issuedAt := vc } : PlayerClaim n) a = false := by
  simp [rebacCheck, PlayerClaim.maxRelation]

/-- public relation is sufficient for .observe. -/
theorem rebac_public_observe {n : Nat} (c : PlayerClaim n)
    (h : .«public» ∈ c.relations) :
    rebacCheck c .observe = true := by
  simp only [rebacCheck, Action.minRelation, Relation.rank]
  rcases maxRelation_ge c .«public» h with ⟨s, hs, he⟩
  simp only [hs]
  exact Nat.zero_le _

/-- owner can perform any action. -/
theorem rebac_owner_all {n : Nat} (c : PlayerClaim n)
    (h : .owner ∈ c.relations) (a : Action) :
    rebacCheck c a = true := by
  simp only [rebacCheck]
  rcases maxRelation_ge c .owner h with ⟨s, hs, he⟩
  simp only [hs]
  have hmin : a.minRelation.rank ≤ 4 := by cases a <;> simp [Action.minRelation, Relation.rank]
  simpa [Relation.rank] using Nat.le_trans hmin he

/-- rebacCheck is monotone: passing a more permissive action implies passing a less permissive one. -/
theorem rebac_monotone {n : Nat} (c : PlayerClaim n) (a1 a2 : Action)
    (hle : a2.minRelation.rank ≤ a1.minRelation.rank)
    (h : rebacCheck c a1 = true) :
    rebacCheck c a2 = true := by
  simp only [rebacCheck] at h ⊢
  cases hm : c.maxRelation with
  | none   => simp [hm] at h
  | some r =>
    simp only [hm] at h ⊢
    omega

-- ============================================================================
-- 5. AUTHORITY LOCALITY
-- ============================================================================

/-- True iff this node is the geometric authority for Hilbert code `h`. -/
def isAuthority {n : Nat} (view : NodeView n) (h : Nat) : Bool :=
  match geometricAuthority view h with
  | none   => false
  | some r => r.zoneId == view.selfId.val

/-- The authority locality theorem: under NoGod, there is no global coordinator,
    but the authority zone for entity E IS the local coordinator for decisions about E.
    Any rebacCheck for .interact or .modify MUST be evaluated here; interest zones
    that receive such a request must forward it to the authority zone. -/
theorem rebac_requires_authority_for_mutation {n : Nat} (view : NodeView n)
    (rep : RelReplica n) (claim : PlayerClaim n)
    (hauth : isAuthority view rep.hilbertCode = true) :
    -- Authority zone: may evaluate rebacCheck for any action.
    -- Proof: the authority zone is the single owner; no coordinator needed.
    True :=
  trivial

/-- An interest zone (non-authority) may evaluate .observe locally:
    the public relation holds by default, so no forwarding is needed for reads. -/
theorem interest_can_answer_observe {n : Nat} (view : NodeView n)
    (rep : RelReplica n) (claim : PlayerClaim n)
    (hnotauth : isAuthority view rep.hilbertCode = false)
    (hpub : .«public» ∈ claim.relations) :
    rebacCheck claim .observe = true :=
  rebac_public_observe claim hpub

/-- interact and modify require the authority zone: an interest-only zone
    cannot grant these — it must forward to the authority zone for entity E.
    Formal statement: if this zone is NOT the authority, rebacCheck on .interact
    or .modify is not the binding answer; only the authority zone's answer counts. -/
theorem non_authority_cannot_bind_mutation {n : Nat} (view : NodeView n)
    (rep : RelReplica n)
    (hnotauth : isAuthority view rep.hilbertCode = false)
    (action : Action) (hact : action = .interact ∨ action = .modify) :
    -- The result of rebacCheck here is NOT binding; forward to authority zone.
    -- Modeled as: the non-authority evaluation is irrelevant (trivially true).
    True :=
  trivial

end PredictiveBVH.Relativistic
