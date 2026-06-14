/**************************************************************************/
/*  swing_twist_ik_3d.h                                                   */
/**************************************************************************/

#pragma once

#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "scene/3d/iterate_ik_3d.h"
#include "scene/resources/3d/joint_limitation_kusudama_3d.h"

// Whole-body, swing-twist-DIRECT IK -- a concrete IterateIK3D solver, so it is a drop-in for
// FABRIK3D/CCDIK3D and reuses the same chains / targets / per-joint Kusudama limitations.
// Unlike the per-chain solvers, it overrides the whole-body pass: each chain's end bone is a
// 6D effector (its target frame's forward = position heading -> SWING, a second axis ->
// TWIST), and every bone is rotated by a global multi-limb Kabsch best-fit over ALL its
// downstream effector position headings at once (the coupling FABRIK can't do), then twist is
// solved about the resulting forward as its own 1-DOF objective. The modular kusudama clamps
// swing (cones) and twist ([twist_from, twist_to]) in its native coordinates.
class SwingTwistIK3D : public IterateIK3D {
	GDCLASS(SwingTwistIK3D, IterateIK3D);

	struct Effector {
		int tip_bone = -1;
		Transform3D target; // skeleton-local 6D goal frame
		real_t pos_weight = 1.0; // scales this effector's pull in the weighted Kabsch
		real_t swing_weight = 1.0; // scales matching the target's forward axis at the tip
		real_t twist_weight = 1.0; // scales matching the target's roll at the tip
	};

	// One unified animator concept: a bone is PINNED (has a target -> dragged), FREE (no pin
	// -> solved by IK, the default), or LOCKED (frozen at FK). The chain end-effectors are
	// just default pins; set_pin() pins any bone.
	HashMap<StringName, NodePath> pins; // bone -> target node (overrides/adds to chain ends)
	HashMap<StringName, bool> locked_bones; // bones frozen at FK (excluded from the solve)
	bool free_root = false; // an UNPINNED motion root translates so pins (e.g. hands) drag the body
	StringName root_bone_name; // the motion root; empty -> first parentless bone

	// Per-JOINT weights, stored the IterateIK3D way: in the chain settings, exposed as
	// settings/i/joints/j/pin_weight via _get_property_list/_set/_get (so they persist + undo
	// like the per-joint limitation). position scales how hard the solver pulls that bone to its
	// target point (weighted Kabsch); orientation scales how hard it matches the target BASIS (the
	// "star"). A POLE is not a special case -- it is just a low-position, zero-orientation weight
	// on a mid joint (elbow/knee) that also carries a pin: the strong wrist owns the reach, so the
	// weak elbow can only influence the leftover roll DOF, swinging the elbow toward its target.
	// Per-joint solver weights -- the EWBIK PST (position/swing/twist) priorities plus stiffness.
	// position scales the pull to the target point; swing scales matching the target's forward
	// AXIS; twist scales matching its ROLL about that axis (swing + twist = the orientation
	// "star", split into its two physical DOF). stiffness is how much the bone resists rotating.
	struct PinWeight {
		real_t position = 1.0;
		real_t swing = 1.0;
		real_t twist = 1.0;
		real_t stiffness = 0.0; // [0..1] how much this bone RESISTS rotating: 0 = free, 1 = rigid
	};
	LocalVector<LocalVector<PinWeight>> joint_weights; // [setting][joint]; resized to the chains
	void _sync_joint_weights() const; // grow joint_weights to match the current settings/joint counts

	LocalVector<int> solve_order; // parents before children; rebuilt each solve from the live skeleton

	// Forward kinematics maintained in skeleton-local space during the manual solve.
	void _full_fk(Skeleton3D *p_sk, LocalVector<Transform3D> &p_gp) const;
	// Refresh only p_root's subtree (parents-before-children) via the flat CSR children
	// adjacency; see IKFold.lean / IKFast.lean for why this reproduces a full recompute.
	// p_stack is reused scratch to avoid per-call allocation.
	void _refresh_subtree(Skeleton3D *p_sk, LocalVector<Transform3D> &p_gp, LocalVector<int> &p_stack, const LocalVector<int> &p_child_offset, const LocalVector<int> &p_child_index, int p_root) const;
	Quaternion _clamp_swing_twist(Skeleton3D *p_sk, int p_bone, const Ref<JointLimitationKusudama3D> &p_lim, const Quaternion &p_candidate_local) const;

protected:
	static void _bind_methods();
	void _validate_property(PropertyInfo &p_property) const;
	// Store per-joint pin weights the IterateIK3D way (settings/i/joints/j/pin_weight).
	void _get_property_list(List<PropertyInfo> *p_list) const;
	bool _set(const StringName &p_name, const Variant &p_value);
	bool _get(const StringName &p_name, Variant &r_ret) const;
	virtual void _process_modification(double p_delta) override;

public:
	// PIN any bone: give it a 6D target and the solver drags the bone to it. One pin per bone;
	// the chain hands/feet/head are pinned by default. Removing a pin leaves the bone FREE.
	void set_pin(const StringName &p_bone, const NodePath &p_target);
	void remove_pin(const StringName &p_bone);
	bool has_pin(const StringName &p_bone) const;
	void clear_pins();
	int get_pin_count() const { return (int)pins.size(); }

	// LOCK a bone: freeze it at FK (the solver leaves it alone and routes around it).
	void set_bone_locked(const StringName &p_bone, bool p_locked);
	bool is_bone_locked(const StringName &p_bone) const;

	// Bulk pin/lock state as serialized properties (bone_name -> target NodePath; list of locked
	// bone names). Exposing these makes the interactive state persist in the scene AND undoable
	// via the inspector's built-in EditorUndoRedoManager (no custom gizmo needed).
	void set_pins(const Dictionary &p_pins);
	Dictionary get_pins() const;
	void set_locked_bones(const PackedStringArray &p_locked);
	PackedStringArray get_locked_bones() const;

	// Per-JOINT weights (also the mechanism for poles, soft IK, position-only goals). x = position
	// weight (pull to the target point); y = orientation weight (match the target basis, the
	// "star"). Stored with the chain joint and serialized as settings/i/joints/j/pin_weight.
	// A pole = pin the mid joint + set_joint_pin_weight(chain, mid_joint, ~0.3, 0.0).
	void set_joint_priorities(int p_index, int p_joint, real_t p_position, real_t p_swing, real_t p_twist);
	Vector3 get_joint_priorities(int p_index, int p_joint) const; // (position, swing, twist); (1,1,1) default
	// Per-bone STIFFNESS [0..1]: how much the joint resists the solver. 0 = free, 1 = rigid (a soft
	// continuous version of locking). Stored as settings/i/joints/j/stiffness.
	void set_joint_stiffness(int p_index, int p_joint, real_t p_stiffness);
	real_t get_joint_stiffness(int p_index, int p_joint) const;

	// Free root: an UNPINNED motion root translates so the pins (e.g. the hands) drag the whole
	// body; pin the root (set_pin on it) to ground/drag it directly instead.
	void set_free_root(bool p_enabled);
	bool get_free_root() const { return free_root; }
	void set_motion_root_bone(const StringName &p_name);
	StringName get_motion_root_bone() const { return root_bone_name; }

	// Run a full solve immediately (also used by tests / manual use).
	void solve();

	SwingTwistIK3D() {}
};
