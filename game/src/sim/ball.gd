class_name BallSim
extends RefCounted
## Football physics: gravity, quadratic drag, Magnus lift (curl), bounce with
## spin/friction coupling, rolling resistance, walls, posts, crossbar, nets.
## Pure data — no nodes — so it runs headless and on a server.

const R := 0.11
const G := 9.81
const K_DRAG := 0.0118        # 0.5·ρ·Cd·A/m
const K_MAGNUS := 0.0052      # a = K·(ω × v)
const SPIN_DECAY_AIR := 0.10
const MU_SLIDE := 0.42        # ball/grass sliding friction
const SHELL := 2.5            # 1 + m R² / I for a thin shell (I = 2/3 m R²)

var pitch: Pitch
var pos := Vector3(0.0, R, 0.0)
var vel := Vector3.ZERO
var spin := Vector3.ZERO      # angular velocity (rad/s)
var roll_c := 1.05            # constant rolling deceleration (m/s²)
var roll_k := 0.085           # speed-proportional rolling deceleration (1/s)
var bounce_e := 0.58
var in_goal := 0                # side of the goal the ball is inside of, 0 = none
var in_hands := -1              # id of goalkeeper holding the ball, -1 = none
var fast := false               # prediction mode: coarse substeps, no goal-frame collisions
var events: Array = []          # {t:String, p:Vector3, s:float}
var frozen := false


func setup(p: Pitch) -> void:
	pitch = p
	if p.surface == Pitch.Surface.TURF:
		roll_c = 0.85
		roll_k = 0.07
		bounce_e = 0.64


func reset(at: Vector3) -> void:
	pos = Vector3(at.x, R, at.z)
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	in_goal = 0
	in_hands = -1


func on_ground() -> bool:
	return pos.y <= R + 0.02 and absf(vel.y) < 0.35


func speed() -> float:
	return vel.length()


func ground_speed() -> float:
	return Vector2(vel.x, vel.z).length()


## Apply a kick: new velocity and spin.
func kick(v: Vector3, w: Vector3 = Vector3.ZERO) -> void:
	in_hands = -1
	vel = v
	spin = w
	if pos.y < R:
		pos.y = R


## Spin that makes a ground ball roll without slipping for its velocity.
static func rolling_spin(v: Vector3) -> Vector3:
	return Vector3(v.z / R, 0.0, -v.x / R)


func step(dt: float) -> void:
	if frozen or in_hands >= 0:
		return
	var sp := vel.length()
	var n := clampi(int(ceil(sp * dt / (0.07 if not fast else 0.25))), 1, 10)
	var h := dt / n
	for i in n:
		_substep(h)


func _substep(h: float) -> void:
	var prev := pos
	var airborne := pos.y > R + 0.004 or vel.y > 0.05
	if airborne:
		var sp := vel.length()
		var acc := Vector3(0.0, -G, 0.0)
		acc -= vel * (K_DRAG * sp)
		acc += spin.cross(vel) * K_MAGNUS
		vel += acc * h
		pos += vel * h
		spin *= (1.0 - SPIN_DECAY_AIR * h)
		if pos.y < R:
			pos.y = R
			_ground_impact()
	else:
		pos.y = R
		vel.y = 0.0
		var vh := Vector3(vel.x, 0.0, vel.z)
		var gsp := vh.length()
		# slip of the contact point: u = v + ω × (−R ŷ)
		var u := Vector3(vel.x + R * spin.z, 0.0, vel.z - R * spin.x)
		var ul := u.length()
		if ul > 0.15:
			# sliding: friction reduces slip until rolling
			var dvmag := minf(MU_SLIDE * G * h, ul / SHELL)
			var dv := -u / ul * dvmag
			vel += dv
			var dw := Vector3(0.0, -R, 0.0).cross(dv) * (1.5 / (R * R))
			spin += dw
		else:
			if gsp > 0.0001:
				var dec := (roll_c + roll_k * gsp) * h
				if dec >= gsp:
					vel = Vector3.ZERO
				else:
					vel = vh * ((gsp - dec) / gsp)
			var rs := rolling_spin(vel)
			spin = Vector3(rs.x, spin.y, rs.z)
		spin.y *= (1.0 - 2.2 * h)
		# slight curl on the ground from side spin
		if gsp > 1.0:
			vel += spin.cross(vel) * (K_MAGNUS * 0.15 * h)
			vel.y = 0.0
		pos += vel * h
	_collide_world(prev)


