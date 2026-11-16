class_name CharacterView
extends Node3D
## Skinned footballer (filled in when the character pipeline is ready).

func setup(_p: Footballer, _kit: Dictionary) -> void:
	pass


func sync(_p: Footballer, pos: Vector3, _face: Vector3, _dt: float) -> void:
	position = pos
