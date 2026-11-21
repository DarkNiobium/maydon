class_name FootPlanter
extends SkeletonModifier3D
## Foot locking: when the animation puts a foot on the ground, the foot is pinned
## to that spot (two-bone leg IK) until the animation lifts it. If the body
## drifts too far from a pinned foot (turning on the spot, kick approach,
## speed/cadence mismatch) the foot takes a quick procedural step instead of
## skating. Also keeps a pinned foot's yaw while the body turns.

const MAX_OFF := 0.30          # m: pinned foot may lag the animated one this much
const STEP_TIME := 0.16        # s: procedural re-plant step
const STEP_H := 0.07           # m: step arc height

var weight := 1.0              # target weight (view fades it out for floor actions / LOD)
var body_speed := 0.0          # set by the view each frame (m/s)
var body_vel := Vector3.ZERO   # world velocity of the character root
var unlean := Transform3D.IDENTITY  # world -> world without the body lean (contact detection)
var stepped := 0               # stats: procedural steps taken
var debug := false
var frame_dt := 0.0            # set by the view with each animation update
var frame_id := 0              # incremented by the view; state advances once per id
var spine_pitch := 0.0         # forward lean added at spine_01 (rad)
var left_world := Vector3.RIGHT  # character-left axis in world (lean axis)
# reach: one swinging foot is pulled to a world point (ball contact) with weight reach_w
var reach_leg := -1              # 0 = left, 1 = right, -1 = none
var reach_w := 0.0
var reach_target := Vector3.ZERO # world target for the ball (metatarsal) joint
var reach_yaw := 0.0             # extra foot yaw (rad) at full weight, e.g. inside of the foot to the ball
var force_pin := false           # actions: a low foot is always pinned (moves only by stepping, never sliding)

var final_ball: Array = [Vector3.ZERO, Vector3.ZERO]   # world, after IK (diagnostics)
var diag: Array = ["", ""]
static var diag_samples: Array = []
var _seen_id := -1
var _spine := -1
var _cache: Array = [null, null]   # per leg: [t_world, yaw] from the last state update

var _w := 0.0
var _legs: Array = []
var _ready_bones := false
var _pelvis := -1


class Leg:
	var thigh := -1
	var calf := -1
	var foot := -1
	var ball := -1
	var planted := false
	var lock := Vector3.ZERO      # world position of the pinned ball joint
	var off := Vector3.ZERO       # world xz offset applied to the animated foot
	var yaw := 0.0                # pinned foot yaw correction (rad)
	var lock_yaw := 0.0
	var prev_b := Vector3.INF     # previous animated ball position, skeleton space
	var step_t := -1.0            # >= 0 while taking a procedural step
	var step_from := Vector3.ZERO
	var step_yaw := 0.0


func _init_bones() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_pelvis = sk.find_bone("pelvis")
	_spine = sk.find_bone("spine_01")
	_legs.clear()
	for s in ["l", "r"]:
		var l := Leg.new()
		l.thigh = sk.find_bone("thigh_" + s)
		l.calf = sk.find_bone("calf_" + s)
		l.foot = sk.find_bone("foot_" + s)
		l.ball = sk.find_bone("ball_" + s)
		_legs.append(l)
	_ready_bones = _pelvis >= 0 and _legs[0].foot >= 0 and _legs[1].foot >= 0


func reset() -> void:
	for l: Leg in _legs:
		l.planted = false
		l.off = Vector3.ZERO
		l.yaw = 0.0
		l.step_t = -1.0
		l.prev_b = Vector3.INF


