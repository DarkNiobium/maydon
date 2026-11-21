class_name NetMatch
extends Node
## Glue between MatchView and Net for LAN games.
## Host: feeds remote controllers from received input, streams snapshots/events.
## Client: sends world-space stick + button mask, applies snapshots to the
## local (non-stepped) MatchSim so views/HUD work unchanged.

const HDR := 18
const PER := 18
const B := InputState.B
const NET_EVENTS := ["kick", "goal", "whistle", "save", "post", "bar", "card", "foul", "out",
	"restart", "kickoff", "halftime", "fulltime", "tackle", "fall", "net", "wall", "shot",
	"offside", "bounce", "touch", "trap", "catch", "parry", "live", "emote"]

var view: MatchView
var host := false
var remote := {}               # peer -> HumanController
var _snap_acc := 0
var _pending_events: Array = []
var _remote_emote := {}
var _emote_send := 0
var _emote_ticks := 0
var last_snap_ms := 0
var snap_interval := 1.0 / 30.0


func _init(v: MatchView, as_host: bool) -> void:
	view = v
	host = as_host


func _ready() -> void:
	if host:
		for h in view.cfg.humans:
			var idx := int(h["idx"])
			if idx == 0:
				continue
			for p in view.sim.players:
				if p.human == idx:
					var hc := HumanController.new(view.sim, p.id)
					hc.gk_assist = true
					remote[int(h.get("peer", -1))] = hc
	else:
		Net.snapshot.connect(_on_snapshot)
		Net.net_events.connect(_on_events)
		Net.match_ended.connect(_on_end)
	Net.disconnected.connect(_on_disconnected)


# --- host --------------------------------------------------------------------

func host_pre(now: float) -> void:
	for peer in remote:
		var hc: HumanController = remote[peer]
		var ri: Dictionary = Net.remote_inputs.get(peer, {})
		if ri.is_empty():
			hc.inp.stick = Vector2.ZERO
		else:
			hc.inp.stick = ri["stick"]
			var mask: int = ri["mask"]
			for b in InputState.N:
				hc.inp.set_button(b, (mask >> b) & 1 == 1, now)
			# emote id rides in bits 16..19 (held a few ticks); trigger on change
			var em := (mask >> 16) & 15
			if em != int(_remote_emote.get(peer, 0)) and em > 0:
				hc.inp.emote = em - 1
			_remote_emote[peer] = em
		# remote sticks are already world-space (x, z)
		hc.update(now, Vector3(0, 0, 1), Vector3(1, 0, 0))
		hc.inp.end_frame()


func host_post(events: Array) -> void:
	for e in events:
		if e["t"] in NET_EVENTS:
			_pending_events.append(e)
	_snap_acc += 1
	if _snap_acc >= 2:
		_snap_acc = 0
		Net.send_snapshot(encode())
		if not _pending_events.is_empty():
			Net.send_events(_pending_events)
			_pending_events = []


func encode() -> PackedFloat32Array:
	var m := view.sim
	var n := m.players.size()
	var a := PackedFloat32Array()
	a.resize(HDR + n * PER)
	a[0] = m.clock
	a[1] = m.phase
	a[2] = m.half
	a[3] = m.teams[0]["score"]
	a[4] = m.teams[1]["score"]
	a[5] = m.phase_t
	a[6] = m.owner
	a[7] = m.ball.pos.x
	a[8] = m.ball.pos.y
	a[9] = m.ball.pos.z
	a[10] = m.ball.spin.x
	a[11] = m.ball.spin.y
	a[12] = m.ball.spin.z
	a[13] = m.ball.in_hands
	a[14] = m.poss_team
	a[15] = m.restart.get("taker", -1)
	a[16] = m.restart.get("type", -1)
	a[17] = m.teams[0]["side"]
	for i in n:
		var p: Footballer = m.players[i]
		var o := HDR + i * PER
		a[o] = p.pos.x
		a[o + 1] = p.pos.z
		a[o + 2] = p.face.x
		a[o + 3] = p.face.z
		a[o + 4] = p.vel.x
		a[o + 5] = p.vel.z
		a[o + 6] = p.gait
		a[o + 7] = p.action
		a[o + 8] = p.act_t
		a[o + 9] = p.act_contact
		a[o + 10] = p.act_seq
		a[o + 11] = p.stamina
		a[o + 12] = 1.0 if p.sent_off else 0.0
		var dir: Vector3 = p.act_data.get("dir", Vector3.ZERO) if p.act_data.get("dir", null) is Vector3 else Vector3.ZERO
		a[o + 13] = dir.x
		a[o + 14] = dir.z
		a[o + 15] = float(p.act_data.get("lat", 0.0)) + floorf(float(p.act_data.get("h", 0.0)) * 10.0) * 100.0
		a[o + 16] = p.touch_at - m.clock if p.touch_at >= 0.0 else -1.0   # planned dribble touch (s ahead)
		a[o + 17] = float(p.touch_foot) + 10.0 * float(p.act_data.get("foot", 1))
	return a


