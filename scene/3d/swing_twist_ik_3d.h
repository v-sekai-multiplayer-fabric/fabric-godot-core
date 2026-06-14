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
		bool valid = false;
	};

	LocalVector<int> solve_order; // parents before children (whole skeleton)
	bool order_dirty = true;

	void _rebuild_order(Skeleton3D *p_sk);
	bool _is_ancestor(Skeleton3D *p_sk, int p_anc, int p_bone) const;
	Quaternion _clamp_swing_twist(Skeleton3D *p_sk, int p_bone, const Ref<JointLimitationKusudama3D> &p_lim, const Quaternion &p_candidate_local) const;

protected:
	static void _bind_methods();
	virtual void _process_modification(double p_delta) override;

public:
	// Run a full solve immediately (also used by tests / manual use).
	void solve();

	SwingTwistIK3D() {}
};