func _ground_impact() -> void:
	var vy := -vel.y
	if vy > 0.75:
		var e := bounce_e * clampf(1.05 - vy * 0.012, 0.75, 1.0)
		vel.y = vy * e
		events.append({"t": "bounce", "p": pos, "s": vy})
	else:
		vel.y = 0.0
	# friction impulse at contact couples spin and horizontal velocity
	var u := Vector3(vel.x + R * spin.z, 0.0, vel.z - R * spin.x)
	var ul := u.length()
	if ul > 0.001:
		var jmax := MU_SLIDE * (1.0 + bounce_e) * vy
		var dvmag := minf(jmax, ul / SHELL)
		var dv := -u / ul * dvmag
		vel += dv
		spin += Vector3(0.0, -R, 0.0).cross(dv) * (1.5 / (R * R))
	spin.y *= 0.8


func _reflect(nrm: Vector3, e: float, tangential_keep: float) -> void:
	var vn := vel.dot(nrm)
	if vn < 0.0:
		var vt := vel - nrm * vn
		vel = vt * tangential_keep - nrm * vn * e
		spin *= 0.7


func _collide_world(prev: Vector3) -> void:
	var hl := pitch.hl()
	var hw := pitch.hw()
	var gw2 := pitch.goal_width * 0.5
	var gh := pitch.goal_height
	var depth := pitch.goal_depth
	var side := 1 if pos.x > 0.0 else -1
	var ax := absf(pos.x)
	var az := absf(pos.z)

	# --- goal frame: posts and crossbar -----------------------------------
	_frame(side, hl, gw2, gh, pitch.post_radius)

	# --- goal net box ---------------------------------------------------------
	var inside_x := ax > hl + 0.001 and ax < hl + depth + R
	var inside_mouth := az < gw2 + R * 0.2 and pos.y < gh + R * 0.2
	if in_goal == 0:
		var was_front := absf(prev.x) <= hl + 0.02
		if inside_x and az < gw2 + R and pos.y < gh + R:
			if was_front and inside_mouth:
				in_goal = side
			else:
				# hit the net from outside (side net / roof / back)
				var dz := gw2 + R - az
				var dy := gh + R - pos.y
				var dx := hl + depth + R - ax
				if dy < dz and dy < dx:
					pos.y = gh + R
					_reflect(Vector3.UP, 0.15, 0.5)
				elif dz < dx:
					pos.z = signf(pos.z) * (gw2 + R)
					_reflect(Vector3(0.0, 0.0, signf(pos.z)), 0.15, 0.5)
				else:
					pos.x = side * (hl + depth + R)
					_reflect(Vector3(side, 0.0, 0.0), 0.15, 0.5)
				events.append({"t": "net_out", "p": pos, "s": vel.length()})
	if in_goal != 0:
		var s := in_goal
		var hit := false
		var spd := vel.length()
		if absf(pos.x) > hl + depth - R:
			pos.x = s * (hl + depth - R)
			_reflect(Vector3(-s, 0.0, 0.0), 0.08, 0.35)
			hit = true
		if absf(pos.z) > gw2 - R:
			pos.z = signf(pos.z) * (gw2 - R)
			_reflect(Vector3(0.0, 0.0, -signf(pos.z)), 0.1, 0.4)
			hit = true
		if pos.y > gh - R:
			pos.y = gh - R
			_reflect(Vector3.DOWN, 0.1, 0.4)
			hit = true
		if absf(pos.x) < hl - R and vel.x * s < 0.0:
			in_goal = 0  # rebounded back out (rare: only via the front)
		if hit and spd > 2.0:
			events.append({"t": "net", "p": pos, "s": spd})
		return

	# --- boundary walls (arena) or ad boards ---------------------------------
	var bx := hl + (pitch.runoff_x if not pitch.walls else 0.0)
	var bz := hw + (pitch.runoff_z if not pitch.walls else 0.0)
	var e := pitch.wall_restitution if pitch.walls else 0.3
	var keep := 0.88 if pitch.walls else 0.5
	var spd2 := vel.length()
	var wall_hit := false
	if ax > bx - R:
		var in_opening := pitch.walls and az < gw2 and pos.y < gh
		if not in_opening:
			pos.x = signf(pos.x) * (bx - R)
			_reflect(Vector3(-signf(pos.x), 0.0, 0.0), e, keep)
			wall_hit = true
	if az > bz - R:
		pos.z = signf(pos.z) * (bz - R)
		_reflect(Vector3(0.0, 0.0, -signf(pos.z)), e, keep)
		wall_hit = true
	if pitch.walls and pitch.wall_chamfer > 0.0:
		var lim := hl + hw - pitch.wall_chamfer
		var s2 := absf(pos.x) + absf(pos.z)
		if s2 > lim - R * 1.4142:
			var nrm := Vector3(-signf(pos.x), 0.0, -signf(pos.z)).normalized()
			var over := s2 - (lim - R * 1.4142)
			pos += nrm * (over / 1.4142)
			_reflect(nrm, e, keep)
			wall_hit = true
	if wall_hit and spd2 > 1.5:
		events.append({"t": "wall", "p": pos, "s": spd2})


