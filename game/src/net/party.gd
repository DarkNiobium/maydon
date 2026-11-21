class_name Party
extends Node
## Client side of rooms + matchmaking (Brawl Stars style): your room has as many
## slots as one team of the selected mode (3 / 5 / 11). Friends join by code,
## "search teammates" fills empty slots with players who are also searching,
## PLAY queues the room; whoever isn't found within the wait becomes a bot.
## Online needs a matchmaking server (Game.settings["server"], ws://host:port).
## Without one the search runs locally and the match is played with bots.

signal changed
signal queue_changed
signal match_found(info: Dictionary)
signal notice(key: String)
signal mate_emote(member_id: int, index: int)

const DEFAULT_SERVER := "ws://129.151.206.134:47900"   # MAYDON online (UZB777 VPS)
const TEAM := {3: 3, 5: 5, 11: 11}
const OFFLINE_SEARCH := 3.5

var ws: WebSocketPeer
var online := false
var my_id := -1
var room := {}                       # last "room" message
var queue := {}                      # last "queue" message
var searching := false
var _search_t := 0.0
var _retry := 0.0
var _url := ""
var _ping := 0.0


func server_url() -> String:
	if OS.has_feature("web"):
		return ""          # browsers can't open the UDP (ENet) match connection
	var u := str(Game.settings.get("server", "")).strip_edges()
	return u if u != "" else DEFAULT_SERVER


func server_host() -> String:
	var u := _url.trim_prefix("ws://").trim_prefix("wss://")
	return u.get_slice(":", 0).get_slice("/", 0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var url := server_url()
	if url != _url:
		_disconnect()
		_url = url
		_retry = 0.0
	if _url != "" and ws == null:
		_retry -= delta
		if _retry <= 0.0:
			_retry = 8.0
			ws = WebSocketPeer.new()
			if ws.connect_to_url(_url) != OK:
				ws = null
	if ws:
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			if not online:
				online = true
				_send({"t": "hello", "name": Game.player_name(), "level": int(Game.profile.get("level", 1)),
					"role": int(Game.profile.get("role", 3)), "number": int(Game.profile.get("number", 10)), "look": Look.get_look()})
			while ws.get_available_packet_count() > 0:
				var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if typeof(d) == TYPE_DICTIONARY:
					_handle(d)
			_ping -= delta
			if _ping <= 0.0:
				_ping = 20.0
				_send({"t": "ping"})
		elif st == WebSocketPeer.STATE_CLOSED:
			var was := online
			ws = null
			online = false
			room = {}
			searching = false
			if was:
				changed.emit()
	# offline search (no server): short local search, then bots
	if searching and not online:
		_search_t += delta
		queue = {"wait": _search_t, "max": OFFLINE_SEARCH, "found": 1, "need": team_size() * 2}
		queue_changed.emit()
		if _search_t >= OFFLINE_SEARCH:
			searching = false
			var roster := [[{"name": Game.player_name(), "level": int(Game.profile.get("level", 1)), "bot": false}], []]
			for t in 2:
				while roster[t].size() < team_size():
					roster[t].append({"name": "BOT", "level": 0, "bot": true})
			match_found.emit({"offline": true, "mode": mode(), "teams": roster, "team": 0})


func _disconnect() -> void:
	if ws:
		ws.close()
	ws = null
	online = false
	room = {}


func _send(d: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func _handle(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"welcome":
			my_id = int(d.get("id", -1))
			changed.emit()
		"room":
			room = d if str(d.get("code", "")) != "" else {}
			searching = bool(room.get("queue", false))
			if not room.is_empty():
				Game.settings["mode"] = int(room.get("mode", mode()))
			changed.emit()
		"queue":
			queue = d
			searching = true
			queue_changed.emit()
		"match":
			searching = false
			var info := d.duplicate()
			info["host"] = server_host()
			match_found.emit(info)
		"error":
			notice.emit("ERR_" + str(d.get("e", "")))
		"emote":
			mate_emote.emit(int(d.get("id", -1)), int(d.get("e", 0)))


# ---------------------------------------------------------------------------
# API used by the lobby
# ---------------------------------------------------------------------------

func mode() -> int:
	return int(room.get("mode", Game.settings.get("mode", 11)))


func team_size(m := -1) -> int:
	return TEAM.get(m if m > 0 else mode(), 5)


func in_room() -> bool:
	return not room.is_empty()


func is_leader() -> bool:
	return room.is_empty() or int(room.get("leader", -1)) == my_id


## Room members (me first). Offline / not in a room: just me.
func members() -> Array:
	var me := {"id": my_id, "name": Game.player_name(), "level": int(Game.profile.get("level", 1)), "look": Look.get_look(), "me": true}
	if room.is_empty():
		return [me]
	var out := [me]
	for m in room.get("members", []):
		if int(m["id"]) != my_id:
			out.append(m)
	return out


func set_mode(m: int) -> void:
	Game.settings["mode"] = m
	if online and in_room() and is_leader():
		_send({"t": "room_mode", "mode": m})
	changed.emit()


func create_room(open := false) -> void:
	_send({"t": "room_create", "mode": mode(), "open": open})


func join_code(code: String) -> void:
	_send({"t": "room_join", "code": code})


func leave() -> void:
	_send({"t": "room_leave"})
	room = {}
	changed.emit()


func set_search_mates(on: bool) -> void:
	if not online:
		notice.emit("ERR_offline")
		return
	if not in_room():
		if on:
			_send({"t": "find_team", "mode": mode()})
		return
	if (room.get("members", []) as Array).size() <= 1 and on:
		_send({"t": "find_team", "mode": mode()})
	elif is_leader():
		_send({"t": "room_open", "open": on})


func search_mates_on() -> bool:
	return bool(room.get("open", false))


func send_emote(i: int) -> void:
	_send({"t": "emote", "e": i})


func push_profile() -> void:
	_send({"t": "profile", "look": Look.get_look(), "role": int(Game.profile.get("role", 3))})


func play() -> void:
	if online:
		if not is_leader():
			return
		_send({"t": "queue", "on": true, "mode": mode()})
		searching = true
		queue = {"wait": 0.0, "max": 12.0, "found": members().size(), "need": team_size() * 2}
	else:
		searching = true
		_search_t = 0.0
	queue_changed.emit()


func cancel() -> void:
	if online and in_room():
		_send({"t": "queue", "on": false, "mode": mode()})
	searching = false
	queue = {}
	queue_changed.emit()
