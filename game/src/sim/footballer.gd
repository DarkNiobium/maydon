class_name Footballer
extends RefCounted
## Simulation state of one footballer: kinematics with momentum, stamina,
## current action, gait phase (drives animation and dribble-touch timing).

enum Role { GK, DEF, MID, FWD }

enum A {
	NONE, PASS, LOB, SHOT, CHIP, HEADER, VOLLEY, TACKLE, SLIDE, TRAP,
	GK_DIVE, GK_SET, GK_THROW, GK_KICK, THROW_IN, FALL, GETUP, SKILL, CELEBRATE,
}

var id := 0
var team := 0
var role := Role.MID
var slot := 0
var number := 7
var pname := ""
var human := -1                  # human controller index, -1 = AI

# attributes 0..1
var pace := 0.6
var accel_attr := 0.6
var stamina_attr := 0.6
var shot_attr := 0.6
var pass_attr := 0.6
var dribble_attr := 0.6
var tackle_attr := 0.6
var gk_attr := 0.6
var strength := 0.6

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var face := Vector3(1, 0, 0)
var stamina := 1.0
var gait := 0.0                  # 0..1 locomotion cycle phase
var gait_steps := 0              # foot-strikes counter
var cmd := Cmd.new()
var queued := Cmd.new()          # first-time action waiting for the ball

var action := A.NONE
var act_t := 0.0
var act_dur := 0.0
var act_contact := 0.0
var act_done := false
var act_data := {}
var act_seq := 0                 # increments per action (view uses it to restart clips)
var stun := 0.0
var no_touch := 0.0              # can't touch the ball for this long (just kicked)
var touch_cd := 0.0
var touch_at := -1.0             # sim clock of the next planned dribble touch (-1 = none); the view
                                 # reaches the foot to the ball for it (phase-locked to `gait`)
var touch_foot := 1              # foot of the planned touch: 1 = right, -1 = left
var sent_off := false
var yellow := 0

var stats := {
	"goals": 0, "assists": 0, "shots": 0, "on_target": 0, "passes": 0,
	"passes_ok": 0, "key_passes": 0, "tackles": 0, "tackles_won": 0,
	"interceptions": 0, "saves": 0, "dribbles": 0, "lost": 0, "fouls": 0,
	"blocks": 0, "touches": 0, "zone_t": 0.0, "play_t": 0.0, "conceded": 0,
}


## Stronger foot: 1 = right, -1 = left (about one in five players is left-footed).
func strong_foot() -> int:
	return -1 if (id * 7 + number * 3) % 5 == 0 else 1


## Step cycles per second at ground speed `sp` (one cycle = right + left step). Same table as the
## animation library (walk/jog/run/sprint cycle lengths), so the view can phase-lock to `gait`.
const GAIT_TABLE := [[0.0, 0.0], [0.6, 0.62], [1.75, 1.0], [3.35, 1.43], [5.19, 1.58], [6.9, 1.875]]
static func gait_freq(sp: float) -> float:
	if sp <= 0.25:
		return 0.0
	for i in range(1, GAIT_TABLE.size()):
		var b: Array = GAIT_TABLE[i]
		if sp <= b[0]:
			var a: Array = GAIT_TABLE[i - 1]
			return lerpf(a[1], b[1], (sp - float(a[0])) / (float(b[0]) - float(a[0])))
	var last: Array = GAIT_TABLE[-1]
	return float(last[1]) * sqrt(sp / float(last[0]))


## Gait phases at which a swinging foot passes the ball: right foot late swing (phase 0 = right
## foot strike), left foot half a cycle later. Returns [seconds until the window, foot].
const TOUCH_PHASE := 0.86
func next_touch_window(min_lead: float) -> Array:
	var f := gait_freq(vel.length())
	if f < 0.3:
		return [INF, strong_foot()]
	var best := INF
	var bf := 1
	for w: Array in [[TOUCH_PHASE, 1], [TOUCH_PHASE - 0.5, -1]]:
		var dt := fposmod(float(w[0]) - gait, 1.0) / f
		if dt < min_lead:
			dt += 1.0 / f
		if dt < best:
			best = dt
			bf = w[1]
	return [best, bf]


func is_gk() -> bool:
	return role == Role.GK


func top_speed(sprint: bool) -> float:
	var jog := 5.0 + pace * 0.6
	var spr := 7.3 + pace * 1.9
	var s := spr if sprint else jog
	if stamina < 0.35:
		s *= 0.82 + stamina * 0.5
	return s


func accel() -> float:
	return 6.4 + accel_attr * 3.2


func busy() -> bool:
	return action != A.NONE or stun > 0.0


func on_floor() -> bool:
	return action in [A.SLIDE, A.FALL, A.GETUP, A.GK_DIVE] and act_t > 0.25


func foot_point(reach := 0.42) -> Vector3:
	return pos + face * reach


