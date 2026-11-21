class_name Emotes
extends RefCounted
## Player emotes (view-only, synced over LAN as "emote" events).
## upper = plays on the upper body (works while running); otherwise full body, standing only.

const LIST := [
	{"clip": "emote_wave", "label": "EM_WAVE", "upper": true},
	{"clip": "clap", "label": "EM_CLAP", "upper": true},
	{"clip": "emote_point_sky", "label": "EM_SKY", "upper": true},
	{"clip": "emote_flex", "label": "EM_HYPE", "upper": true},
	{"clip": "emote_arms_crossed", "label": "EM_COOL", "upper": true},
	{"clip": "celebrate_3", "label": "EM_PUMP", "upper": false},
	{"clip": "dejected", "label": "EM_SAD", "upper": true},
	{"clip": "celebrate_2", "label": "EM_KNEEL", "upper": false},
]
const COOLDOWN := 2.0


static func icon(i: int) -> Texture2D:
	var p := "res://assets/gen/emotes/%s.png" % LIST[i]["clip"]
	return load(p) if ResourceLoader.exists(p) else null
