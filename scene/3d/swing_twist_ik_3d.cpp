/**************************************************************************/
/*  swing_twist_ik_3d.cpp                                                 */
/**************************************************************************/

#include "swing_twist_ik_3d.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "scene/3d/ik_kabsch_6d.h"
#include "scene/3d/skeleton_3d.h"

// A usable target frame: finite, non-degenerate. (Reflections are allowed here and fixed to a
// proper rotation where the orientation is consumed.)
static bool st_target_valid(const Transform3D &p_t) {
	return p_t.origin.is_finite() &&
			p_t.basis.get_column(0).is_finite() && p_t.basis.get_column(1).is_finite() && p_t.basis.get_column(2).is_finite() &&
			Math::abs(p_t.basis.determinant()) > (real_t)1e-9;
}

// Proper (right-handed, det +1) rotation from a possibly-mirrored target basis.
static Basis st_proper_rotation(const Basis &p_b) {
	Basis o = p_b.orthonormalized();
	if (o.determinant() < 0.0) {
		o.set_column(2, -o.get_column(2)); // flip a column to remove the reflection
	}
	return o;
}

void SwingTwistIK3D::_full_fk(Skeleton3D *p_sk, LocalVector<Transform3D> &p_gp) const {
	const int bc = p_sk->get_bone_count();
	for (int o = 0; o < bc; o++) {
		const int p = p_sk->get_bone_parent(o); // bones are parent-before-child in index order
		p_gp[o] = (p >= 0 ? p_gp[p] : Transform3D()) * p_sk->get_bone_pose(o);
	}
}

void SwingTwistIK3D::_refresh_subtree(Skeleton3D *p_sk, LocalVector<Transform3D> &p_gp, LocalVector<int> &p_stack, const LocalVector<int> &p_child_offset, const LocalVector<int> &p_child_index, int p_root) const {
	p_stack.clear();
	p_stack.push_back(p_root);
	while (!p_stack.is_empty()) {
		const int x = p_stack[p_stack.size() - 1];
		p_stack.resize(p_stack.size() - 1);
		const int p = p_sk->get_bone_parent(x);
		p_gp[x] = (p >= 0 ? p_gp[p] : Transform3D()) * p_sk->get_bone_pose(x); // parent already current
		for (int k = p_child_offset[x]; k < p_child_offset[x + 1]; k++) {
			p_stack.push_back(p_child_index[k]);
		}
	}
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
}

void SwingTwistIK3D::remove_pin(const StringName &p_bone) {
	pins.erase(p_bone);
}

bool SwingTwistIK3D::has_pin(const StringName &p_bone) const {
	return pins.has(p_bone);
}

void SwingTwistIK3D::clear_pins() {
	pins.clear();
}