func start_action(a: int, dur: float, contact: float, data := {}) -> void:
	action = a
	act_t = 0.0
	act_dur = dur
	act_contact = contact
	act_done = false
	act_data = data
	act_seq += 1
	touch_at = -1.0


func end_action() -> void:
	action = A.NONE
	act_t = 0.0
	act_data = {}


## Integrate locomotion for one tick. `with_ball` slows top speed a little.
func move_step(dt: float, with_ball: bool) -> void:
	if stun > 0.0:
		stun -= dt
	var c := cmd
	var top := top_speed(c.sprint)
	if with_ball:
		top *= 0.9 + dribble_attr * 0.06
	var want := c.move
	if want.length() > 1.0:
		want = want.normalized()
	want.y = 0.0
	var desired := want * top
	var sp := vel.length()

	# facing target
	var look_dir := Vector3.ZERO
	if c.look != Vector3.INF:
		look_dir = c.look - pos
		look_dir.y = 0.0
	var jock := c.jockey and look_dir.length() > 0.2

	if jock:
		desired = want * minf(top, 3.6)
	# moving sideways/backwards relative to facing is slower
	if desired.length() > 0.1 and jock:
		var cosang := desired.normalized().dot(face)
		if cosang < 0.3:
			desired *= lerpf(0.75, 1.0, clampf((cosang + 1.0) / 1.3, 0.0, 1.0))

	var a := accel()
	var brake := 13.5
	var dsp := desired.length()
	if sp < 1.6 or jock:
		# low speed: omnidirectional, quick footwork
		vel = vel.move_toward(desired, (a * 1.4) * dt)
	else:
		var vdir := vel / sp
		var ddir := desired / dsp if dsp > 0.05 else vdir
		var ang := vdir.signed_angle_to(ddir, Vector3.UP)
		var a_lat := 11.5 + accel_attr * 4.0
		if with_ball:
			a_lat *= 0.85 + dribble_attr * 0.2
		var max_turn := a_lat / sp * dt
		var nd := vdir.rotated(Vector3.UP, clampf(ang, -max_turn, max_turn))
		var target_sp := dsp
		if absf(ang) > 1.9 and sp > 3.0:
			target_sp = 0.0          # plant and turn
		elif dsp > 0.05:
			target_sp = dsp * (1.0 - 0.25 * absf(ang) / PI)
		var rate := a * (1.0 - 0.45 * pow(sp / maxf(top, 0.1), 2.0)) if target_sp > sp else brake
		var nsp := move_toward(sp, target_sp, rate * dt)
		vel = nd * nsp
	vel.y = 0.0
	pos += vel * dt
	pos.y = 0.0

	# facing
	var turn := 12.0 if not with_ball else 9.5
	var fd := Vector3.ZERO
	if jock:
		fd = look_dir.normalized()
		turn = 8.0
	elif vel.length() > 0.6:
		fd = vel.normalized()
	elif look_dir.length() > 0.2:
		fd = look_dir.normalized()
		turn = 6.0
	if fd != Vector3.ZERO:
		var ang2 := face.signed_angle_to(fd, Vector3.UP)
		face = face.rotated(Vector3.UP, clampf(ang2, -turn * dt, turn * dt)).normalized()

	_gait_step(dt)
	_stamina_step(dt, c.sprint and vel.length() > 5.5)


func _gait_step(dt: float) -> void:
	var f := gait_freq(vel.length())
	var prev := gait
	gait = fmod(gait + f * dt, 1.0)
	if (prev < 0.5 and gait >= 0.5) or gait < prev:
		gait_steps += 1


func _stamina_step(dt: float, sprinting: bool) -> void:
	var drain := 0.0
	if sprinting:
		drain = 0.012 * (1.35 - stamina_attr * 0.7)
	else:
		drain = -0.006 - (0.01 if vel.length() < 2.0 else 0.0)
	stamina = clampf(stamina - drain * dt, 0.15, 1.0)


## Time (s) for this player to get within `reach` of point `t` (ground plane).
func time_to(t: Vector3, sprint := true, reach := 0.5) -> float:
	var d3 := Vector3(t.x - pos.x, 0.0, t.z - pos.z)
	var d := d3.length() - reach
	if d <= 0.0:
		return 0.0
	var dir := d3 / (d + reach)
	var vmax := top_speed(sprint)
	var v0 := maxf(vel.dot(dir), 0.0)
	var a := accel()
	var t_acc := maxf(vmax - v0, 0.0) / a
	var d_acc := (v0 + vmax) * 0.5 * t_acc
	var tt := 0.0
	if d_acc >= d:
		tt = (-v0 + sqrt(v0 * v0 + 2.0 * a * d)) / a
	else:
		tt = t_acc + (d - d_acc) / vmax
	# turning penalty when moving away
	var sp := vel.length()
	if sp > 1.0:
		var cosv := vel.dot(dir) / sp
		tt += (1.0 - cosv) * 0.12 * sp / 4.0
	if busy():
		tt += maxf(act_dur - act_t, 0.0) + maxf(stun, 0.0)
	return tt