func _frame(side: int, hl: float, gw2: float, gh: float, pr: float) -> void:
	if absf(absf(pos.x) - hl) > 0.6:
		return
	for zs: float in [-1.0, 1.0]:
		var c := Vector3(hl * side, 0.0, (gw2 + pr) * zs)
		_collide_segment(c, c + Vector3(0.0, gh + pr, 0.0), pr, "post")
	_collide_segment(Vector3(hl * side, gh + pr, -gw2 - pr), Vector3(hl * side, gh + pr, gw2 + pr), pr, "bar")


func _collide_segment(a: Vector3, b: Vector3, r: float, kind: String) -> void:
	var ab := b - a
	var t := clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var c := a + ab * t
	var d := pos - c
	var dl := d.length()
	var minr := r + R
	if dl < minr and dl > 0.0001:
		var nrm := d / dl
		pos = c + nrm * minr
		var vn := vel.dot(nrm)
		if vn < 0.0:
			var spd := vel.length()
			vel -= nrm * vn * (1.0 + 0.72)
			vel *= 0.92
			spin *= 0.5
			if spd > 1.5:
				events.append({"t": kind, "p": pos, "s": spd})


## Fully over the goal line inside the goal mouth → side of goal scored in.
func goal_side() -> int:
	if in_goal == 0:
		return 0
	if absf(pos.x) > pitch.hl() + pitch.line_half + R:
		return in_goal
	return 0


## Predict future ball positions (no player collisions). Returns positions at
## intervals of `dt` for `steps` steps. Uses a copy of the state.
func predict(steps: int, dt: float) -> PackedVector3Array:
	var b := BallSim.new()
	b.pitch = pitch
	b.pos = pos
	b.vel = vel
	b.spin = spin
	b.roll_c = roll_c
	b.roll_k = roll_k
	b.bounce_e = bounce_e
	b.in_goal = in_goal
	b.fast = true
	var out := PackedVector3Array()
	out.resize(steps)
	for i in steps:
		b.step(dt)
		out[i] = b.pos
	return out


# ---------------------------------------------------------------------------
# Kick solvers (used by AI and assisted human passing)
# ---------------------------------------------------------------------------

## Distance a rolling ball travels when slowing from v0 to v1.
func roll_distance(v0: float, v1: float) -> float:
	var c := roll_c
	var k := roll_k
	return ((v0 - v1) - (c / k) * log((c + k * v0) / (c + k * v1))) / k