void SwingTwistIK3D::set_bone_locked(const StringName &p_bone, bool p_locked) {
	if (p_locked) {
		locked_bones[p_bone] = true;
	} else {
		locked_bones.erase(p_bone);
	}
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

void SwingTwistIK3D::set_pins(const Dictionary &p_pins) {
	pins.clear();
	const Array keys = p_pins.keys();
	for (int i = 0; i < keys.size(); i++) {
		pins[StringName(keys[i])] = NodePath(p_pins[keys[i]]);
	}
}

Dictionary SwingTwistIK3D::get_pins() const {
	Dictionary d;
	for (const KeyValue<StringName, NodePath> &kv : pins) {
		d[kv.key] = kv.value;
	}
	return d;
}

void SwingTwistIK3D::set_locked_bones(const Array &p_locked) {
	locked_bones.clear();
	for (int i = 0; i < p_locked.size(); i++) {
		locked_bones[StringName(p_locked[i])] = true;
	}
}

Array SwingTwistIK3D::get_locked_bones() const {
	Array a;
	for (const KeyValue<StringName, bool> &kv : locked_bones) {
		a.push_back(String(kv.key));
	}
	return a;
}

void SwingTwistIK3D::_sync_joint_weights() const {
	// Grow the per-joint weight store to match the current chain settings/joint counts. const
	// because _get_property_list/_get are const; the store is logically a cache of the chains.
	LocalVector<LocalVector<PinWeight>> &jw = const_cast<SwingTwistIK3D *>(this)->joint_weights;
	const int sc = get_setting_count();
	if ((int)jw.size() < sc) {
		jw.resize(sc);
	}
	for (int i = 0; i < sc; i++) {
		const int jc = get_joint_count(i);
		if ((int)jw[i].size() < jc) {
			jw[i].resize(jc); // new entries default to (1,1)
		}
	}
}

void SwingTwistIK3D::set_joint_priorities(int p_index, int p_joint, real_t p_position, real_t p_swing, real_t p_twist) {
	_sync_joint_weights();
	ERR_FAIL_INDEX(p_index, (int)joint_weights.size());
	ERR_FAIL_INDEX(p_joint, (int)joint_weights[p_index].size());
	joint_weights[p_index][p_joint].position = MAX((real_t)0.0, p_position);
	joint_weights[p_index][p_joint].swing = CLAMP(p_swing, (real_t)0.0, (real_t)1.0);
	joint_weights[p_index][p_joint].twist = CLAMP(p_twist, (real_t)0.0, (real_t)1.0);
}

Vector3 SwingTwistIK3D::get_joint_priorities(int p_index, int p_joint) const {
	_sync_joint_weights();
	if (p_index < 0 || p_index >= (int)joint_weights.size() || p_joint < 0 || p_joint >= (int)joint_weights[p_index].size()) {
		return Vector3(1.0, 1.0, 1.0);
	}
	const PinWeight &w = joint_weights[p_index][p_joint];
	return Vector3(w.position, w.swing, w.twist);
}

void SwingTwistIK3D::set_joint_stiffness(int p_index, int p_joint, real_t p_stiffness) {
	_sync_joint_weights();
	ERR_FAIL_INDEX(p_index, (int)joint_weights.size());
	ERR_FAIL_INDEX(p_joint, (int)joint_weights[p_index].size());
	joint_weights[p_index][p_joint].stiffness = CLAMP(p_stiffness, (real_t)0.0, (real_t)1.0);
}

real_t SwingTwistIK3D::get_joint_stiffness(int p_index, int p_joint) const {
	_sync_joint_weights();
	if (p_index < 0 || p_index >= (int)joint_weights.size() || p_joint < 0 || p_joint >= (int)joint_weights[p_index].size()) {
		return 0.0;
	}
	return joint_weights[p_index][p_joint].stiffness;
}

void SwingTwistIK3D::set_joint_engage(int p_index, int p_joint, real_t p_engage) {
	_sync_joint_weights();
	ERR_FAIL_INDEX(p_index, (int)joint_weights.size());
	ERR_FAIL_INDEX(p_joint, (int)joint_weights[p_index].size());
	joint_weights[p_index][p_joint].engage = CLAMP(p_engage, (real_t)0.0, (real_t)1.0);
}

real_t SwingTwistIK3D::get_joint_engage(int p_index, int p_joint) const {
	_sync_joint_weights();
	if (p_index < 0 || p_index >= (int)joint_weights.size() || p_joint < 0 || p_joint >= (int)joint_weights[p_index].size()) {
		return 0.0;
	}
	return joint_weights[p_index][p_joint].engage;
}

void SwingTwistIK3D::set_joint_isolation(int p_index, int p_joint, real_t p_isolation) {
	_sync_joint_weights();
	ERR_FAIL_INDEX(p_index, (int)joint_weights.size());
	ERR_FAIL_INDEX(p_joint, (int)joint_weights[p_index].size());
	joint_weights[p_index][p_joint].isolation = CLAMP(p_isolation, (real_t)0.0, (real_t)1.0);
}

real_t SwingTwistIK3D::get_joint_isolation(int p_index, int p_joint) const {
	_sync_joint_weights();
	if (p_index < 0 || p_index >= (int)joint_weights.size() || p_joint < 0 || p_joint >= (int)joint_weights[p_index].size()) {
		return 0.0;
	}
	return joint_weights[p_index][p_joint].isolation;
}

void SwingTwistIK3D::set_joint_relax(int p_index, int p_joint, real_t p_relax) {
	_sync_joint_weights();
	ERR_FAIL_INDEX(p_index, (int)joint_weights.size());
	ERR_FAIL_INDEX(p_joint, (int)joint_weights[p_index].size());
	joint_weights[p_index][p_joint].relax = CLAMP(p_relax, (real_t)0.0, (real_t)1.0);
}

real_t SwingTwistIK3D::get_joint_relax(int p_index, int p_joint) const {
	_sync_joint_weights();
	if (p_index < 0 || p_index >= (int)joint_weights.size() || p_joint < 0 || p_joint >= (int)joint_weights[p_index].size()) {
		return 0.0;
	}
	return joint_weights[p_index][p_joint].relax;
}

void SwingTwistIK3D::_get_joint_extra_properties(int p_setting, int p_joint, const String &p_path, LocalVector<PropertyInfo> &p_props) const {
	// Emitted inside the base joint loop (the FABRIK/CCD pattern), so these interleave with the
	// joint's other properties instead of forming a second "settings" block. PST priorities
	// (x = position, y = swing, z = twist) + the damp-family knobs. A pole = low position, swing =
	// twist = 0 on a mid joint.
	_sync_joint_weights();
	p_props.push_back(PropertyInfo(Variant::VECTOR3, p_path + "priorities"));
	p_props.push_back(PropertyInfo(Variant::FLOAT, p_path + "stiffness", PROPERTY_HINT_RANGE, "0,1,0.01"));
	p_props.push_back(PropertyInfo(Variant::FLOAT, p_path + "engage", PROPERTY_HINT_RANGE, "0,1,0.01"));
	p_props.push_back(PropertyInfo(Variant::FLOAT, p_path + "isolation", PROPERTY_HINT_RANGE, "0,1,0.01"));
	p_props.push_back(PropertyInfo(Variant::FLOAT, p_path + "relax", PROPERTY_HINT_RANGE, "0,1,0.01"));
}

bool SwingTwistIK3D::_set(const StringName &p_name, const Variant &p_value) {
	const String n = p_name;
	if (n.begins_with("settings/")) {
		const Vector<String> parts = n.split("/");
		if (parts.size() == 5 && parts[4] == "priorities") {
			const Vector3 v = p_value;
			set_joint_priorities(parts[1].to_int(), parts[3].to_int(), v.x, v.y, v.z);
			return true;
		}
		if (parts.size() == 5 && parts[4] == "stiffness") {
			set_joint_stiffness(parts[1].to_int(), parts[3].to_int(), p_value);
			return true;
		}
		if (parts.size() == 5 && parts[4] == "engage") {
			set_joint_engage(parts[1].to_int(), parts[3].to_int(), p_value);
			return true;
		}
		if (parts.size() == 5 && parts[4] == "isolation") {
			set_joint_isolation(parts[1].to_int(), parts[3].to_int(), p_value);
			return true;
		}
		if (parts.size() == 5 && parts[4] == "relax") {
			set_joint_relax(parts[1].to_int(), parts[3].to_int(), p_value);
			return true;
		}
	}
	return IterateIK3D::_set(p_name, p_value);
}

bool SwingTwistIK3D::_get(const StringName &p_name, Variant &r_ret) const {
	const String n = p_name;
	if (n.begins_with("settings/")) {
		const Vector<String> parts = n.split("/");
		if (parts.size() == 5 && parts[4] == "priorities") {
			r_ret = get_joint_priorities(parts[1].to_int(), parts[3].to_int());
			return true;
		}
		if (parts.size() == 5 && parts[4] == "stiffness") {
			r_ret = get_joint_stiffness(parts[1].to_int(), parts[3].to_int());
			return true;
		}
		if (parts.size() == 5 && parts[4] == "engage") {
			r_ret = get_joint_engage(parts[1].to_int(), parts[3].to_int());
			return true;
		}
		if (parts.size() == 5 && parts[4] == "isolation") {
			r_ret = get_joint_isolation(parts[1].to_int(), parts[3].to_int());
			return true;
		}
		if (parts.size() == 5 && parts[4] == "relax") {
			r_ret = get_joint_relax(parts[1].to_int(), parts[3].to_int());
			return true;
		}
	}
	return IterateIK3D::_get(p_name, r_ret);
}

void SwingTwistIK3D::solve() {
	Skeleton3D *sk = get_skeleton();
	if (!sk) {
		return;
	}
	// Resolve chain bone names -> indices only when they are NOT already resolved (joints empty).
	// resolve_chains() runs the base setters, which call notify_property_list_changed() and
	// rebuild gizmos; doing that every solve thrashed the editor inspector (continuous rebuilds)
	// on selection. In a loaded scene / the editor the chains are already resolved by the
	// load/setter flow, so this fires at most once (e.g. to bootstrap a detached test rig).
	int resolved_joints = 0;
	for (int s = 0; s < get_setting_count(); s++) {
		resolved_joints += get_joint_count(s);
	}
	if (resolved_joints == 0) {
		resolve_chains();
	}
	const int bc = sk->get_bone_count();
	const Transform3D sk_inv = sk->get_global_transform().affine_inverse();

	// Effectors and per-bone limitations come from the inherited IterateIK3D chains: each
	// chain's end bone is an effector driven by its target node; each joint carries a kusudama.
	LocalVector<Effector> effectors;
	HashMap<int, Ref<JointLimitationKusudama3D>> limitations;
	HashMap<int, bool> controlled; // bones the chains actually own (only these are rotated)
	HashMap<int, PinWeight> bone_weight; // bone index -> per-joint weight (the "star"/pole knobs)
	_sync_joint_weights();
	for (int s = 0; s < get_setting_count(); s++) {
		for (int j = 0; j < get_joint_count(s); j++) {
			const int b = get_joint_bone(s, j);
			if (b < 0) {
				continue;
			}
			controlled[b] = true;
			if (s < (int)joint_weights.size() && j < (int)joint_weights[s].size()) {
				bone_weight[b] = joint_weights[s][j];
			}
			Ref<JointLimitation3D> l = get_joint_limitation(s, j);
			JointLimitationKusudama3D *k = Object::cast_to<JointLimitationKusudama3D>(l.ptr());
			if (k) {
				limitations[b] = Ref<JointLimitationKusudama3D>(k);
			}
		}
		const int tip = get_end_bone(s);
		Node3D *tn = Object::cast_to<Node3D>(get_node_or_null(get_target_node(s)));
		if (tip >= 0 && tip < bc && tn) {
			const Transform3D tgt = sk_inv * tn->get_global_transform();
			if (st_target_valid(tgt)) {
				Effector e;
				e.tip_bone = tip;
				e.target = tgt;
				if (const PinWeight *pw = bone_weight.getptr(tip)) {
					e.pos_weight = pw->position;
					e.swing_weight = pw->swing;
					e.twist_weight = pw->twist;
				}
				effectors.push_back(e);
				controlled[tip] = true;
			}
		}
	}
	// Pins: a 6D target on any bone (the chain ends above are the default pins; these add to
	// or override them). Pinning a bone makes it a dragged effector.
	for (const KeyValue<StringName, NodePath> &kv : pins) {
		const int tip = sk->find_bone(kv.key);
		Node3D *tn = Object::cast_to<Node3D>(get_node_or_null(kv.value));
		if (tip >= 0 && tip < bc && tn) {
			const Transform3D tgt = sk_inv * tn->get_global_transform();
			if (st_target_valid(tgt)) {
				Effector e;
				e.tip_bone = tip;
				e.target = tgt;
				if (const PinWeight *pw = bone_weight.getptr(tip)) {
					e.pos_weight = pw->position;
					e.swing_weight = pw->swing;
					e.twist_weight = pw->twist;
				}
				effectors.push_back(e);
				controlled[tip] = true;
			}
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

	// CSR children adjacency (flat offset+index arrays): get_bone_children() returns a
	// Vector<int> BY VALUE (a heap allocation per call), which the per-bone subtree refresh and
	// the BFS below would hit in their loops. Built fresh each solve from the live skeleton, so
	// it can never go stale. (childrenOf equivalence proven in misc/humanoid_kusudama_rom/lean/
	// IKFast.lean.)
	LocalVector<int> child_offset;
	child_offset.resize(bc + 1);
	for (int b = 0; b <= bc; b++) {
		child_offset[b] = 0;
	}
	for (int b = 0; b < bc; b++) {
		const int p = sk->get_bone_parent(b);
		if (p >= 0) {
			child_offset[p + 1]++;
		}
	}
	for (int b = 0; b < bc; b++) {
		child_offset[b + 1] += child_offset[b];
	}
	LocalVector<int> child_index;
	child_index.resize(child_offset[bc]);
	LocalVector<int> child_cursor;
	child_cursor.resize(bc);
	for (int b = 0; b < bc; b++) {
		child_cursor[b] = child_offset[b];
	}
	for (int b = 0; b < bc; b++) {
		const int p = sk->get_bone_parent(b);
		if (p >= 0) {
			child_index[child_cursor[p]++] = b;
		}
	}

	// Process order: whole-skeleton BFS over the CSR adjacency, restricted to controlled bones
	// (parents first). Rebuilt every solve -- it depends on the live skeleton structure AND the
	// controlled set (chains/pins/locks), neither of which has a reliable single dirty signal, so
	// caching it risked stale bone indices (out-of-bounds into gp) after a skeleton/chain change.
	// The BFS is O(bones) over a no-alloc adjacency, so rebuilding is cheap.
	solve_order.clear();
	{
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
			for (int k = child_offset[b]; k < child_offset[b + 1]; k++) {
				queue.push_back(child_index[k]);
			}
		}
	}

	// Downstream-effector table, built once (O(effectors * depth)): for each controlled bone,
	// the indices of effectors lying in its subtree. Replaces the per-iteration _is_ancestor
	// rescan; indexed by solve_order position. (downstream-table equivalence is proven in
	// IKFast.lean; the walk preserves effector order, so the Kabsch input is bit-identical.)
	HashMap<int, int> order_index;
	for (uint32_t i = 0; i < solve_order.size(); i++) {
		order_index[solve_order[i]] = (int)i;
	}
	LocalVector<LocalVector<int>> down_by_order;
	LocalVector<LocalVector<real_t>> down_transmit; // per (bone, effector): isolation-attenuated weight
	down_by_order.resize(solve_order.size());
	down_transmit.resize(solve_order.size());
	HashMap<int, real_t> effector_isolation; // an effector bone's isolation blocks it from ancestors above
	for (uint32_t i = 0; i < effectors.size(); i++) {
		const PinWeight *pw = bone_weight.getptr(effectors[i].tip_bone);
		effector_isolation[effectors[i].tip_bone] = pw ? pw->isolation : (real_t)0.0;
	}
	for (uint32_t i = 0; i < effectors.size(); i++) {
		int x = effectors[i].tip_bone;
		real_t transmit = 1.0;
		bool first = true;
		while (x >= 0) {
			const int *oi = order_index.getptr(x);
			if (oi) {
				down_by_order[*oi].push_back((int)i);
				down_transmit[*oi].push_back(transmit);
			}
			// An intervening pin (x, not the source tip) with isolation attenuates this effector's
			// pull on every ancestor ABOVE x.
			if (!first) {
				const real_t *iso = effector_isolation.getptr(x);
				if (iso && *iso > (real_t)0.0) {
					transmit *= (real_t)1.0 - *iso;
				}
			}
			first = false;
			x = sk->get_bone_parent(x);
		}
	}

	// Solver knobs inherited from IterateIK3D, all honored below: max_iterations (loop bound),
	// angular_delta_limit (per-step jerk cap), min_distance (early-out), and influence (blend).
	// `deterministic` is always satisfied -- this solve has a fixed tip->root order and no
	// randomness, so it is deterministic regardless of the flag.
	const double min_d_sq = get_min_distance() * get_min_distance();
	const real_t infl = get_influence();
	LocalVector<Quaternion> orig_rot; // pre-solve local rotations of the rotated bones (influence blend)
	if (infl < (real_t)1.0) {
		orig_rot.resize(solve_order.size());
		for (uint32_t i = 0; i < solve_order.size(); i++) {
			orig_rot[i] = sk->get_bone_pose_rotation(solve_order[i]);
		}
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

	// The skeleton does not refresh its global cache between set_bone_pose_*() calls during a
	// manual solve, so we maintain `gp` (skeleton-local globals) ourselves. Editing one bone's
	// local pose only changes that bone's SUBTREE, so instead of recomputing the whole skeleton
	// before every bone (the old O(iters*joints*bones) cost), we keep `gp` consistent with one
	// full pass, then refresh only the edited bone's subtree after each edit -- provably the
	// same globals as full recompute (misc/humanoid_kusudama_rom/lean/IKFold.lean).
	LocalVector<int> refresh_stack; // reused scratch for _refresh_subtree
	_full_fk(sk, gp); // one consistent baseline; the invariant is then maintained incrementally

	const int iters = MAX(1, get_max_iterations());
	for (int it = 0; it < iters; it++) {
		if (motion_root >= 0) {
			// Translate the root by the mean residual (target - current tip) over all pins.
			Vector3 resid;
			for (const Effector &e : effectors) {
				resid += e.target.origin - gp[e.tip_bone].origin;
			}
			resid /= (real_t)effectors.size();
			sk->set_bone_pose_position(motion_root, sk->get_bone_pose(motion_root).origin + resid);
			_refresh_subtree(sk, gp, refresh_stack, child_offset, child_index, motion_root); // root moved
		}
		// Tip -> root: joints nearest the effector bend first (reach sub-extension targets).
		for (int bi = (int)solve_order.size() - 1; bi >= 0; bi--) {
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
				// Effector tip: match the target frame, but split the orientation delta into its
				// SWING (aim the forward axis) and TWIST (roll about it) parts and scale each by its
				// PST priority. swing=twist=1 -> full 6D match; both 0 -> keep FK orientation
				// (position-only goal); independent values let an animator match aim but free the
				// roll, etc. The split uses the bone's forward (its first child's rest dir).
				const Effector &te = effectors[tip_eff];
				const Basis tgt_basis = st_proper_rotation(te.target.basis);
				if (te.swing_weight >= (real_t)1.0 && te.twist_weight >= (real_t)1.0) {
					new_gbasis = tgt_basis;
				} else {
					const Quaternion cur_q = gp[b].basis.get_rotation_quaternion();
					const Quaternion delta = tgt_basis.get_rotation_quaternion() * cur_q.inverse(); // global cur->tgt
					// twist axis = current global forward.
					Vector3 f_local(0, 1, 0);
					const Vector<int> ch = sk->get_bone_children(b);
					if (!ch.is_empty()) {
						const Vector3 d = sk->get_bone_rest(ch[0]).origin.normalized();
						if (!d.is_zero_approx()) {
							f_local = d;
						}
					}
					const Vector3 f = gp[b].basis.xform(f_local).normalized();
					// swing-twist decomposition of `delta` about f.
					const Vector3 ra(delta.x, delta.y, delta.z);
					const Vector3 proj = f * ra.dot(f);
					Quaternion twist(proj.x, proj.y, proj.z, delta.w);
					if (twist.length_squared() < (real_t)CMP_EPSILON) {
						twist = Quaternion();
					} else {
						twist.normalize();
					}
					const Quaternion swing = (delta * twist.inverse()).normalized();
					// Scale each component's angle by its priority (q^w = slerp(identity, q, w)).
					const Quaternion sw = Quaternion().slerp(swing, te.swing_weight);
					const Quaternion tw = Quaternion().slerp(twist, te.twist_weight);
					new_gbasis = Basis((sw * tw * cur_q).normalized());
				}
			} else {
				const LocalVector<int> &downstream = down_by_order[bi];
				const LocalVector<real_t> &dtransmit = down_transmit[bi];
				if (downstream.is_empty()) {
					continue; // no downstream effector pulls this bone
				}
				LocalVector<Vector3> rest_pts;
				LocalVector<Vector3> tgt_pts;
				for (uint32_t k = 0; k < downstream.size(); k++) {
					const Effector &e = effectors[downstream[k]];
					// Weighted Kabsch: scaling a correspondence pair by sqrt(w) scales its term in
					// the covariance Sum(w * rest (X) tgt) by w. A low-weight pin (e.g. an elbow
					// "pole") thus only nudges the fit -- the strong wrist pin dominates the reach.
					// dtransmit folds in isolation (intervening pins blocking this pull).
					const real_t sw = Math::sqrt(MAX((real_t)0.0, e.pos_weight * dtransmit[k]));
					rest_pts.push_back((gp[e.tip_bone].origin - gb.origin) * sw);
					tgt_pts.push_back((e.target.origin - gb.origin) * sw);
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
			Quaternion target_local = _clamp_swing_twist(sk, b, limp ? *limp : Ref<JointLimitationKusudama3D>(), cand_local);
			const Quaternion prev_local = sk->get_bone_pose_rotation(b);
			if (const PinWeight *pw = bone_weight.getptr(b)) {
				// ENGAGE: ramp the bone in over the solve (0 = full from the start). Lets distal
				// joints settle before proximal ones engage, etc.
				if (pw->engage > (real_t)0.0) {
					const real_t t = ((real_t)it + (real_t)1.0) / (real_t)iters; // solve progress
					const real_t ramp = CLAMP((t - pw->engage) / MAX((real_t)1e-3, (real_t)1.0 - pw->engage), (real_t)0.0, (real_t)1.0);
					target_local = prev_local.slerp(target_local, ramp);
				}
				// STIFFNESS: a soft, continuous resistance to rotating. 1 holds the bone (rigid),
				// 0 lets it move freely; in between it keeps a fraction of its prior pose.
				if (pw->stiffness > (real_t)0.0) {
					target_local = prev_local.slerp(target_local, MAX((real_t)0.0, (real_t)1.0 - pw->stiffness));
				}
				// RELAX: pull the target toward the bone's REST pose. The effectors re-assert the
				// reach each iteration, so this only claims the slack they leave free; at 1 the bone
				// sits at rest (reach abandoned).
				if (pw->relax > (real_t)0.0) {
					const Quaternion rest_q = sk->get_bone_rest(b).basis.get_rotation_quaternion();
					target_local = target_local.slerp(rest_q, pw->relax);
				}
			}
			// Rate-limit the per-iteration rotation delta (mirrors IterateIK3D's angular_delta_limit):
			// at a kinematic fold the candidate can flip ~180deg in one step; slerping the delta down
			// to the limit spreads that across iterations/frames so the joint sweeps smoothly instead
			// of teleporting (bounded per-step angle => bounded jerk). At alignment diff~0 => no change,
			// so the "hits the marker when aligned" fixed point is preserved.
			const double diff = prev_local.angle_to(target_local);
			const double adl = get_angular_delta_limit();
			if (diff > adl && !Math::is_zero_approx(diff)) {
				target_local = prev_local.slerp(target_local, adl / diff);
			}
			sk->set_bone_pose_rotation(b, target_local);
			_refresh_subtree(sk, gp, refresh_stack, child_offset, child_index, b); // refresh b's subtree, keep gp consistent
		}
		// Early-out (min_distance): stop once every effector is within min_distance of its target.
		double worst_sq = 0.0;
		for (const Effector &e : effectors) {
			worst_sq = MAX(worst_sq, (double)(e.target.origin - gp[e.tip_bone].origin).length_squared());
		}
		if (worst_sq <= min_d_sq) {
			break;
		}
	}
	// Influence: blend each rotated bone from its pre-solve pose toward the solved pose. 1.0 (the
	// default) leaves the full IK result untouched; <1 eases the IK in (animators' partial-IK knob).
	if (infl < (real_t)1.0) {
		for (uint32_t i = 0; i < solve_order.size(); i++) {
			const int b = solve_order[i];
			sk->set_bone_pose_rotation(b, orig_rot[i].slerp(sk->get_bone_pose_rotation(b), infl));
		}
	}
	sk->force_update_all_bone_transforms();
}

void SwingTwistIK3D::_validate_property(PropertyInfo &p_property) const {
	// Auto-fill the motion root from the skeleton's bone list (same picker as the other IK
	// bone-name properties), so the animator selects it from a dropdown instead of typing.
	// Editor-only: outside the editor the hint is unused, so skip the lookup entirely.
	if (!Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	Skeleton3D *skeleton = get_skeleton();
	const String bones = skeleton ? String(skeleton->get_concatenated_bone_names()) : String();
	if (p_property.name == "motion_root_bone") {
		p_property.hint = skeleton ? PROPERTY_HINT_ENUM_SUGGESTION : PROPERTY_HINT_NONE;
		p_property.hint_string = bones;
	} else if (p_property.name == "locked_bones") {
		// Typed array of bone-name dropdowns: each element is a String with an enum suggestion.
		p_property.hint = PROPERTY_HINT_TYPE_STRING;
		p_property.hint_string = vformat("%d/%d:%s", Variant::STRING, PROPERTY_HINT_ENUM_SUGGESTION, bones);
	} else if (p_property.name == "pins") {
		// Typed dictionary: key = bone name (enum suggestion), value = target NodePath.
		p_property.hint = PROPERTY_HINT_DICTIONARY_TYPE;
		p_property.hint_string = vformat("%d/%d:%s;%d/%d:", Variant::STRING_NAME, PROPERTY_HINT_ENUM_SUGGESTION, bones, Variant::NODE_PATH, PROPERTY_HINT_NONE);
	}
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
	ClassDB::bind_method(D_METHOD("set_pins", "pins"), &SwingTwistIK3D::set_pins);
	ClassDB::bind_method(D_METHOD("get_pins"), &SwingTwistIK3D::get_pins);
	ClassDB::bind_method(D_METHOD("set_locked_bones", "locked_bones"), &SwingTwistIK3D::set_locked_bones);
	ClassDB::bind_method(D_METHOD("get_locked_bones"), &SwingTwistIK3D::get_locked_bones);
	ClassDB::bind_method(D_METHOD("set_joint_priorities", "setting", "joint", "position", "swing", "twist"), &SwingTwistIK3D::set_joint_priorities);
	ClassDB::bind_method(D_METHOD("get_joint_priorities", "setting", "joint"), &SwingTwistIK3D::get_joint_priorities);
	ClassDB::bind_method(D_METHOD("set_joint_stiffness", "setting", "joint", "stiffness"), &SwingTwistIK3D::set_joint_stiffness);
	ClassDB::bind_method(D_METHOD("get_joint_stiffness", "setting", "joint"), &SwingTwistIK3D::get_joint_stiffness);
	ClassDB::bind_method(D_METHOD("set_joint_engage", "setting", "joint", "engage"), &SwingTwistIK3D::set_joint_engage);
	ClassDB::bind_method(D_METHOD("get_joint_engage", "setting", "joint"), &SwingTwistIK3D::get_joint_engage);
	ClassDB::bind_method(D_METHOD("set_joint_isolation", "setting", "joint", "isolation"), &SwingTwistIK3D::set_joint_isolation);
	ClassDB::bind_method(D_METHOD("get_joint_isolation", "setting", "joint"), &SwingTwistIK3D::get_joint_isolation);
	ClassDB::bind_method(D_METHOD("set_joint_relax", "setting", "joint", "relax"), &SwingTwistIK3D::set_joint_relax);
	ClassDB::bind_method(D_METHOD("get_joint_relax", "setting", "joint"), &SwingTwistIK3D::get_joint_relax);

	// All interactive state is serialized so it persists in the scene and is undoable via the
	// inspector's built-in EditorUndoRedoManager. Per-joint weights ride the chain settings
	// (settings/i/joints/j/priorities, stiffness, engage, isolation, relax) via _set/_get/
	// _get_property_list, like the limitation.
	ADD_GROUP("Body", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "free_root"), "set_free_root", "get_free_root");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "motion_root_bone", PROPERTY_HINT_ENUM_SUGGESTION, ""), "set_motion_root_bone", "get_motion_root_bone");
	ADD_GROUP("Controls", "");
	// pins (bone name -> target NodePath) and locked_bones (bone names) are given their element
	// types/bone-name dropdowns dynamically in _validate_property (the hint needs the live skeleton).
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "pins"), "set_pins", "get_pins");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "locked_bones"), "set_locked_bones", "get_locked_bones");
}
