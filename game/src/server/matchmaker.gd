class_name MatchmakerServer
extends Node
## Online matchmaking server (headless Godot, no external deps).
## Clients talk JSON over WebSocket: rooms (parties) with a join code,
## "search teammates" (open rooms get filled with solo searchers), a match
## queue per mode that pairs parties into two teams and fills the rest with
## bots after a wait. Each match runs in its own dedicated headless process.
##
## Run: godot --headless --path game res://scenes/server.tscn -- --mm port=47900 [match_ports=47910-47990]

const TEAM := {3: 3, 5: 5, 11: 11}
const WAIT := {3: 10.0, 5: 12.0, 11: 15.0}     # seconds before bots fill the gaps
const PROTO := 1

var port := 47900
var port_lo := 47910
var port_hi := 47990
var max_matches := 8        # RAM cap: each match is its own process (~60-170 MB)
var _tcp := TCPServer.new()
var _clients := {}          # id -> {ws, name, level, role, number, look, room}
var _pending := []          # [WebSocketPeer, id] handshaking
var _rooms := {}            # code -> {code, mode, leader, members:[id], open, queue, q_t}
var _matches := {}          # port -> {pid, t}
var _next_id := 1
var _tick := 0.0
var _rng := RandomNumberGenerator.new()


func start(args: Dictionary) -> void:
	port = int(args.get("port", port))
	if args.has("match_ports"):
		var pr := str(args["match_ports"]).split("-")
		port_lo = int(pr[0])
		port_hi = int(pr[1]) if pr.size() > 1 else port_lo + 80
	_rng.randomize()
	max_matches = int(args.get("max_matches", max_matches))
	var err := _tcp.listen(port)
	print("[mm] listening on ", port, " err=", err, "  match ports ", port_lo, "-", port_hi)


func _process(delta: float) -> void:
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 18
		ws.accept_stream(conn)
		var id := _next_id
		_next_id += 1
		_clients[id] = {"ws": ws, "name": "?", "level": 1, "role": 3, "number": 10, "look": {}, "room": "", "hello": false}
	for id in _clients.keys():
		var c: Dictionary = _clients[id]
		var ws: WebSocketPeer = c["ws"]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if typeof(d) == TYPE_DICTIONARY:
					_handle(id, d)
		elif st == WebSocketPeer.STATE_CLOSED:
			_drop(id)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_matchmake()
		_reap()


