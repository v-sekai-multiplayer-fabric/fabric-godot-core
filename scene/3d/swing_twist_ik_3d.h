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
	};

	// One unified animator concept: a bone is PINNED (has a target -> dragged), FREE (no pin
	// -> solved by IK, the default), or LOCKED (frozen at FK). The chain end-effectors are
	// just default pins; set_pin() pins any bone.
	HashMap<StringName, NodePath> pins; // bone -> target node (overrides/adds to chain ends)
	HashMap<StringName, bool> locked_bones; // bones frozen at FK (excluded from the solve)
	bool free_root = false; // an UNPINNED motion root translates so pins (e.g. hands) drag the body
	StringName root_bone_name; // the motion root; empty -> first parentless bone

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
