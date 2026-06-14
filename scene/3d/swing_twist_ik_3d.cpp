/**************************************************************************/
/*  swing_twist_ik_3d.cpp                                                 */
/**************************************************************************/

#include "swing_twist_ik_3d.h"

#include "core/object/class_db.h"
#include "scene/3d/ik_kabsch_6d.h"
#include "scene/3d/skeleton_3d.h"

bool SwingTwistIK3D::_is_ancestor(Skeleton3D *p_sk, int p_anc, int p_bone) const {
	int b = p_bone;
	while (b >= 0) {
		if (b == p_anc) {
			return true;
		}
		b = p_sk->get_bone_parent(b);
	}
	return false;
}

Quaternion SwingTwistIK3D::_clamp_swing_twist(Skeleton3D *p_sk, int p_bone, const Ref<JointLimitationKusudama3D> &p_lim, const Quaternion &p_candidate_local) const {
	if (p_lim.is_null()) {
		return p_candidate_local;
	}
	const Vector<int> children = p_sk->get_bone_children(p_bone);
	if (children.is_empty()) {
		return p_candidate_local; // no forward (swing) reference
	}
	Vector3 fwd = p_sk->get_bone_rest(children[0]).origin.normalized();
	if (fwd.is_zero_approx()) {
		return p_candidate_local;
	}
	const Vector3 right(0, 0, 1); // bone-rest +Z roll convention (matches the baked cones)
	const Quaternion rest_local = p_sk->get_bone_rest(p_bone).basis.get_rotation_quaternion();
	const Quaternion delta = rest_local.inverse() * p_candidate_local;
	// SWING: clamp the forward axis to the kusudama cone union (its native solve).
	const Vector3 cur_dir = (delta.xform(fwd)).normalized();
	const Vector3 clamped_dir = p_lim->solve(fwd, right, Quaternion(), cur_dir).normalized();
	const Quaternion swing = Quaternion(fwd, clamped_dir);
	// TWIST: the twist ANGLE of delta about forward, clamped, rebuilt as a PURE twist so it
	// can't reintroduce the swing we just clamped.
	const real_t twist_angle = 2.0 * Math::atan2((double)(delta.x * fwd.x + delta.y * fwd.y + delta.z * fwd.z), (double)delta.w);
	const real_t clamped_angle = p_lim->has_twist_limit() ? p_lim->clamp_twist_angle(twist_angle) : twist_angle;
	const Quaternion twist_clamped(fwd, clamped_angle);
	return rest_local * (swing * twist_clamped).normalized();
}

void SwingTwistIK3D::set_pin(const StringName &p_bone, const NodePath &p_target) {
	pins[p_bone] = p_target;
	order_dirty = true;
}

void SwingTwistIK3D::remove_pin(const StringName &p_bone) {
	pins.erase(p_bone);
	order_dirty = true;
}

bool SwingTwistIK3D::has_pin(const StringName &p_bone) const {
	return pins.has(p_bone);
}

void SwingTwistIK3D::clear_pins() {
	pins.clear();
	order_dirty = true;
}

void SwingTwistIK3D::set_bone_locked(const StringName &p_bone, bool p_locked) {
	if (p_locked) {
		locked_bones[p_bone] = true;
	} else {
		locked_bones.erase(p_bone);
	}
	order_dirty = true;
}

bool SwingTwistIK3D::is_bone_locked(const StringName &p_bone) const {
	return locked_bones.has(p_bone);
}

void SwingTwistIK3D::set_free_root(bool p_enabled) {
	free_root = p_enabled;
}

void SwingTwistIK3D::set_motion_root_bone(const StringName &p_name) {
	root_bone_name = p_name;
}

