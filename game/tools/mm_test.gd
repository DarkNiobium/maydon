extends Node
## Matchmaking end-to-end client bot. args: A|B server_url mode codefile
var role := "A"
var codefile := "/tmp/mm_code.txt"
var t := 0.0
var queued := false
var joined := false
var in_match_t := -1.0

func _ready() -> void:
	if get_parent() != get_tree().root or name == "MMTest":
		# survive scene changes: move under the root as a plain node
		var dummy := Node.new()
		dummy.name = "Dummy"
		var tree := get_tree()
		(func() -> void:
			var r := tree.root
			get_parent().remove_child(self)
			name = "MMWatcher"
			r.add_child(dummy)
			tree.current_scene = dummy
			request_ready()
			r.add_child(self)).call_deferred()
		return
	var a := OS.get_cmdline_user_args()
	role = a[0]
	Game.settings["server"] = a[1]
	Game.settings["mode"] = int(a[2])
	codefile = a[3]
	Game.profile["name"] = "Bot" + role
	Net.party.changed.connect(func() -> void:
		print("[", role, "] room ", Net.party.room.get("code", ""), " members ", Net.party.members().size(), " leader ", Net.party.is_leader()))
	Net.party.match_found.connect(func(info: Dictionary) -> void:
		print("[", role, "] MATCH FOUND port ", info.get("port"), " team ", info.get("team"), " roster ", (info["teams"][0] as Array).size(), "+", (info["teams"][1] as Array).size())
		Net.join_online(info["host"], int(info["port"]), str(info["token"])))
	Net.party.notice.connect(func(k: String) -> void: print("[", role, "] notice ", k))
	Net.party.queue_changed.connect(func() -> void:
		if int(t * 2) % 4 == 0:
			print("[", role, "] queue ", Net.party.queue))

func _process(delta: float) -> void:
	t += delta
	var p: Party = Net.party
	if role.begins_with("S"):
		# solo "search teammates": both bots toggle search, the leader queues once merged
		if p.online and p.my_id > 0 and not p.in_room() and not joined and t > (1.0 if role == "S1" else 2.5):
			joined = true
			p.set_search_mates(true)
		if p.in_room() and p.members().size() >= 2 and p.is_leader() and not queued:
			queued = true
			print("[", role, "] merged with ", p.members()[1]["name"], " -> queue")
			p.play()
	elif role.begins_with("Q"):
		# separate rooms queueing on their own → should face each other
		if p.online and p.my_id > 0 and not p.in_room() and not joined:
			joined = true
			p.create_room(false)
		if p.in_room() and not queued:
			queued = true
			p.play()
	elif role == "A":
		if p.online and p.my_id > 0 and not p.in_room() and t > 1.0 and not queued:
			p.create_room(false)
		if p.in_room() and not FileAccess.file_exists(codefile):
			var f := FileAccess.open(codefile, FileAccess.WRITE)
			f.store_string(str(p.room["code"]))
			f.close()
		if p.in_room() and p.members().size() >= 2 and not queued:
			queued = true
			print("[A] queue start")
			p.play()
	else:
		if p.online and p.my_id > 0 and not p.in_room() and not joined and FileAccess.file_exists(codefile):
			joined = true
			p.join_code(FileAccess.get_file_as_string(codefile).strip_edges())
	var sc := get_tree().current_scene
	if sc and sc.name != "Dummy" and in_match_t < 0.0:
		in_match_t = t
		print("[", role, "] scene ", sc.name)
	if in_match_t >= 0.0 and t - in_match_t > 8.0:
		var mv := get_tree().current_scene as MatchView
		if mv:
			print("[", role, "] in match: human_id ", mv.human_id, " humans ", mv.cfg.humans.size(), " clock ", mv.sim.clock, " score ", mv.sim.teams[0]["score"], "-", mv.sim.teams[1]["score"])
		get_tree().quit()
	if t > 60.0:
		print("[", role, "] timeout")
		get_tree().quit()
