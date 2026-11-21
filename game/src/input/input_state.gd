class_name InputState
extends RefCounted
## Device-independent controller state for one human: stick + 4 action buttons.
## Filled by touch UI, keyboard or gamepad. Buttons track press/hold/release edges.

## A pass/tackle, B shoot/slide, C through/jockey, D skill (contextual, touch/gamepad)
## TACKLE, SLIDE, CALL, RUNREQ: explicit actions (PC keyboard).
enum B { A, B, C, D, SPRINT, SWITCH, TACKLE, SLIDE, CALL, RUNREQ }
const N := 10

var stick := Vector2.ZERO      # screen-space, x right, y up (forward)
var held: Array = []
var t_down: Array = []
var pressed: Array = []
var released: Array = []
var hold_time: Array = []      # how long it was held when released
var aim_mode := false          # true when aiming with the camera (mouse / right stick)
var emote := -1                # Emotes.LIST index requested this frame (-1 = none)


func _init() -> void:
	for a in [held, pressed, released]:
		a.resize(N)
		a.fill(false)
	for a in [t_down, hold_time]:
		a.resize(N)
		a.fill(0.0)


func set_button(b: int, down: bool, now: float) -> void:
	if down and not held[b]:
		pressed[b] = true
		t_down[b] = now
	elif not down and held[b]:
		released[b] = true
		hold_time[b] = now - t_down[b]
	held[b] = down


func held_for(b: int, now: float) -> float:
	return now - t_down[b] if held[b] else 0.0


func end_frame() -> void:
	emote = -1
	for i in pressed.size():
		pressed[i] = false
		released[i] = false
