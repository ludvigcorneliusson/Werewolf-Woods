extends RefCounted
## Item definitions: name, icon (inventory / tools bar), how many fit in one
## inventory slot, and how the item looks lying on the ground. Add an entry here
## to add an item; scripts/pickups.gd, inventory.gd and hud.gd read this table.
##
## "prop" = the map prop image that can be picked up as this item (pebbles and
## sticks already lying in the forest). "world_scale" = size on the ground.
## "gleam" = glints on the ground like the ore nodes (copper_material.tres).

const ITEMS := {
	# Tools (tools bar, keys 1-4). Icons: tools/make_item_icons.py. Spade and
	# pickaxe are placeholders for now: they can be held but don't do anything yet.
	"axe": {"name": "Axe", "icon": preload("res://assets/ui/axe.png"), "tool": true},
	"spade": {"name": "Spade", "icon": preload("res://assets/ui/spade.png"), "tool": true},
	"pickaxe": {"name": "Pickaxe", "icon": preload("res://assets/ui/pickaxe.png"), "tool": true},
	# Stone: from pebbles on the ground ("prop") and from mined stone nodes.
	# Dropped stones show the stone chunk art, shrunk.
	"stone": {"name": "Stone", "icon": preload("res://assets/ui/stone.png"), "stack": 20,
			"world": preload("res://assets/ui/stone.png"), "world_scale": 0.5, "prop": "pebble.png"},
	"twig": {"name": "Twig", "icon": preload("res://assets/ui/twig.png"), "stack": 20,
			"world": preload("res://assets/props/stick.png"), "world_scale": 1.0, "prop": "stick.png"},
	"copper_ore": {"name": "Copper Ore", "icon": preload("res://assets/ui/copper_ore.png"), "stack": 20,
			"world": preload("res://assets/ui/copper_ore.png"), "world_scale": 0.5, "gleam": true},
	"log": {"name": "Log", "icon": preload("res://assets/ui/log.png"), "stack": 10,
			"world": preload("res://assets/props/log_drop.png"), "world_scale": 1.0},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func display_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id.capitalize())


static func stack_size(id: String) -> int:
	return int(ITEMS.get(id, {}).get("stack", 1))


## Item id for a map prop image (e.g. "pebble.png" -> "stone"), or "".
static func item_for_prop(image: String) -> String:
	for id: String in ITEMS:
		if ITEMS[id].get("prop", "") == image:
			return id
	return ""