## Arrival speed used for firm, realistic ground passes.
static func pass_arrive_speed(d: float, through := false) -> float:
	if through:
		return clampf(2.5 + d * 0.12, 3.0, 7.0)
	return clampf(4.6 + d * 0.17, 5.5, 11.0)


## Initial speed for a ground pass to travel `d` metres and arrive at `v_arrive`.
func ground_pass_speed(d: float, v_arrive: float) -> float:
	var lo := v_arrive
	var hi := 45.0
	for i in 16:
		var mid := (lo + hi) * 0.5
		if roll_distance(mid, v_arrive) < d:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Time for a rolling ball starting at v0 to cover distance d (INF if never).
func roll_time(v0: float, d: float) -> float:
	var c := roll_c
	var k := roll_k
	# v(t) = (v0 + c/k)·e^{-kt} − c/k ; s(t) = (v0 + c/k)(1 − e^{-kt})/k − (c/k)t
	var lo := 0.0
	var hi := log((v0 + c / k) / (c / k)) / k  # time when v reaches 0
	var a := v0 + c / k
	var smax := a * (1.0 - exp(-k * hi)) / k - (c / k) * hi
	if d > smax:
		return INF
	for i in 18:
		var mid := (lo + hi) * 0.5
		var s := a * (1.0 - exp(-k * mid)) / k - (c / k) * mid
		if s < d:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Aerial kick from `from` landing (first bounce) at horizontal `to` with
## launch elevation `elev` (radians). Returns launch velocity. Iterative with drag.
func lob_velocity(from: Vector3, to: Vector3, elev: float, w := Vector3.ZERO) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := flat.length()
	if dist < 0.1:
		return Vector3(0, 4, 0)
	var dir := flat / dist
	var lo := 2.0
	var hi := 45.0
	var best := Vector3.ZERO
	for it in 22:
		var spd := (lo + hi) * 0.5
		var v := dir * cos(elev) * spd + Vector3.UP * sin(elev) * spd
		var land := _carry(from, v, w)
		best = v
		if land < dist:
			lo = spd
		else:
			hi = spd
	return best


## Horizontal carry distance until the ball first comes down to ground level.
func _carry(from: Vector3, v: Vector3, w: Vector3) -> float:
	var p := from
	var vel2 := v
	var spin2 := w
	var h := 1.0 / 60.0
	for i in 600:
		var sp := vel2.length()
		var acc := Vector3(0.0, -G, 0.0) - vel2 * (K_DRAG * sp) + spin2.cross(vel2) * K_MAGNUS
		vel2 += acc * h
		p += vel2 * h
		spin2 *= (1.0 - SPIN_DECAY_AIR * h)
		if p.y <= R and vel2.y < 0.0:
			break
	return Vector2(p.x - from.x, p.z - from.z).length()


## Velocity to send the ball from `from` through `target` (3D point) with a given
## speed, accounting for gravity, drag and spin. Iterates on elevation and yaw.
func shot_velocity(from: Vector3, target: Vector3, spd: float, w := Vector3.ZERO) -> Vector3:
	var aim := target
	var v := Vector3.ZERO
	for it in 6:
		var d := aim - from
		var flat := Vector3(d.x, 0.0, d.z)
		var fl := flat.length()
		var elev := atan2(d.y, maxf(fl, 0.01))
		var dir := flat / maxf(fl, 0.001)
		v = dir * cos(elev) * spd + Vector3.UP * sin(elev) * spd
		# simulate to the plane at distance fl
		var p := from
		var vv := v
		var ww := w
		var h := 1.0 / 120.0
		var reached := false
		for i in 600:
			var sp := vv.length()
			vv += (Vector3(0.0, -G, 0.0) - vv * (K_DRAG * sp) + ww.cross(vv) * K_MAGNUS) * h
			p += vv * h
			ww *= (1.0 - SPIN_DECAY_AIR * h)
			if (p - from).dot(dir) >= fl:
				reached = true
				break
			if p.y < -2.0:
				break
		if not reached:
			aim.y += 1.0
			continue
		var err := target - p
		aim += err
	return v