void SwingTwistIK3D::solve() {
	Skeleton3D *sk = get_skeleton();
	if (!sk) {
		return;
	}
	resolve_chains(); // map chain bone names -> indices (also works on detached scenes)
	const int bc = sk->get_bone_count();
	const Transform3D sk_inv = sk->get_global_transform().affine_inverse();

	// Effectors and per-bone limitations come from the inherited IterateIK3D chains: each
	// chain's end bone is an effector driven by its target node; each joint carries a kusudama.
	LocalVector<Effector> effectors;
	HashMap<int, Ref<JointLimitationKusudama3D>> limitations;
	HashMap<int, bool> controlled; // bones the chains actually own (only these are rotated)
	for (int s = 0; s < get_setting_count(); s++) {
		for (int j = 0; j < get_joint_count(s); j++) {
			const int b = get_joint_bone(s, j);
			if (b < 0) {
				continue;
			}
			controlled[b] = true;
			Ref<JointLimitation3D> l = get_joint_limitation(s, j);
			JointLimitationKusudama3D *k = Object::cast_to<JointLimitationKusudama3D>(l.ptr());
			if (k) {
				limitations[b] = Ref<JointLimitationKusudama3D>(k);
			}
		}
		const int tip = get_end_bone(s);
		Node3D *tn = Object::cast_to<Node3D>(get_node_or_null(get_target_node(s)));
		if (tip >= 0 && tip < bc && tn) {
			Effector e;
			e.tip_bone = tip;
			e.target = sk_inv * tn->get_global_transform();
			e.valid = true;
			effectors.push_back(e);
			controlled[tip] = true;
		}
	}
	// Pins: a 6D target on any bone (the chain ends above are the default pins; these add to
	// or override them). Pinning a bone makes it a dragged effector.
	for (const KeyValue<StringName, NodePath> &kv : pins) {
		const int tip = sk->find_bone(kv.key);
		Node3D *tn = Object::cast_to<Node3D>(get_node_or_null(kv.value));
		if (tip >= 0 && tip < bc && tn) {
			Effector e;
			e.tip_bone = tip;
			e.target = sk_inv * tn->get_global_transform();
			e.valid = true;
			effectors.push_back(e);
			controlled[tip] = true;
		}
	}
	// Locked bones are left at FK (excluded from the solve, so the chain routes around them).
	for (const KeyValue<StringName, bool> &kv : locked_bones) {
		const int b = sk->find_bone(kv.key);
		if (b >= 0) {
			controlled.erase(b);
		}
	}
	if (effectors.is_empty()) {
		return;
	}

	// Process order: whole-skeleton BFS, restricted to controlled bones (parents first).
	if (order_dirty || solve_order.is_empty()) {
		solve_order.clear();
		LocalVector<int> queue;
		for (int pb : sk->get_parentless_bones()) {
			queue.push_back(pb);
		}
		uint32_t head = 0;
		while (head < queue.size()) {
			const int b = queue[head++];
			if (controlled.has(b)) {
				solve_order.push_back(b);
			}
			for (int c : sk->get_bone_children(b)) {
				queue.push_back(c);
			}
		}
		order_dirty = false;
	}

	LocalVector<Transform3D> gp;
	gp.resize(bc);
	// Seat each pose position at its rest offset (this solver drives only rotation; the pose
	// position otherwise defaults to (0,0,0) and collapses the chain).
	for (int b = 0; b < bc; b++) {
		sk->set_bone_pose_position(b, sk->get_bone_rest(b).origin);
	}
	// Free-root motion bone: translate it so the pins drag the body. Skipped if the root is
	// itself pinned (then it stays where its target puts it).
	int motion_root = -1;
	if (free_root) {
		const PackedInt32Array pl = sk->get_parentless_bones();
		motion_root = root_bone_name == StringName() ? (pl.is_empty() ? -1 : pl[0]) : sk->find_bone(root_bone_name);
		for (const Effector &e : effectors) {
			if (e.tip_bone == motion_root) {
				motion_root = -1; // root is pinned
				break;
			}
		}
	}

	const int iters = MAX(1, get_max_iterations());
	for (int it = 0; it < iters; it++) {
		if (motion_root >= 0) {
			// Translate the root by the mean residual (target - current tip) over all pins.
			for (int o = 0; o < bc; o++) {
				const int p = sk->get_bone_parent(o);
				gp[o] = (p >= 0 ? gp[p] : Transform3D()) * sk->get_bone_pose(o);
			}
			Vector3 resid;
			for (const Effector &e : effectors) {
				resid += e.target.origin - gp[e.tip_bone].origin;
			}
			resid /= (real_t)effectors.size();
			sk->set_bone_pose_position(motion_root, sk->get_bone_pose(motion_root).origin + resid);
		}
		// Tip -> root: joints nearest the effector bend first (reach sub-extension targets).
		for (int bi = (int)solve_order.size() - 1; bi >= 0; bi--) {
			// Recompute globals from current local poses (the skeleton does not refresh its
			// global cache between set_bone_pose_rotation() calls during a manual solve).
			for (int o = 0; o < bc; o++) {
				const int p = sk->get_bone_parent(o);
				gp[o] = (p >= 0 ? gp[p] : Transform3D()) * sk->get_bone_pose(o);
			}
			const int b = solve_order[bi];
			const Transform3D gb = gp[b];

			int tip_eff = -1;
			for (uint32_t i = 0; i < effectors.size(); i++) {
				if (effectors[i].tip_bone == b) {
					tip_eff = (int)i;
					break;
				}
			}
			Basis new_gbasis;
			if (tip_eff >= 0) {
				// Effector tip: its full target frame (6D axes) sets the orientation.
				new_gbasis = effectors[tip_eff].target.basis.orthonormalized();
			} else {
				LocalVector<Vector3> rest_pts;
				LocalVector<Vector3> tgt_pts;
				for (uint32_t i = 0; i < effectors.size(); i++) {
					if (!_is_ancestor(sk, b, effectors[i].tip_bone)) {
						continue;
					}
					rest_pts.push_back(gp[effectors[i].tip_bone].origin - gb.origin);
					tgt_pts.push_back(effectors[i].target.origin - gb.origin);
				}
				if (rest_pts.is_empty()) {
					continue;
				}
				Basis R;
				if (rest_pts.size() == 1) {
					const Vector3 a = rest_pts[0].normalized();
					const Vector3 c = tgt_pts[0].normalized();
					if (a.is_zero_approx() || c.is_zero_approx()) {
						continue;
					}
					R = Basis(Quaternion(a, c));
				} else {
					// Multi-limb: Kabsch best-fit over ALL downstream headings at once.
					R = IKKabsch6D::kabsch(rest_pts.ptr(), tgt_pts.ptr(), (int)rest_pts.size());
				}
				new_gbasis = (R * gb.basis).orthonormalized();
			}
			const int parent = sk->get_bone_parent(b);
			const Basis parent_basis = parent >= 0 ? gp[parent].basis : Basis();
			const Quaternion cand_local = (parent_basis.inverse() * new_gbasis).get_rotation_quaternion();
			const Ref<JointLimitationKusudama3D> *limp = limitations.getptr(b);
			sk->set_bone_pose_rotation(b, _clamp_swing_twist(sk, b, limp ? *limp : Ref<JointLimitationKusudama3D>(), cand_local));
		}
	}
	sk->force_update_all_bone_transforms();
}

