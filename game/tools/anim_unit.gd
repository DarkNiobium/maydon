extends Node
## Single character at constant velocity; measures planted-foot slide of the
## final pose (after foot IK). args: speed dir(fwd|left|right|back|diag) [turn_rate_rad_s]

var final_b := Vector3.ZERO
var final_a := Vector3.ZERO
var sk: Skeleton3D
var bl := -1
var bbl := -1

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var sp := float(args[0]) if args.size() > 0 else 3.35
	var dirn := args[1] if args.size() > 1 else "fwd"
	var turn := float(args[2]) if args.size() > 2 else 0.0
	CharacterView.load_shared()
	var p := Footballer.new()
	p.id = 0
	p.number = 9
	p.face = Vector3(0, 0, 1)
	var v := CharacterView.new()
	add_child(v)
	v.setup(p, Game.team_kit(0))
	var dirs := {"fwd": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(1, 0, 0), "right": Vector3(-1, 0, 0), "diag": Vector3(0.7, 0, 0.7)}
	var vdir: Vector3 = dirs[dirn]
	var dt := 1.0 / 60.0
	var pos := Vector3.ZERO
	sk = v.get("_skel")
	bl = sk.find_bone("foot_l")
	bbl = sk.find_bone("ball_l")
	sk.skeleton_updated.connect(func() -> void:
		final_a = sk.global_transform * sk.get_bone_global_pose(bl).origin
		final_b = sk.global_transform * sk.get_bone_global_pose(bbl).origin)
	var plx: FootPlanter = v.get("_planter")
	plx.debug = true
	var verbose := OS.get_environment("DBG") != ""
	var pr := Vector3.INF
	var slides := []
	var miny := 9.0
	var minb := 9.0
	for f in 300:
		p.face = p.face.rotated(Vector3.UP, turn * dt)
		if turn != 0.0 and dirn == "fwd":
			vdir = p.face
		p.vel = vdir * sp
		pos += p.vel * dt
		CharacterView.cam_pos = pos
		v.sync(p, pos, p.face, dt)
		await get_tree().process_frame
		if plx._w > 0.5:
			final_b = plx.final_ball[0]
		if f > 60:
			var hb := Vector2(final_b.x - pr.x, final_b.z - pr.z).length() / dt
			miny = minf(miny, final_a.y)
			minb = minf(minb, final_b.y)
			slides.append([final_a.y, final_b.y, hb])
			if verbose:
				print("F%d w%.2f fb(%.3f,%.3f,%.3f) hb %.2f" % [f, plx._w, final_b.x, final_b.y, final_b.z, hb])
		pr = final_b
	var n := 0
	var s := 0.0
	var big := 0
	for e in slides:
		if e[1] < minb + 0.012:
			n += 1
			s += e[2]
			if e[2] > 0.5:
				big += 1
	var pl: FootPlanter = v.get("_planter")
	print("speed %.2f %s turn %.1f: ball min %.3f planted n%d slide %.2f m/s (>0.5: %d) steps %d" % [sp, dirn, turn, minb, n, s / maxf(n, 1), big, pl.stepped if pl else -1])
	get_tree().quit()
