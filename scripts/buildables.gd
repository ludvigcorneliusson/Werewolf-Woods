extends RefCounted
## Things you can build (B opens the build menu, scripts/build_menu.gd; placing
## is done by scripts/placer.gd). Add an entry to add a buildable:
##   name      - shown in the menu
##   scene     - what gets placed (its origin = where it stands on the ground)
##   cost      - item id -> count, taken from the backpack when it's placed
##   icon      - menu picture
##   footprint - [centre offset from the origin, radius or Vector2 size] of the
##               ground it needs free (match the scene's collision)
##   variants  - optional: scenes R cycles through while placing (walls). Each
##               has metadata/wall_ends (its two ground ends): the footprint is
##               the strip between them, and it snaps end to end to built walls
##   needs     - optional: "workbench" = only shows up in the build menu while
##               you stand near a workbench you've built (advanced recipes)

const ALL := {
	"campfire": {
		"name": "Campfire",
		"scene": "res://assets/props/campfire.tscn",
		"cost": {"stone": 3, "twig": 3},
		"icon": preload("res://assets/props/campfire.png"),
		"footprint": [Vector2(0, -6), 20.0],
	},
	"torch": {
		"name": "Torch",
		"scene": "res://assets/props/torch.tscn",
		"cost": {"log": 1, "twig": 2},
		"icon": preload("res://assets/props/torch.png"),
		"footprint": [Vector2(0, -2), 6.0],
	},
	"workbench": {
		"name": "Workbench",
		"scene": "res://assets/props/workbench.tscn",
		"cost": {"stone": 5, "log": 5},
		"icon": preload("res://assets/props/workbench.png"),
		"footprint": [Vector2(-3, -6), Vector2(55, 10)],
	},
	"furnace": {
		"name": "Furnace",
		"scene": "res://assets/props/furnace.tscn",
		"cost": {"stone": 10},
		"icon": preload("res://assets/props/furnace.png"),
		"footprint": [Vector2(0, -7), 24.0],
	},
	"wall": {
		"name": "Wall",
		"scene": "res://assets/props/wall_front.tscn",
		"cost": {"log": 2},
		"icon": preload("res://assets/props/wall_front.png"),
		"footprint": [Vector2.ZERO, Vector2(40, 4)],
		"variants": [
			"res://assets/props/wall_front.tscn",
			"res://assets/props/wall_front_plain.tscn",
			"res://assets/props/wall_end.tscn",
			"res://assets/props/wall_diag_up.tscn",
			"res://assets/props/wall_diag_down.tscn",
		],
	},
	# Advanced recipes go here with "needs": "workbench", e.g.
	# "chest": {"name": "Chest", "scene": "res://assets/props/chest.tscn",
	# 		"cost": {"log": 4}, "icon": ..., "footprint": [...], "needs": "workbench"},
}

## How close you must stand to a workbench for its recipes to show (world px,
## measured from the workbench's front edge centre).
const WORKBENCH_RANGE := 90.0


## Is there a built workbench within reach of `pos`?
static func near_workbench(tree: SceneTree, pos: Vector2) -> bool:
	for w in tree.get_nodes_in_group("workbenches"):
		if (w as Node2D).global_position.distance_to(pos) <= WORKBENCH_RANGE:
			return true
	return false


## Recipes available where the player stands, in menu order.
static func available(tree: SceneTree, player_pos: Vector2) -> Array[String]:
	var out: Array[String] = []
	var bench := near_workbench(tree, player_pos)
	for id: String in ALL:
		var needs: String = ALL[id].get("needs", "")
		if needs == "workbench" and not bench:
			continue
		out.append(id)
	return out


static func can_afford(id: String, inventory: Node) -> bool:
	if inventory == null:
		return false
	var cost: Dictionary = ALL[id].cost
	for item: String in cost:
		if inventory.count(item) < int(cost[item]):
			return false
	return true


static func pay(id: String, inventory: Node) -> void:
	var cost: Dictionary = ALL[id].cost
	for item: String in cost:
		inventory.remove(item, int(cost[item]))