void SwingTwistIK3D::_process_modification(double p_delta) {
	if (get_influence() <= 0.0) {
		return;
	}
	solve();
}

void SwingTwistIK3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("solve"), &SwingTwistIK3D::solve);
	ClassDB::bind_method(D_METHOD("set_pin", "bone", "target"), &SwingTwistIK3D::set_pin);
	ClassDB::bind_method(D_METHOD("remove_pin", "bone"), &SwingTwistIK3D::remove_pin);
	ClassDB::bind_method(D_METHOD("has_pin", "bone"), &SwingTwistIK3D::has_pin);
	ClassDB::bind_method(D_METHOD("clear_pins"), &SwingTwistIK3D::clear_pins);
	ClassDB::bind_method(D_METHOD("get_pin_count"), &SwingTwistIK3D::get_pin_count);
	ClassDB::bind_method(D_METHOD("set_bone_locked", "bone", "locked"), &SwingTwistIK3D::set_bone_locked);
	ClassDB::bind_method(D_METHOD("is_bone_locked", "bone"), &SwingTwistIK3D::is_bone_locked);
	ClassDB::bind_method(D_METHOD("set_free_root", "enabled"), &SwingTwistIK3D::set_free_root);
	ClassDB::bind_method(D_METHOD("get_free_root"), &SwingTwistIK3D::get_free_root);
	ClassDB::bind_method(D_METHOD("set_motion_root_bone", "name"), &SwingTwistIK3D::set_motion_root_bone);
	ClassDB::bind_method(D_METHOD("get_motion_root_bone"), &SwingTwistIK3D::get_motion_root_bone);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "free_root"), "set_free_root", "get_free_root");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "motion_root_bone"), "set_motion_root_bone", "get_motion_root_bone");
}