func _process_modification_with_delta(_delta: float) -> void:
	if not _ready_bones:
		_init_bones()
		if not _ready_bones:
			return
	var sk0 := get_skeleton()
	if absf(spine_pitch) > 0.002 and _spine >= 0:
		_lean_spine(sk0)
	if frame_id == _seen_id:
		# modifier re-run within the same frame: re-apply the cached solution
		for i in 2:
			var c = _cache[i]
			if c != null:
				_solve(sk0, sk0.global_transform, _legs[i], c[0], c[1])
		return
	_seen_id = frame_id
	_cache = [null, null]
	var delta := frame_dt
	_w = move_toward(_w, weight, delta * 6.0)
	if _w <= 0.001:
		for l: Leg in _legs:
			l.planted = false
			l.off = Vector3.ZERO
			l.yaw = 0.0
			l.step_t = -1.0
			l.prev_b = Vector3.INF
		return
	var sk := get_skeleton()
	var gt := sk.global_transform
	var body_yaw := gt.basis.get_euler().y
	var other_stepping := false
	for l: Leg in _legs:
		if l.step_t >= 0.0:
			other_stepping = true
	for i in 2:
		var l: Leg = _legs[i]
		var a0: Vector3 = gt * sk.get_bone_global_pose(l.foot).origin
		var b0: Vector3 = gt * sk.get_bone_global_pose(l.ball).origin
		# ground speed the animation intends for this foot (body translation +
		# foot motion relative to the body, ignoring body yaw → turning on the
		# spot still counts as planted)
		var bl := gt.affine_inverse() * b0
		var bspeed := 0.0
		if l.prev_b != Vector3.INF and delta > 0.0:
			var gv := gt.basis * ((bl - l.prev_b) / delta) + body_vel
			bspeed = Vector2(gv.x, gv.z).length()
		l.prev_b = bl
		var hb := (unlean * b0).y
		var ha := (unlean * a0).y
		var low := hb < 0.05 or ha < 0.105
		var down := low and (force_pin or bspeed < 1.2 + body_speed * 0.5)      # touchdown
		var still_low := hb < 0.065 or ha < 0.118                  # pinned feet stay until lifted
		if debug and hb < 0.04:
			diag_samples.append([body_speed, bspeed])
		if debug:
			diag[i] = "high%.2f" % hb if not (hb < 0.05 or ha < 0.105) else ("fast_b%.0f_v%.0f" % [bspeed, body_speed] if not down else "down")
		var lift := 0.0
		if l.step_t >= 0.0:
			# procedural step back under the animated foot
			l.step_t += delta / STEP_TIME
			var k := clampf(l.step_t, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			l.off = l.step_from * (1.0 - e)
			l.yaw = l.step_yaw * (1.0 - e)
			lift = sqrt(sin(k * PI)) * STEP_H        # clears the turf quickly, no dragging at the ends
			if l.step_t >= 1.0:
				l.step_t = -1.0
				l.off = Vector3.ZERO
				l.yaw = 0.0
				if down:
					l.planted = true
					l.lock = b0
					l.lock_yaw = body_yaw
		elif l.planted:
			if not still_low:
				l.planted = false          # animation lifts the foot: swing catches up in the air
			else:
				var o := l.lock - b0
				o.y = 0.0
				var yd := angle_difference(body_yaw, l.lock_yaw)
				var lim := MAX_OFF * (1.4 if other_stepping else 1.0)
				if o.length() > 1.0:
					l.planted = false        # teleport (restart positions): no step
					l.off = Vector3.ZERO
					l.yaw = 0.0
				elif (o.length() > lim or absf(yd) > 0.55 or not _reachable(sk, gt, l, a0 + o)) and not other_stepping:
					l.planted = false
					l.step_t = 0.0
					l.step_from = o
					l.step_yaw = clampf(yd, -0.7, 0.7)
					other_stepping = true
					stepped += 1
				else:
					l.off = o
					l.yaw = clampf(yd, -0.7, 0.7)
		else:
			# free foot: offset decays (swing leg catches up), then pin on touchdown
			var dk := exp(-delta * 14.0)
			l.off *= dk
			l.yaw *= dk
			if down:
				l.planted = true
				l.lock = b0 + l.off
				l.lock.y = b0.y
				l.lock_yaw = body_yaw - l.yaw
		if debug and i == 0 and OS.get_environment("DBG") != "":
			print("ha%.3f hb%.3f bs%.2f down%d pl%d st%.2f off%.3f" % [ha, hb, bspeed, int(down), int(l.planted), l.step_t, l.off.length()])
		final_ball[i] = b0
		if i == reach_leg and reach_w > 0.001:
			# touch / strike: the swinging foot meets the ball (overrides pinning for this leg)
			l.planted = false
			l.step_t = -1.0
			var rw := reach_w * _w
			var tb := b0.lerp(reach_target, rw)
			var ry := reach_yaw * rw
			var tw := tb + Basis(Vector3.UP, ry) * (a0 - b0)
			if tw.y < 0.06:
				tw.y = 0.06
			l.off = Vector3(tb.x - b0.x, 0.0, tb.z - b0.z)
			l.yaw = 0.0
			_cache[i] = [tw, ry]
			_solve(sk, gt, l, tw, ry)
			if debug:
				final_ball[i] = gt * sk.get_bone_global_pose(l.ball).origin
			continue
		if l.off.length_squared() < 1e-6 and absf(l.yaw) < 0.002 and lift == 0.0 and b0.y >= 0.015:
			continue
		# ankle target: the ball joint goes to (animated + offset) and the foot yaw
		# correction pivots around the ball, so a pinned toe doesn't move
		var yw := l.yaw * _w
		var t_world := b0 + l.off * _w + Basis(Vector3.UP, yw) * (a0 - b0) + Vector3(0, lift * _w, 0)
		if b0.y < 0.015:
			t_world.y += 0.015 - b0.y                 # no sinking into the turf
		_cache[i] = [t_world, yw]
		_solve(sk, gt, l, t_world, yw)
		if debug:
			final_ball[i] = gt * sk.get_bone_global_pose(l.ball).origin


func _reachable(sk: Skeleton3D, gt: Transform3D, l: Leg, t_world: Vector3) -> bool:
	var h := sk.get_bone_global_pose(l.thigh).origin
	var k := sk.get_bone_global_pose(l.calf).origin
	var a := sk.get_bone_global_pose(l.foot).origin
	var t := gt.affine_inverse() * t_world
	return h.distance_to(t) < (h.distance_to(k) + k.distance_to(a)) * 0.985


func _lean_spine(sk: Skeleton3D) -> void:
	var gt := sk.global_transform
	var axis := (gt.basis.inverse() * left_world).normalized()
	var par := sk.get_bone_parent(_spine)
	var pb := sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis()
	var g := sk.get_bone_global_pose(_spine).basis.orthonormalized()
	var ng := Basis(axis, spine_pitch) * g
	sk.set_bone_pose_rotation(_spine, (pb.inverse() * ng).get_rotation_quaternion())


## Analytic two-bone IK in skeleton space; keeps the animated knee plane and
## the animated foot orientation (optionally yawed by `yaw`).
func _solve(sk: Skeleton3D, gt: Transform3D, l: Leg, t_world: Vector3, yaw: float) -> void:
	var inv := gt.affine_inverse()
	var t := inv * t_world
	var pp := sk.get_bone_global_pose(_pelvis)
	var pt := sk.get_bone_global_pose(l.thigh)
	var pc := sk.get_bone_global_pose(l.calf)
	var pf := sk.get_bone_global_pose(l.foot)
	var h := pt.origin
	var k0 := pc.origin
	var a0 := pf.origin
	var l1 := h.distance_to(k0)
	var l2 := k0.distance_to(a0)
	var dv := t - h
	var d := clampf(dv.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	if dv.length_squared() < 1e-8:
		return
	var u := dv.normalized()
	var pole := (k0 - h) - u * (k0 - h).dot(u)
	if pole.length_squared() < 1e-8:
		pole = (inv.basis * gt.basis.z).normalized()
		pole = pole - u * pole.dot(u)
	pole = pole.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hh := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var k := h + u * a + pole * hh
	var a_new := h + u * d
	var q1 := Quaternion((k0 - h).normalized(), (k - h).normalized())
	var bt := Basis(q1) * pt.basis.orthonormalized()
	var q2 := Quaternion((q1 * (a0 - k0)).normalized(), (a_new - k).normalized())
	var bc := Basis(q2) * Basis(q1) * pc.basis.orthonormalized()
	var bf := pf.basis.orthonormalized()
	if absf(yaw) > 0.002:
		var up := (inv.basis * Vector3.UP).normalized()
		bf = Basis(up, yaw) * bf
	sk.set_bone_pose_rotation(l.thigh, (pp.basis.orthonormalized().inverse() * bt).get_rotation_quaternion())
	sk.set_bone_pose_rotation(l.calf, (bt.inverse() * bc).get_rotation_quaternion())
	sk.set_bone_pose_rotation(l.foot, (bc.inverse() * bf).get_rotation_quaternion())