func _send(id: int, d: Dictionary) -> void:
	if not _clients.has(id):
		return
	var ws: WebSocketPeer = _clients[id]["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func _drop(id: int) -> void:
	_leave_room(id)
	_clients.erase(id)


# ---------------------------------------------------------------------------
# Protocol
# ---------------------------------------------------------------------------

func _handle(id: int, d: Dictionary) -> void:
	var c: Dictionary = _clients[id]
	match str(d.get("t", "")):
		"hello":
			c["name"] = str(d.get("name", "Player")).substr(0, 14)
			c["level"] = clampi(int(d.get("level", 1)), 1, 99)
			c["role"] = clampi(int(d.get("role", 3)), 0, 3)
			c["number"] = clampi(int(d.get("number", 10)), 1, 99)
			var look = d.get("look", {})
			c["look"] = look if typeof(look) == TYPE_DICTIONARY and JSON.stringify(look).length() < 4000 else {}
			c["hello"] = true
			_send(id, {"t": "welcome", "id": id, "proto": PROTO})
		"profile":
			# look / role changed in the locker while in a room
			var look2 = d.get("look", {})
			if typeof(look2) == TYPE_DICTIONARY and JSON.stringify(look2).length() < 4000:
				c["look"] = look2
			c["role"] = clampi(int(d.get("role", c["role"])), 0, 3)
			_push_room(str(c["room"]))
		"room_create":
			_leave_room(id)
			_create_room(id, _mode(d), bool(d.get("open", false)))
		"room_join":
			var code := str(d.get("code", "")).to_upper().strip_edges()
			if not _rooms.has(code):
				_send(id, {"t": "error", "e": "no_room"})
				return
			var r: Dictionary = _rooms[code]
			if r["queue"]:
				_send(id, {"t": "error", "e": "in_queue"})
				return
			if (r["members"] as Array).size() >= TEAM[r["mode"]]:
				_send(id, {"t": "error", "e": "full"})
				return
			_leave_room(id)
			(r["members"] as Array).append(id)
			c["room"] = code
			_push_room(code)
		"room_leave":
			_leave_room(id)
			_send(id, {"t": "room", "code": ""})
		"room_mode":
			var r2 := _my_room(id)
			if r2.is_empty() or r2["leader"] != id or r2["queue"]:
				return
			var m := _mode(d)
			if (r2["members"] as Array).size() > TEAM[m]:
				_send(id, {"t": "error", "e": "too_many"})
				return
			r2["mode"] = m
			_push_room(r2["code"])
		"room_open":
			var r3 := _my_room(id)
			if r3.is_empty() or r3["leader"] != id:
				return
			r3["open"] = bool(d.get("open", false))
			_push_room(r3["code"])
			if r3["open"]:
				_pull_searchers(r3)
		"find_team":
			# solo "search teammates": join an open room of this mode, else open one
			var m2 := _mode(d)
			var mine := _my_room(id)
			if not mine.is_empty() and (mine["members"] as Array).size() > 1:
				return
			var best := ""
			for code2 in _rooms:
				var r4: Dictionary = _rooms[code2]
				if r4["open"] and not r4["queue"] and r4["mode"] == m2 and code2 != str(c["room"]) \
						and (r4["members"] as Array).size() < TEAM[m2]:
					if best == "" or (r4["members"] as Array).size() > (_rooms[best]["members"] as Array).size():
						best = code2
			if best != "":
				_leave_room(id)
				(_rooms[best]["members"] as Array).append(id)
				c["room"] = best
				_push_room(best)
			elif mine.is_empty():
				_create_room(id, m2, true)
			else:
				mine["open"] = true
				mine["mode"] = m2
				_push_room(mine["code"])
		"queue":
			var r5 := _my_room(id)
			if r5.is_empty():
				r5 = _create_room(id, _mode(d), false)
			if r5["leader"] != id:
				return
			r5["queue"] = bool(d.get("on", true))
			r5["q_t"] = Time.get_ticks_msec() / 1000.0
			_push_room(r5["code"])
		"emote":
			var r6 := _my_room(id)
			if not r6.is_empty():
				for mid in r6["members"]:
					if mid != id:
						_send(mid, {"t": "emote", "id": id, "e": clampi(int(d.get("e", 0)), 0, 15)})
		"ping":
			_send(id, {"t": "pong"})


func _mode(d: Dictionary) -> int:
	var m := int(d.get("mode", 5))
	return m if TEAM.has(m) else 5


func _my_room(id: int) -> Dictionary:
	var code := str(_clients[id]["room"]) if _clients.has(id) else ""
	return _rooms.get(code, {})


func _create_room(id: int, mode: int, open: bool) -> Dictionary:
	var code := ""
	while code == "" or _rooms.has(code):
		code = ""
		for i in 5:
			code += "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[_rng.randi() % 32]
	var r := {"code": code, "mode": mode, "leader": id, "members": [id], "open": open, "queue": false, "q_t": 0.0}
	_rooms[code] = r
	_clients[id]["room"] = code
	_push_room(code)
	if open:
		_pull_searchers(r)
	return r


func _pull_searchers(_r: Dictionary) -> void:
	# solo searchers sit in their own open 1-player rooms: merge them into bigger open rooms
	var codes := _rooms.keys()
	for code in codes:
		if not _rooms.has(code):
			continue
		var small: Dictionary = _rooms[code]
		if not small["open"] or small["queue"] or (small["members"] as Array).size() != 1:
			continue
		for code2 in _rooms:
			var big: Dictionary = _rooms[code2]
			if code2 == code or not big["open"] or big["queue"] or big["mode"] != small["mode"]:
				continue
			var n := (big["members"] as Array).size()
			if n >= 1 and n < TEAM[big["mode"]] and (n > 1 or str(code2) < str(code)):
				var who: int = small["members"][0]
				_rooms.erase(code)
				(big["members"] as Array).append(who)
				_clients[who]["room"] = code2
				_push_room(code2)
				break


func _leave_room(id: int) -> void:
	if not _clients.has(id):
		return
	var code := str(_clients[id]["room"])
	_clients[id]["room"] = ""
	if not _rooms.has(code):
		return
	var r: Dictionary = _rooms[code]
	(r["members"] as Array).erase(id)
	if (r["members"] as Array).is_empty():
		_rooms.erase(code)
		return
	if r["leader"] == id:
		r["leader"] = r["members"][0]
	r["queue"] = false
	_push_room(code)


func _push_room(code: String) -> void:
	if not _rooms.has(code):
		return
	var r: Dictionary = _rooms[code]
	var ms := []
	for mid in r["members"]:
		var c: Dictionary = _clients[mid]
		ms.append({"id": mid, "name": c["name"], "level": c["level"], "role": c["role"], "look": c["look"]})
	var msg := {"t": "room", "code": code, "mode": r["mode"], "leader": r["leader"], "open": r["open"],
		"queue": r["queue"], "members": ms, "size": TEAM[r["mode"]]}
	for mid in r["members"]:
		_send(mid, msg)


# ---------------------------------------------------------------------------
# Matchmaking
# ---------------------------------------------------------------------------

func _matchmake() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for mode in TEAM:
		var n: int = TEAM[mode]
		var q := []
		for code in _rooms:
			var r: Dictionary = _rooms[code]
			if r["queue"] and r["mode"] == mode:
				q.append(r)
		if q.is_empty():
			continue
		q.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["q_t"] < b["q_t"])
		var teams := [[], []]
		var sizes := [0, 0]
		for r in q:
			# balance: each party goes to the team with fewer humans (if it fits)
			var s := (r["members"] as Array).size()
			var order := [0, 1] if sizes[0] <= sizes[1] else [1, 0]
			for t in order:
				if sizes[t] + s <= n:
					teams[t].append(r)
					sizes[t] += s
					break
		var wait: float = now - float(q[0]["q_t"])
		var full: bool = sizes[0] == n and sizes[1] == n
		if full or wait >= WAIT[mode]:
			_start_match(mode, teams)
		else:
			for r in q:
				for mid in r["members"]:
					_send(mid, {"t": "queue", "wait": wait, "max": WAIT[mode], "found": sizes[0] + sizes[1], "need": n * 2})


