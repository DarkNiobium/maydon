extends Node
## LAN multiplayer (same Wi-Fi or phone hotspot). Host-authoritative:
## the host runs MatchSim; clients send controller state and render snapshots.
## Discovery via UDP broadcast beacons; gameplay over ENet.

signal hosts_changed
signal lobby_changed
signal match_starting
signal snapshot(data: PackedFloat32Array)
signal net_events(evs: Array)
signal match_ended(res: Dictionary)
signal disconnected

const GAME_PORT := 47891
const BEACON_PORT := 47890
const MAGIC := "MAYDON1"
const SNAP_HZ := 30

var is_host := false
var active := false
var hosts := {}                 # ip -> {name, players, format, seen}
var lobby := {"format": 5, "players": []}   # players: [{peer, name, number, role, team}]
var my_name := ""
var _beacon_tx: PacketPeerUDP
var _beacon_rx: PacketPeerUDP
var _beacon_t := 0.0
var remote_inputs := {}         # peer -> {"mask": int, "stick": Vector2}
var _snap_t := 0.0
var party: Party                # online rooms + matchmaking client
var dedicated := false          # headless match server (no local player)
var online_token := ""          # client: ticket for a dedicated match
var _ded_spec := {}
var _ded_t := 0.0
var _ded_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	party = Party.new()
	party.name = "Party"
	add_child(party)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


# ---------------------------------------------------------------------------
# Hosting / joining
# ---------------------------------------------------------------------------

func host(format: int) -> bool:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(GAME_PORT, 9) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	my_name = Game.player_name()
	lobby = {"format": format, "players": [_me(1, 0)]}
	_beacon_tx = PacketPeerUDP.new()
	_beacon_tx.set_broadcast_enabled(true)
	_beacon_tx.set_dest_address("255.255.255.255", BEACON_PORT)
	lobby_changed.emit()
	return true


func _me(peer_id: int, team: int) -> Dictionary:
	return {"peer": peer_id, "name": Game.player_name(), "number": int(Game.profile.get("number", 10)),
		"role": int(Game.profile.get("role", 3)), "team": team, "level": int(Game.profile.get("level", 1))}


func start_discovery() -> void:
	stop_discovery()
	_beacon_rx = PacketPeerUDP.new()
	if _beacon_rx.bind(BEACON_PORT) != OK:
		_beacon_rx = null
	hosts.clear()


func stop_discovery() -> void:
	if _beacon_rx:
		_beacon_rx.close()
		_beacon_rx = null


func join(ip: String, port := GAME_PORT) -> bool:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	return true


## Client: connect to a dedicated match server with the ticket from the matchmaker.
func join_online(host_ip: String, port: int, token: String) -> bool:
	var ok := join(host_ip, port)
	online_token = token if ok else ""
	return ok


## Dedicated server: wait for the ticketed players, then start (missing ones become bots).
func host_dedicated(port: int, spec: Dictionary) -> bool:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, 24) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	dedicated = true
	_ded_spec = spec
	_ded_t = 0.0
	_ded_started = false
	lobby = {"format": int(spec.get("mode", 5)), "players": []}
	print("[match] waiting on ", port, " for ", (spec.get("humans", []) as Array).size(), " players")
	return true


@rpc("any_peer", "reliable")
func c_hello_tok(token: String) -> void:
	if not dedicated or _ded_started:
		return
	var id := multiplayer.get_remote_sender_id()
	for h in _ded_spec.get("humans", []):
		if str(h.get("token", "")) == token:
			h["peer"] = id
	if _ded_ready():
		_dedicated_start()


func _ded_ready() -> bool:
	for h in _ded_spec.get("humans", []):
		if int(h.get("peer", -1)) <= 0:
			return false
	return true


func _dedicated_start() -> void:
	_ded_started = true
	var fmt := int(_ded_spec.get("mode", 5))
	var cfg := Game.quick_match(fmt, Footballer.Role.FWD, 2, bool(_ded_spec.get("night", true)))
	cfg.kits = [Game.team_kit(0), Game.team_kit(1)]
	cfg.team_strength = [0.62, 0.62]
	cfg.seed = int(_ded_spec.get("seed", 1))
	cfg.humans = []
	var idx := 1
	for h in _ded_spec.get("humans", []):
		if int(h.get("peer", -1)) <= 0:
			continue
		cfg.humans.append({"team": int(h["team"]), "role": int(h["role"]), "idx": idx, "name": str(h["name"]),
			"number": int(h["number"]), "level": clampf(0.58 + int(h["level"]) * 0.011, 0.58, 0.9),
			"peer": int(h["peer"]), "look": h.get("look", {})})
		idx += 1
	print("[match] start with ", cfg.humans.size(), " players")
	var d := cfg.to_dict()
	rpc("h_start", d)
	_begin_match(d)


func stop() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if _beacon_tx:
		_beacon_tx.close()
		_beacon_tx = null
	active = false
	is_host = false
	online_token = ""
	remote_inputs.clear()


func _process(delta: float) -> void:
	if dedicated and not _ded_started:
		_ded_t += delta
		var any := multiplayer.get_peers().size() > 0
		if (any and _ded_t > 12.0) or (_ded_ready() and any):
			_dedicated_start()
		elif _ded_t > 40.0:
			print("[match] nobody came")
			get_tree().quit()
	if is_host and _beacon_tx and get_tree().current_scene and get_tree().current_scene.name == "Menu":
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := JSON.stringify({"m": MAGIC, "name": my_name, "n": lobby["players"].size(), "f": lobby["format"]})
			_beacon_tx.put_packet(msg.to_utf8_buffer())
	if _beacon_rx:
		while _beacon_rx.get_available_packet_count() > 0:
			var pkt := _beacon_rx.get_packet()
			var ip := _beacon_rx.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(d) == TYPE_DICTIONARY and d.get("m", "") == MAGIC:
				hosts[ip] = {"name": d.get("name", "?"), "players": int(d.get("n", 1)), "format": int(d.get("f", 5)),
					"seen": Time.get_ticks_msec()}
				hosts_changed.emit()
		var now := Time.get_ticks_msec()
		for ip in hosts.keys():
			if now - int(hosts[ip]["seen"]) > 3500:
				hosts.erase(ip)
				hosts_changed.emit()


