extends RefCounted
## Trailer shot list (music: Electronic Outlaw, 135 BPM, bar = 1.7778 s).
## "in" = sim seconds of the in-point, or "sync": [tick, t] puts sim tick `tick` at output second t.
## "len" = output seconds. "slow" = [[t0, t1, scale, ramp]] in output seconds.

const B := 1.7777778

const SHOTS := {
	"test": {"kind": "arena5", "seed": 1, "in": 58.5, "len": 3.0,
		"cam": {"type": "track", "target": "carrier", "dist": 8.0, "h": 1.2, "fov": 38, "look_w": 0.4, "w": 0.7}},

	"skytest2": {"kind": "arena5", "seed": 1, "in": 30.0, "len": 3.0, "sky_rot": 38,
		"cam": {"type": "pan", "pos": [0, 2.0, 0], "a0": 0, "speed": 120, "fov": 60, "tilt": 0.15}},
	"skytest": {"kind": "arena5", "seed": 1, "in": 30.0, "len": 3.0,
		"cam": {"type": "pan", "pos": [0, 2.0, 0], "a0": 0, "speed": 120, "fov": 60, "tilt": 0.15}},

	# ---------------- intro (quiet)
	"s01_aerial": {"kind": "stadium", "seed": 5, "in": 140.0, "len": 2.5 * B,
		"cam": {"type": "orbit", "center": [0, 0, 0], "r": 16, "r_to": 44, "h": 80, "h_to": 30, "a0": 200, "speed": 7,
			"fov": 50, "fov_to": 44, "look_h": 0.0, "clamp": false}},
	"s02_hero": {"kind": "arena5", "seed": 23, "in": 0.9, "len": 2.5 * B, "dof": [4.2, 5.0, 0.07], "sky_rot": 218,
		"cam": {"type": "orbit", "center": 8, "r": 3.4, "h": 1.35, "a0": 250, "speed": 16, "fov": 32, "look_h": 0.62, "w": 0.9}},
	"s03_shoulder": {"kind": "arena5", "seed": 23, "sync": [824, 2.99 * B], "len": 2.99 * B,
		"cam": {"type": "chase", "target": 8, "back": 4.6, "h": 1.6, "side": 0.32, "fov": 62, "w": 0.6, "look_h": -0.2, "dir": "attack", "att_w": 0.75, "lag": 0.25}},

	# ---------------- drop: montage
	"s04_net": {"kind": "arena5", "seed": 23, "sync": [842, 0.62], "len": B, "slow": [[0.0, 0.62, 0.3, 0.12]],
		"cam": {"type": "fixed", "pos": "auto_net", "look": "ball@816", "look_w": 0.0, "look_h": 0.6, "fov": 50}},
	"s05_celebrate": {"kind": "arena5", "seed": 23, "in": 842.0 / 60.0 + 0.4, "len": B, "dof": [6.5, 6.0, 0.05],
		"cam": {"type": "track", "target": 8, "dist": 3.9, "h": 1.15, "yaw": -20, "fov": 38, "w": 0.4, "look": 8, "look_h": 0.15, "look_w": 0.3}},
	"s06_stadium_run": {"kind": "stadium", "seed": 5, "sync": [8945, 2.95], "len": 2.0 * B,
		"cam": {"type": "track", "target": "carrier", "dist": 22.0, "h": 8.0, "yaw": 0, "fov": 30, "w": 0.7, "look_w": 0.45, "look": "carrier", "look_h": -0.3}},
	"s07_slide": {"kind": "arena5", "seed": 21, "sync": [1090, 0.85], "len": B, "slow": [[0.55, 1.25, 0.33, 0.15]],
		"cam": {"type": "track", "target": 3, "dist": 6.5, "h": 0.7, "yaw": 100, "fov": 36, "w": 0.4, "look_w": 0.25, "look": 3, "look_h": -0.4}},
	"s08_save": {"kind": "arena5", "seed": 21, "sync": [1236, 0.95], "len": B, "slow": [[0.55, 1.3, 0.3, 0.15]],
		"cam": {"type": "fixed", "goal_rel": true, "pos": [-6.0, 1.0, 5.5], "look": 5, "look_w": 0.2, "look_h": -0.3, "fov": 34}},
	"s09_volley": {"kind": "arena5day", "seed": 11, "sync": [7311, 1.7], "len": 2.0 * B, "slow": [[0.75, 1.55, 0.3, 0.2]],
		"cam": {"type": "track", "target": 9, "dist": 7.5, "h": 0.8, "yaw": -20, "fov": 38, "w": 0.5, "look_w": 0.3, "look": 9, "look_h": -0.2}},

	# ---------------- break -> re-entry on the screamer hitting the net
	"s10_screamer": {"kind": "stadium", "seed": 2, "sync": [24999, B], "len": 2.0 * B, "slow": [[0.3, 1.7, 0.55, 0.15]], "sky_rot": -52,
		"cam": {"type": "fixed", "goal_rel": true, "pos": [3.6, 2.0, 0.6], "look": "ball", "look_w": 0.3, "look_mix": [[0, 1.0, 0], 0.4], "fov": 30, "clamp": false}},
	"s11_stadium_party": {"kind": "stadium", "seed": 2, "sync": [24999, 1.62], "len": B, "slow": [[0.0, 2.0, 0.6, 0.1]], "no_trail": false,
		"cam": {"type": "track", "target": "ball", "dist": 15.0, "h": 3.0, "yaw": 0, "fov": 36, "w": 0.25, "look": "ball", "look_w": 0.2, "look_h": 0.3}},

	# ---------------- climax: quick gameplay cuts (half-bar)
	"s14a_tv": {"kind": "stadium", "seed": 2, "sync": [24938, 0.75], "len": 0.5 * B, "hud": true, "ss": 1.25,
		"cam": {"type": "rig", "mode": "TV", "zoom": 0.55}},
	"s14b_shoulder": {"kind": "arena5", "seed": 12, "in": 165.6, "len": 0.5 * B, "hud": true, "follow": 3,
		"cam": {"type": "rig", "mode": "SHOULDER"}},
	"s14c_arena3": {"kind": "arena3day", "seed": 1, "sync": [9999, 0.6], "len": 0.5 * B,
		"cam": {"type": "track", "target": "carrier", "dist": 7.5, "h": 1.4, "yaw": 15, "fov": 40, "w": 0.5, "look_w": 0.3}},
	"s14d_aerial_day": {"kind": "stadiumday", "seed": 6, "sync": [29203, 0.7], "len": 0.5 * B,
		"cam": {"type": "orbit", "center": "ball", "r": 16, "h": 4.5, "a0": 100, "speed": 18, "fov": 42, "w": 0.6, "look_h": 0.5}},
	"s15_final": {"kind": "arena5", "seed": 25, "sync": [15213, 1.62], "len": B, "slow": [[1.2, 1.8, 0.35, 0.25]],
		"cam": {"type": "track", "target": 3, "dist": 4.8, "h": 0.7, "yaw": -35, "fov": 40, "w": 0.35, "look_w": 0.2, "look": 3, "look_h": -0.3}},
}


static func get_shot(n: String) -> Dictionary:
	return SHOTS.get(n, SHOTS["test"])


static func names() -> Array:
	var a := []
	for k: String in SHOTS:
		if k != "test":
			a.append(k)
	return a
