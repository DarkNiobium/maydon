class_name InputState
extends RefCounted
## Device-independent controller state for one human: stick + 4 action buttons.
## Filled by touch UI, keyboard or gamepad. Buttons track press/hold/release edges.

enum B { A, B, C, D, SPRINT, SWITCH }   # A pass/tackle, B shoot/slide, C through/jockey, D skill

var stick := Vector2.ZERO      # screen-space, x right, y up (forward)
var held := [false, false, false, false, false, false]
var t_down := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var pressed := [false, false, false, false, false, false]
var released := [false, false, false, false, false, false]
var hold_time := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # how long it was held when released


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
	for i in pressed.size():
		pressed[i] = false
		released[i] = false