# --- client ------------------------------------------------------------------

func client_tick(now: float) -> void:
	var inp := view.human.inp if view.human else null
	if inp == null:
		return
	var ax := view.cam.control_axes()
	var w: Vector3 = ax[1] * inp.stick.x + ax[0] * inp.stick.y
	var mask := 0
	for b in InputState.N:
		if inp.held[b]:
			mask |= 1 << b
	if inp.emote >= 0:
		_emote_send = inp.emote + 1
		_emote_ticks = 12
	if _emote_ticks > 0:
		_emote_ticks -= 1
		mask |= _emote_send << 16
	Net.send_input(Vector2(w.x, w.z), mask)
	view.human.last_ctx = view.human.context()
	inp.end_frame()


func _on_snapshot(a: PackedFloat32Array) -> void:
	var m := view.sim
	var n := m.players.size()
	if a.size() < HDR + n * PER:
		return
	m.clock = a[0]
	m.phase = int(a[1])
	m.half = int(a[2])
	m.teams[0]["score"] = int(a[3])
	m.teams[1]["score"] = int(a[4])
	m.phase_t = a[5]
	m.owner = int(a[6])
	m.ball.pos = Vector3(a[7], a[8], a[9])
	m.ball.spin = Vector3(a[10], a[11], a[12])
	m.ball.in_hands = int(a[13])
	m.poss_team = int(a[14])
	m.restart["taker"] = int(a[15])
	m.restart["type"] = int(a[16])
	var s0 := int(a[17])
	m.teams[0]["side"] = s0
	m.teams[1]["side"] = -s0
	for i in n:
		var p: Footballer = m.players[i]
		var o := HDR + i * PER
		p.pos = Vector3(a[o], 0, a[o + 1])
		var f := Vector3(a[o + 2], 0, a[o + 3])
		if f.length() > 0.1:
			p.face = f.normalized()
		p.vel = Vector3(a[o + 4], 0, a[o + 5])
		p.gait = a[o + 6]
		p.action = int(a[o + 7])
		p.act_t = a[o + 8]
		p.act_contact = a[o + 9]
		p.act_seq = int(a[o + 10])
		p.stamina = a[o + 11]
		p.sent_off = a[o + 12] > 0.5
		var lat_h := a[o + 15]
		var feet := int(roundf(a[o + 17]))
		var kf := 1 if feet >= 0 else -1
		p.touch_foot = feet - 10 * kf
		p.touch_at = m.clock + a[o + 16] if a[o + 16] >= 0.0 else -1.0
		p.act_data = {"dir": Vector3(a[o + 13], 0, a[o + 14]), "lat": fmod(lat_h, 100.0), "h": floorf(lat_h / 100.0) / 10.0, "foot": kf}
	view._snapshot()
	last_snap_ms = Time.get_ticks_msec()


func client_alpha() -> float:
	return clampf((Time.get_ticks_msec() - last_snap_ms) / 1000.0 / snap_interval, 0.0, 1.0)


func _on_events(evs: Array) -> void:
	for e in evs:
		view._on_event(e)


func _on_end(res: Dictionary) -> void:
	# map the human id to my player
	res["human_id"] = view.human_id
	res["meta"] = {"mode": "lan"}
	Game.last_result = res
	Sfx.match_end()
	Net.stop()
	Game.goto("res://scenes/results.tscn")


func _on_disconnected() -> void:
	if view.is_inside_tree():
		view.hud.banner("Wi-Fi", "—", 2.0)
		var tw := create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(func() -> void:
			Sfx.match_end()
			Net.stop()
			Game.goto("res://scenes/menu.tscn"))
