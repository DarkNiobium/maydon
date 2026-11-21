extends Node
## LAN smoke test: run one "host" and one "client" instance headless.
var role := "host"
var t := 0.0
var snaps := 0
var started := false
var found := false

func _ready() -> void:
	if get_parent() != get_tree().root or name != "LanRunner":
		# re-parent a copy to /root so it survives scene changes
		var r: Node = load("res://tools/lan_test.gd").new()
		r.name = "LanRunner"
		get_tree().root.add_child.call_deferred(r)
		set_process(false)
		return
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	Game.profile["created"] = true
	Game.profile["name"] = role.to_upper()
	Game.profile["role"] = 3 if role == "host" else 2
	if role == "host":
		Net.host(3)
		Net.lobby_changed.connect(func() -> void: print("[host] lobby: ", Net.lobby["players"].size(), " players"))
	else:
		Net.start_discovery()
		Net.hosts_changed.connect(func() -> void:
			if not found and not Net.hosts.is_empty():
				found = true
				print("[client] discovered hosts: ", Net.hosts.keys()))
		Net.snapshot.connect(func(_d) -> void: snaps += 1)

func _process(delta: float) -> void:
	t += delta
	if role == "client" and t > 2.5 and not Net.active:
		print("[client] joining 127.0.0.1 (discovered=%s)" % found)
		Net.join("127.0.0.1")
	if role == "host" and not started and Net.lobby["players"].size() >= 2 and t > 3.0:
		started = true
		print("[host] starting match")
		Net.host_start()
	var mv := get_tree().current_scene as MatchView
	if mv and mv.human and role == "client":
		mv.external_input = true
		mv.human.inp.stick = Vector2(0.0, 1.0)
		mv.human.inp.set_button(InputState.B.SPRINT, true, mv.now)
	if t > 14.0:
		if mv:
			var hp: Footballer = mv.sim.players[mv.human_id] if mv.human_id >= 0 else null
			print("[%s] clock=%.1f phase=%d snaps=%d my_player=%s pos=%s" % [role, mv.sim.clock, mv.sim.phase, snaps,
				hp.pname if hp else "-", str(hp.pos) if hp else "-"])
			if role == "host":
				for p in mv.sim.players:
					if p.human > 0:
						print("[host] remote player ", p.pname, " pos=", p.pos, " vel=", p.vel.length())
		else:
			print("[%s] no match scene" % role)
		get_tree().quit()