func _start_match(mode: int, teams: Array) -> void:
	var port := _alloc_port()
	if port < 0:
		return
	var humans := []
	var roster := [[], []]
	for t in 2:
		for r in teams[t]:
			for mid in r["members"]:
				var c: Dictionary = _clients[mid]
				var tok := "%08x%08x" % [_rng.randi(), _rng.randi()]
				humans.append({"team": t, "role": c["role"], "name": c["name"], "number": c["number"],
					"level": c["level"], "look": c["look"], "token": tok, "cid": mid})
				roster[t].append({"name": c["name"], "level": c["level"], "bot": false})
	var n: int = TEAM[mode]
	for t in 2:
		while roster[t].size() < n:
			roster[t].append({"name": "BOT", "level": 0, "bot": true})
	var spec := {"mode": mode, "night": _rng.randf() < 0.6, "humans": humans, "seed": _rng.randi()}
	var path := OS.get_user_data_dir() + "/match_%d.json" % port
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(spec))
	f.close()
	var args := ["--headless"]
	var cl := OS.get_cmdline_args()
	var mp := cl.find("--main-pack")
	if mp >= 0 and mp + 1 < cl.size():
		args += ["--main-pack", cl[mp + 1]]          # exported server pack
	elif OS.has_feature("editor"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	if OS.has_feature("editor"):                    # editor binaries accept a scene override
		args.append("res://scenes/server.tscn")
	args += ["--", "--match", "port=%d" % port, "spec=" + path]
	var pid := OS.create_process(OS.get_executable_path(), args)
	_matches[port] = {"pid": pid, "t": Time.get_ticks_msec()}
	print("[mm] match mode %d on port %d pid %d humans %d" % [mode, port, pid, humans.size()])
	for h in humans:
		_send(int(h["cid"]), {"t": "match", "port": port, "token": h["token"], "mode": mode, "team": h["team"], "teams": roster})
	for t in 2:
		for r in teams[t]:
			r["queue"] = false
			_push_room(r["code"])


func _alloc_port() -> int:
	if _matches.size() >= max_matches:
		return -1
	for p in range(port_lo, port_hi + 1):
		if not _matches.has(p):
			return p
	return -1


func _reap() -> void:
	for p in _matches.keys():
		var m: Dictionary = _matches[p]
		if not OS.is_process_running(int(m["pid"])) or Time.get_ticks_msec() - int(m["t"]) > 40 * 60 * 1000:
			if OS.is_process_running(int(m["pid"])):
				OS.kill(int(m["pid"]))
			_matches.erase(p)
			DirAccess.remove_absolute(OS.get_user_data_dir() + "/match_%d.json" % p)