func _on_peer_connected(id: int) -> void:
	if not is_host:
		return


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	if dedicated and multiplayer.get_peers().is_empty() and _ded_started:
		print("[match] everyone left")
		get_tree().create_timer(2.0).timeout.connect(func() -> void: get_tree().quit())
	var ps: Array = lobby["players"]
	for i in range(ps.size() - 1, -1, -1):
		if ps[i]["peer"] == id:
			ps.remove_at(i)
	remote_inputs.erase(id)
	_push_lobby()


func _on_connected() -> void:
	if online_token != "":
		rpc_id(1, "c_hello_tok", online_token)
		return
	rpc_id(1, "c_hello", Game.player_name(), int(Game.profile.get("number", 10)),
		int(Game.profile.get("role", 3)), int(Game.profile.get("level", 1)))


func _on_failed() -> void:
	active = false
	disconnected.emit()


func _on_server_gone() -> void:
	active = false
	disconnected.emit()


# ---------------------------------------------------------------------------
# Lobby RPCs
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func c_hello(pname: String, number: int, role: int, level: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	var counts := [0, 0]
	for p in lobby["players"]:
		counts[p["team"]] += 1
	var team := 0 if counts[0] <= counts[1] else 1
	lobby["players"].append({"peer": id, "name": pname.substr(0, 14), "number": clampi(number, 1, 99),
		"role": clampi(role, 0, 3), "team": team, "level": clampi(level, 1, 99)})
	_push_lobby()


@rpc("any_peer", "reliable")
func c_set_team(team: int, role: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	set_player(id, team, role)


func set_player(peer_id: int, team: int, role: int) -> void:
	for p in lobby["players"]:
		if p["peer"] == peer_id:
			p["team"] = clampi(team, 0, 1)
			p["role"] = clampi(role, 0, 3)
	_push_lobby()


func request_team(team: int, role: int) -> void:
	if is_host:
		set_player(1, team, role)
	else:
		rpc_id(1, "c_set_team", team, role)


func _push_lobby() -> void:
	lobby_changed.emit()
	if is_host:
		rpc("h_lobby", lobby)


@rpc("authority", "reliable")
func h_lobby(l: Dictionary) -> void:
	lobby = l
	lobby_changed.emit()


func my_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1


# ---------------------------------------------------------------------------
# Match start
# ---------------------------------------------------------------------------

## Host: build the config (humans = lobby players), broadcast, load the match.
func host_start() -> void:
	var fmt: int = lobby["format"]
	var cfg := Game.quick_match(fmt, Footballer.Role.FWD, 2, true)
	cfg.kits = [Game.team_kit(0), Game.team_kit(1)]
	cfg.team_strength = [0.62, 0.62]
	cfg.humans = []
	var idx := 0
	for p in lobby["players"]:
		cfg.humans.append({"team": p["team"], "role": p["role"], "idx": idx, "name": p["name"],
			"number": p["number"], "level": clampf(0.58 + int(p["level"]) * 0.011, 0.58, 0.9), "peer": p["peer"]})
		idx += 1
	var d := cfg.to_dict()
	rpc("h_start", d)
	_begin_match(d)


@rpc("authority", "reliable")
func h_start(cfg_d: Dictionary) -> void:
	_begin_match(cfg_d)


func _begin_match(cfg_d: Dictionary) -> void:
	var cfg := MatchConfig.from_dict(cfg_d)
	# local human index = position of my peer in humans
	var mine := -1
	for h in cfg.humans:
		if int(h.get("peer", -1)) == my_peer():
			mine = int(h["idx"])
	# remap so that my controller is idx 0 locally; others become idx >= 1
	for h in cfg.humans:
		var i := int(h["idx"])
		if i == mine:
			h["idx"] = 0
		elif i == 0:
			h["idx"] = mine
	Game.next_match = cfg
	Game.next_match_meta = {"mode": "online" if (dedicated or online_token != "") else "lan", "net": "host" if is_host else "client"}
	if dedicated:
		Game.next_match_meta["dedicated"] = true
	stop_discovery()
	match_starting.emit()
	Sfx.stop_music()
	Game.goto("res://scenes/match.tscn")


# ---------------------------------------------------------------------------
# In-match traffic
# ---------------------------------------------------------------------------

## Client → host controller state (unreliable, every tick).
func send_input(stick: Vector2, mask: int) -> void:
	rpc_id(1, "c_input", stick, mask)


@rpc("any_peer", "unreliable_ordered")
func c_input(stick: Vector2, mask: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	remote_inputs[id] = {"stick": stick.limit_length(1.0), "mask": mask}


func send_snapshot(data: PackedFloat32Array) -> void:
	rpc("h_snap", data)


@rpc("authority", "unreliable_ordered")
func h_snap(data: PackedFloat32Array) -> void:
	snapshot.emit(data)


func send_events(evs: Array) -> void:
	rpc("h_events", evs)


@rpc("authority", "reliable")
func h_events(evs: Array) -> void:
	net_events.emit(evs)


func send_end(res: Dictionary) -> void:
	rpc("h_end", res)


@rpc("authority", "reliable")
func h_end(res: Dictionary) -> void:
	match_ended.emit(res)
