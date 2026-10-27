@tool
extends Node2D
## Editor-only preview of the generated map, so you can see it in the 2D view.
## Nothing it creates is saved into the scene, and it removes itself when the
## game runs (main.gd builds the real map then).

const MapGenerator := preload("res://scripts/map_generator.gd")

@export var map_seed: int = MapGenerator.DEFAULT_SEED
@export_tool_button("Regenerate", "Reload") var regenerate_button = _regenerate

var _map: Node2D


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_regenerate()


func _regenerate() -> void:
	if not Engine.is_editor_hint():
		return
	if _map:
		_map.queue_free()
	_map = MapGenerator.new()
	add_child(_map)   # no owner set -> not saved to main.tscn
	_map.generate(map_seed)
